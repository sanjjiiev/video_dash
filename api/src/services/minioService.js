'use strict';

/**
 * minioService.js
 *
 * Thin service layer over the MinIO client.
 * Exposes high-level operations used by route handlers:
 *   - Streaming HLS objects (playlists + segments) to HTTP responses
 *   - Serving AES-128 encryption keys from the private key bucket
 *   - Generating presigned upload URLs (optional flow for large files)
 */

const Minio   = require('minio');
const config  = require('../config');
const logger  = require('../logger');

const client = new Minio.Client({
  endPoint:  config.minio.endpoint,
  port:      config.minio.port,
  useSSL:    config.minio.useSSL,
  accessKey: config.minio.accessKey,
  secretKey: config.minio.secretKey,
});

const { videos: VIDEOS_BUCKET, keys: KEYS_BUCKET } = config.minio.buckets;

// ─────────────────────────────────────────────────────────────────────────────
// HLS streaming
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Pipe an HLS object (playlist or segment) from MinIO to an Express response.
 *
 * Called by the /hls/:videoId/* route after authentication passes.
 * Sets appropriate Content-Type and cache headers before streaming.
 *
 * @param {string}   bucket      - MinIO bucket name
 * @param {string}   objectKey   - Full object key in the bucket
 * @param {object}   res         - Express response object
 */
async function streamHlsObject(bucket, objectKey, res) {
  // Fetch object metadata first (stat) to get size and content type
  let stat;
  try {
    stat = await client.statObject(bucket, objectKey);
  } catch (err) {
    if (err.code === 'NotFound' || err.code === 'NoSuchKey') {
      res.status(404).json({ error: 'Segment not found' });
      return;
    }
    throw err;
  }

  const ext = objectKey.split('.').pop().toLowerCase();

  // Set headers
  res.setHeader('Content-Length', stat.size);
  res.setHeader('Content-Type', contentTypeFor(ext));
  res.setHeader('Accept-Ranges', 'bytes');

  // HLS .ts segments are immutable (FFmpeg writes them once, never modifies them).
  // Cache them aggressively at Nginx. .m3u8 playlists are also immutable for VOD.
  if (ext === 'ts') {
    res.setHeader('Cache-Control', 'public, max-age=86400, immutable');
  } else if (ext === 'm3u8') {
    res.setHeader('Cache-Control', 'public, max-age=60');
  }

  // Stream directly — no buffering in the API process
  const stream = await client.getObject(bucket, objectKey);
  stream.pipe(res);

  stream.on('error', (err) => {
    logger.error({ err, objectKey }, 'Error streaming HLS object');
    if (!res.headersSent) {
      res.status(500).json({ error: 'Stream error' });
    }
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// AES-128 key delivery
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Fetch the AES-128 decryption key for a video from the private MinIO bucket.
 * Returns the raw 16-byte Buffer.
 *
 * @param {string} videoId
 * @returns {Promise<Buffer>}
 * @throws if key is not found or MinIO is unreachable
 */
async function getEncryptionKey(videoId) {
  const objectKey = `${videoId}/enc.key`;

  const stream = await client.getObject(KEYS_BUCKET, objectKey);

  return new Promise((resolve, reject) => {
    const chunks = [];
    stream.on('data',  (chunk) => chunks.push(chunk));
    stream.on('end',   ()      => resolve(Buffer.concat(chunks)));
    stream.on('error', reject);
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Presigned URLs (optional large-file upload flow)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Generate a presigned PUT URL so the client can upload a large file
 * directly to MinIO without routing through the API server.
 * Expiry is controlled by config.minio.presignedUploadExpiry (default 1 hour).
 *
 * @param {string} videoId  - Pre-generated UUID for the video
 * @returns {Promise<{ uploadUrl: string, objectKey: string }>}
 */
async function createPresignedUploadUrl(videoId) {
  const objectKey = `${videoId}/source.mp4`;
  const url = await client.presignedPutObject(
    config.minio.buckets.rawUploads,
    objectKey,
    config.minio.presignedUploadExpiry
  );
  return { uploadUrl: url, objectKey };
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

function contentTypeFor(ext) {
  const map = {
    m3u8: 'application/vnd.apple.mpegurl',
    ts:   'video/MP2T',
    key:  'application/octet-stream',
    mp4:  'video/mp4',
  };
  return map[ext] ?? 'application/octet-stream';
}

module.exports = {
  client,
  VIDEOS_BUCKET,
  KEYS_BUCKET,
  streamHlsObject,
  getEncryptionKey,
  createPresignedUploadUrl,
};
