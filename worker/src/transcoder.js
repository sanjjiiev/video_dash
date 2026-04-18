'use strict';

/**
 * transcoder.js
 *
 * Core FFmpeg transcoding engine.
 *
 * Responsibilities:
 *  1. Generate a cryptographically secure AES-128 key + IV.
 *  2. Write an HLS keyinfo file that FFmpeg reads during transcoding.
 *  3. Execute a single FFmpeg pass that splits the input MP4 into THREE
 *     quality renditions simultaneously (1080p, 720p, 480p), each with:
 *       - AES-128 encrypted .ts segments (3-5 second chunks)
 *       - A per-rendition .m3u8 sub-playlist
 *  4. Generate a master .m3u8 playlist that references all sub-playlists
 *     (enables Adaptive Bitrate Streaming on the client).
 *  5. Upload everything to MinIO:
 *       - Encryption key  → private `encryption-keys` bucket
 *       - HLS segments/playlists → private `videos` bucket
 *  6. Clean up the local scratch directory unconditionally (even on error).
 *
 * Security notes:
 *  - Key is generated with crypto.randomBytes (CSPRNG) — never Math.random().
 *  - The key NEVER leaves the worker in plaintext logs; only its hex length is logged.
 *  - The keyUri in the .m3u8 playlists points to the API server endpoint
 *    (Phase 2), NOT to MinIO directly. The API validates session/token before
 *    streaming the key bytes to the player.
 *  - FFmpeg runs with resource limits applied at the Docker level (ulimits).
 */

const crypto     = require('crypto');
const fs         = require('fs');
const fsp        = require('fs/promises');
const path       = require('path');
const { spawn }  = require('child_process');

const logger      = require('./logger');
const {
  VIDEOS_BUCKET,
  uploadDirectory,
  uploadEncryptionKey,
} = require('./minioClient');

// ─────────────────────────────────────────────────────────────────────────────
// Rendition ladder — edit only this table to change quality tiers.
// bitrateK is in kbps. All values are conservative defaults; tune per-content.
// ─────────────────────────────────────────────────────────────────────────────
const RENDITIONS = [
  { name: '1080p', height: 1080, videoBitrateK: 4000, audioBitrateK: 192, maxRateK: 4500, bufSizeK: 8000 },
  { name: '720p',  height: 720,  videoBitrateK: 2500, audioBitrateK: 128, maxRateK: 2750, bufSizeK: 5000 },
  { name: '480p',  height: 480,  videoBitrateK: 1000, audioBitrateK: 96,  maxRateK: 1100, bufSizeK: 2000 },
];

// HLS segment duration in seconds (Apple recommends 4-6 s for live; 4 s is safe for VOD)
const HLS_TIME = 4;

// Scratch directory root (must be writable by the `ffworker` user inside Docker)
const SCRATCH_ROOT = process.env.SCRATCH_DIR ?? '/tmp/transcode';

// The public-facing URL the player will call to get the decryption key.
// Phase 2's API will handle auth at this endpoint.
const KEY_SERVER_BASE = process.env.KEY_SERVER_BASE_URL ?? 'http://localhost:3000';


// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Transcode an MP4 file into AES-128 encrypted, multi-rendition HLS,
 * then upload all artifacts to MinIO.
 *
 * @param {object} params
 * @param {string} params.inputPath  - Absolute path to the source MP4 file
 * @param {string} params.videoId    - Unique video ID (used as MinIO key prefix)
 * @param {string} params.jobId      - BullMQ job ID (for log correlation)
 * @param {Function} params.onProgress - Callback(percent: number) for job progress
 *
 * @returns {Promise<{ minioPrefix: string, renditions: string[] }>}
 */
async function transcode({ inputPath, videoId, jobId, onProgress }) {
  const log = logger.child({ jobId, videoId });

  // Each job gets its own isolated workspace inside the shared scratch dir.
  // If this worker crashes mid-job, Docker's ephemeral container FS ensures cleanup.
  const workDir = path.join(SCRATCH_ROOT, videoId);
  await fsp.mkdir(workDir, { recursive: true });

  log.info({ inputPath }, 'Transcoding started');

  try {
    // ── Step 1: Generate AES-128 key & IV ───────────────────────────────────
    const { keyPath, keyInfoPath } = await generateEncryptionArtifacts(workDir, videoId, log);

    // ── Step 2: FFmpeg transcode (single pass, all renditions) ──────────────
    await runFFmpeg({ inputPath, workDir, keyInfoPath, onProgress, log });

    // ── Step 3: Write the master HLS playlist ───────────────────────────────
    const masterPlaylistPath = await writeMasterPlaylist(workDir, log);

    // ── Step 4: Upload everything to MinIO ──────────────────────────────────
    const minioPrefix = `videos/${videoId}`;

    // 4a. Upload the raw key to the PRIVATE keys bucket
    const keyBuf = await fsp.readFile(keyPath);
    await uploadEncryptionKey(videoId, keyBuf);

    // 4b. Upload all HLS segments, sub-playlists, and master playlist
    const uploaded = await uploadDirectory(workDir, VIDEOS_BUCKET, minioPrefix);
    log.info({ uploaded, minioPrefix }, 'All HLS artifacts uploaded to MinIO');

    return {
      minioPrefix,
      masterPlaylist: `${minioPrefix}/master.m3u8`,
      renditions: RENDITIONS.map(r => r.name),
    };

  } finally {
    // ── Cleanup: Always remove the scratch directory, even on error ──────────
    await fsp.rm(workDir, { recursive: true, force: true });
    log.info('Scratch directory cleaned up');
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Generates:
 *   - `enc.key`      : 16 raw bytes (AES-128 key)
 *   - `enc.keyinfo`  : FFmpeg HLS keyinfo file
 *
 * The keyinfo format (3 lines, all required by FFmpeg):
 *   Line 1: URI the player will use to fetch the key (→ our API endpoint)
 *   Line 2: Local filesystem path to the key file (read by FFmpeg at transcode time)
 *   Line 3: IV as a hex string (16 bytes = 32 hex chars)
 *
 * @returns {{ keyPath: string, keyInfoPath: string }}
 */
async function generateEncryptionArtifacts(workDir, videoId, log) {
  // AES-128 requires exactly 16 bytes (128 bits)
  const key = crypto.randomBytes(16);
  // IV: standard practice is to derive from the video ID for determinism,
  // but a random IV per-video is stronger. We use random here.
  const iv  = crypto.randomBytes(16);

  const keyPath      = path.join(workDir, 'enc.key');
  const keyInfoPath  = path.join(workDir, 'enc.keyinfo');

  // The key URI the HLS player will call to retrieve the decryption key.
  // Format: /api/v1/keys/:videoId  — served by the Phase 2 API with auth checks.
  const keyUri = `${KEY_SERVER_BASE}/api/v1/keys/${videoId}`;

  await fsp.writeFile(keyPath, key);
  await fsp.writeFile(
    keyInfoPath,
    [
      keyUri,                       // Line 1: URI for player
      keyPath,                      // Line 2: local path for FFmpeg
      iv.toString('hex'),           // Line 3: IV hex string
    ].join('\n')
  );

  // Log only non-sensitive metadata — NEVER log the key bytes
  log.info({ keyUri, ivLength: iv.length * 8 }, 'AES-128 key + keyinfo generated');

  return { keyPath, keyInfoPath };
}


/**
 * Builds and executes the FFmpeg command.
 *
 * Design decisions:
 *  - Single pass: FFmpeg reads the input ONCE and writes all 3 renditions.
 *    This is significantly faster than running FFmpeg 3 times separately.
 *  - `-filter_complex`: splits the input into 3 scaled video streams and 3
 *    audio streams, each going to a separate output.
 *  - `-hls_key_info_file`: makes FFmpeg apply AES-128 encryption to every
 *    `.ts` segment it writes for each rendition.
 *  - `-hls_segment_filename`: uses a pattern like `480p/seg%04d.ts` so
 *    segments are organized in per-rendition subdirectories.
 *  - `-hls_flags independent_segments`: every segment is independently
 *    decodable (important for seeking and ABR switching).
 *  - `-preset veryfast`: prioritizes encode speed over compression ratio.
 *    Change to `medium` for better file sizes in production at the cost of
 *    higher CPU time.
 *  - `-c:a aac -ac 2`: stereo AAC audio (universally compatible).
 *  - `-movflags +faststart`: (not needed for HLS TS, but used on MP4 outputs)
 */
async function runFFmpeg({ inputPath, workDir, keyInfoPath, onProgress, log }) {
  // Create per-rendition output directories
  for (const r of RENDITIONS) {
    await fsp.mkdir(path.join(workDir, r.name), { recursive: true });
  }

  // ── Build filter_complex ────────────────────────────────────────────────
  // Split video into N scaled streams + pass audio through N times.
  // [0:v] split=3[v1][v2][v3]
  // [v1] scale=-2:1080 [out1080]
  // [v2] scale=-2:720  [out720]
  // [v3] scale=-2:480  [out480]
  const splitCount     = RENDITIONS.length;
  const splitOutputs   = RENDITIONS.map((_, i) => `[vin${i}]`).join('');
  const scaleFilters   = RENDITIONS.map((r, i) =>
    `[vin${i}]scale=-2:${r.height}[vout${i}]`
  ).join(';');
  const filterComplex  = `[0:v]split=${splitCount}${splitOutputs};${scaleFilters}`;

  // ── Build per-rendition output arguments ────────────────────────────────
  // Each rendition maps to [voutN] for video and [0:a] for audio.
  const renditionArgs = RENDITIONS.flatMap((r, i) => [
    '-map', `[vout${i}]`,
    '-map', '0:a',

    // Video codec & bitrate control
    `-c:v:${i}`, 'libx264',
    `-b:v:${i}`, `${r.videoBitrateK}k`,
    `-maxrate:${i}`, `${r.maxRateK}k`,
    `-bufsize:${i}`, `${r.bufSizeK}k`,
    `-preset:${i}`, 'veryfast',
    // Ensure keyframes align with HLS segment boundaries for clean cuts
    `-g:${i}`, String(HLS_TIME * 30),  // assuming 30fps; FFmpeg adjusts for actual fps
    `-keyint_min:${i}`, String(HLS_TIME * 30),
    `-sc_threshold:${i}`, '0',          // disable scene-change keyframe insertion

    // Audio codec
    `-c:a:${i}`, 'aac',
    `-b:a:${i}`, `${r.audioBitrateK}k`,
    '-ac', '2',  // stereo

    // HLS muxer settings
    '-f', 'hls',
    '-hls_time', String(HLS_TIME),
    '-hls_playlist_type', 'vod',
    '-hls_flags', 'independent_segments',
    '-hls_segment_type', 'mpegts',
    '-hls_key_info_file', keyInfoPath,
    '-hls_segment_filename', path.join(workDir, r.name, 'seg%04d.ts'),

    // Sub-playlist output path
    path.join(workDir, r.name, 'playlist.m3u8'),
  ]);

  // ── Assemble full FFmpeg argv ────────────────────────────────────────────
  const ffmpegArgs = [
    '-y',                     // overwrite output without prompting
    '-loglevel', 'warning',   // suppress INFO spam; warnings+errors only
    '-progress', 'pipe:1',    // write progress stats to stdout in key=value format
    '-i', inputPath,          // input file
    '-filter_complex', filterComplex,
    ...renditionArgs,
  ];

  log.info({ args: ffmpegArgs.join(' ') }, 'Spawning FFmpeg');

  await new Promise((resolve, reject) => {
    const ff = spawn('ffmpeg', ffmpegArgs, {
      // stderr inherits → goes to container logs. stdout is parsed for progress.
      stdio: ['ignore', 'pipe', 'inherit'],
    });

    // Parse `ffmpeg -progress pipe:1` output (key=value pairs, one per line)
    let duration = null;
    let progressBuf = '';

    ff.stdout.on('data', (chunk) => {
      progressBuf += chunk.toString();
      const lines = progressBuf.split('\n');
      progressBuf = lines.pop(); // keep incomplete last line for next chunk

      for (const line of lines) {
        const [key, val] = line.trim().split('=');

        if (key === 'out_time_ms' && duration) {
          const encodedMs = parseInt(val, 10) / 1000;
          const pct = Math.min(100, Math.round((encodedMs / duration) * 100));
          onProgress?.(pct);
        }
      }
    });

    // Extract duration from FFmpeg's stderr header for progress calculation.
    // We inherit stderr, so we won't get it here — use ffprobe instead if needed.
    // For now, duration-based progress is best-effort.

    ff.on('error', (err) => {
      log.error({ err }, 'Failed to spawn FFmpeg — is it installed?');
      reject(err);
    });

    ff.on('close', (code) => {
      if (code === 0) {
        log.info('FFmpeg process exited successfully');
        resolve();
      } else {
        reject(new Error(`FFmpeg exited with code ${code}`));
      }
    });
  });
}


/**
 * Writes the HLS master playlist (`master.m3u8`) that lists all renditions.
 * HLS clients read this first and then pick the best sub-playlist based on
 * available bandwidth (Adaptive Bitrate Streaming).
 *
 * Format per EXT-X-STREAM-INF spec (RFC 8216):
 *   #EXTM3U
 *   #EXT-X-VERSION:3
 *   #EXT-X-STREAM-INF:BANDWIDTH=<bps>,RESOLUTION=<WxH>,CODECS="...",NAME="..."
 *   <rendition-name>/playlist.m3u8
 *
 * BANDWIDTH is in bits per second (bps), not kbps.
 */
async function writeMasterPlaylist(workDir, log) {
  // Approximate pixel widths assuming 16:9 AR for BANDWIDTH label
  const widthMap = { 1080: 1920, 720: 1280, 480: 854 };

  const lines = ['#EXTM3U', '#EXT-X-VERSION:3', ''];

  for (const r of RENDITIONS) {
    const bandwidth = (r.videoBitrateK + r.audioBitrateK) * 1000; // kbps → bps
    const width     = widthMap[r.height] ?? r.height * 16 / 9;
    const resolution = `${width}x${r.height}`;

    lines.push(
      `#EXT-X-STREAM-INF:BANDWIDTH=${bandwidth},RESOLUTION=${resolution},` +
      `CODECS="avc1.640028,mp4a.40.2",NAME="${r.name}"`
    );
    lines.push(`${r.name}/playlist.m3u8`);
    lines.push('');
  }

  const masterPath = path.join(workDir, 'master.m3u8');
  await fsp.writeFile(masterPath, lines.join('\n'));
  log.info({ masterPath }, 'Master HLS playlist written');
  return masterPath;
}


module.exports = { transcode };
