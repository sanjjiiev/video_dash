'use strict';

/**
 * worker.js
 *
 * BullMQ Worker — the entrypoint for the Docker container.
 *
 * Lifecycle:
 *  1. On startup: validate env vars, ensure MinIO buckets exist, register
 *     the BullMQ worker to listen on the `transcode` queue.
 *  2. On each job: download the source MP4 from MinIO to the local scratch
 *     directory, invoke the transcoder, then update the job result in Redis.
 *  3. On shutdown (SIGTERM/SIGINT): drain in-flight jobs gracefully before
 *     exiting (Kubernetes-friendly rolling deployments).
 *
 * Queue contract — each job's `data` object must include:
 * {
 *   videoId:   string,   // Unique ID for the video (UUIDv4)
 *   s3Key:     string,   // Path to the source MP4 inside the `raw-uploads` MinIO bucket
 *   title:     string,   // Human-readable title (stored in job result)
 * }
 *
 * On completion, the job result is:
 * {
 *   videoId:        string,
 *   masterPlaylist: string,   // MinIO key of the master.m3u8
 *   renditions:     string[], // ['1080p', '720p', '480p']
 *   durationMs:     number,   // Wall-clock time for the entire transcode + upload
 * }
 */

const path    = require('path');
const fsp     = require('fs/promises');
const { Worker, UnrecoverableError } = require('bullmq');
const logger  = require('./logger');
const { client: minioClient, ensureBucketsExist } = require('./minioClient');
const { transcode } = require('./transcoder');

// ─────────────────────────────────────────────────────────────────────────────
// Configuration (all via environment variables)
// ─────────────────────────────────────────────────────────────────────────────
const REQUIRED_ENV = [
  'REDIS_HOST',
  'MINIO_ENDPOINT',
  'MINIO_ACCESS_KEY',
  'MINIO_SECRET_KEY',
];

const REDIS_HOST      = process.env.REDIS_HOST  ?? 'localhost';
const REDIS_PORT      = parseInt(process.env.REDIS_PORT ?? '6379', 10);
const REDIS_PASSWORD  = process.env.REDIS_PASSWORD;         // optional
const REDIS_DB        = parseInt(process.env.REDIS_DB ?? '0', 10);

const QUEUE_NAME      = process.env.QUEUE_NAME  ?? 'transcode';
const RAW_BUCKET      = process.env.MINIO_RAW_BUCKET ?? 'raw-uploads';
const SCRATCH_ROOT    = process.env.SCRATCH_DIR ?? '/tmp/transcode';

// Number of jobs to process in parallel. Keep at 1 for CPU-bound FFmpeg work
// unless the host has many cores — FFmpeg itself uses multiple threads internally.
const CONCURRENCY     = parseInt(process.env.WORKER_CONCURRENCY ?? '1', 10);


// ─────────────────────────────────────────────────────────────────────────────
// Startup validation
// ─────────────────────────────────────────────────────────────────────────────
function validateEnv() {
  const missing = REQUIRED_ENV.filter(k => !process.env[k]);
  if (missing.length > 0) {
    logger.error({ missing }, 'Missing required environment variables. Exiting.');
    process.exit(1);
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Job processor
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Downloads the raw MP4 from MinIO to a local scratch path.
 *
 * @param {string} s3Key    - MinIO object key in the `raw-uploads` bucket
 * @param {string} destPath - Local path to save the file
 */
async function downloadSourceFile(s3Key, destPath) {
  await fsp.mkdir(path.dirname(destPath), { recursive: true });

  await new Promise((resolve, reject) => {
    minioClient.getObject(RAW_BUCKET, s3Key, (err, stream) => {
      if (err) return reject(err);

      const { createWriteStream } = require('fs');
      const ws = createWriteStream(destPath);
      stream.pipe(ws);
      ws.on('finish', resolve);
      ws.on('error', reject);
      stream.on('error', reject);
    });
  });
}


/**
 * The BullMQ job processor function.
 * Called by the Worker once per job. Throwing here marks the job as failed
 * (BullMQ will retry based on the job's `attempts` setting).
 *
 * Wrapping in `UnrecoverableError` prevents retries for deterministic failures
 * (e.g., file not found in MinIO — retrying won't help).
 */
async function processJob(job) {
  const { videoId, s3Key, title } = job.data;
  const log = logger.child({ jobId: job.id, videoId, title });

  if (!videoId || !s3Key) {
    throw new UnrecoverableError(
      `Invalid job payload: missing videoId or s3Key. Data: ${JSON.stringify(job.data)}`
    );
  }

  log.info({ s3Key, RAW_BUCKET }, 'Processing transcoding job');

  const t0 = Date.now();
  const localInputPath = path.join(SCRATCH_ROOT, videoId, 'source.mp4');

  // ── 1. Download source file from MinIO ────────────────────────────────────
  await job.updateProgress(5);
  log.info({ localInputPath }, 'Downloading source MP4 from MinIO');

  try {
    await downloadSourceFile(s3Key, localInputPath);
  } catch (err) {
    // If the file doesn't exist in MinIO, no point retrying
    if (err.code === 'NoSuchKey') {
      throw new UnrecoverableError(`Source file not found in MinIO: ${s3Key}`);
    }
    throw err; // transient network err — allow BullMQ to retry
  }

  log.info('Source MP4 downloaded successfully');

  // ── 2. Transcode + encrypt + upload ───────────────────────────────────────
  await job.updateProgress(10);

  const result = await transcode({
    inputPath: localInputPath,
    videoId,
    jobId: job.id,
    onProgress: async (pct) => {
      // FFmpeg progress: map from 0-100 to the 10-95 range of the full job
      const jobPct = 10 + Math.floor(pct * 0.85);
      await job.updateProgress(jobPct);
    },
  });

  // ── 3. Finalize ───────────────────────────────────────────────────────────
  const durationMs = Date.now() - t0;
  await job.updateProgress(100);

  const output = {
    videoId,
    title,
    masterPlaylist: result.masterPlaylist,
    renditions: result.renditions,
    durationMs,
  };

  log.info({ output }, `Job completed in ${(durationMs / 1000).toFixed(1)}s`);

  return output;
}


// ─────────────────────────────────────────────────────────────────────────────
// Worker bootstrap
// ─────────────────────────────────────────────────────────────────────────────
async function main() {
  validateEnv();

  // Ensure MinIO buckets exist (idempotent)
  await ensureBucketsExist();

  // Ensure scratch directory exists and is writable
  await fsp.mkdir(SCRATCH_ROOT, { recursive: true });

  // ── Create BullMQ Worker ────────────────────────────────────────────────
  const worker = new Worker(QUEUE_NAME, processJob, {
    connection: {
      host:     REDIS_HOST,
      port:     REDIS_PORT,
      password: REDIS_PASSWORD,
      db:       REDIS_DB,
    },
    concurrency: CONCURRENCY,

    // Job locking: how long (ms) a job lock is held before considered stale.
    // Set longer than the worst-case transcode duration to prevent re-queuing
    // a job that is still actively processing.
    lockDuration: 5 * 60 * 1000, // 5 minutes

    // Retry settings (applied at the worker level as defaults)
    // Per-job settings in job.opts.attempts override these.
    settings: {
      backoffStrategy: (attemptsMade) => {
        // Exponential backoff: 10s, 40s, 160s
        return Math.min(Math.pow(4, attemptsMade) * 10_000, 300_000);
      },
    },
  });

  // ── Event handlers ─────────────────────────────────────────────────────
  worker.on('active', (job) =>
    logger.info({ jobId: job.id, videoId: job.data.videoId }, 'Job started')
  );

  worker.on('progress', (job, progress) =>
    logger.debug({ jobId: job.id, progress }, 'Job progress update')
  );

  worker.on('completed', (job, result) =>
    logger.info({ jobId: job.id, result }, 'Job completed successfully')
  );

  worker.on('failed', (job, err) =>
    logger.error(
      { jobId: job?.id, videoId: job?.data?.videoId, err: err.message, stack: err.stack },
      'Job failed'
    )
  );

  worker.on('error', (err) =>
    logger.error({ err }, 'Worker-level error (e.g., Redis connection issue)')
  );

  logger.info(
    {
      queue: QUEUE_NAME,
      concurrency: CONCURRENCY,
      redis: `${REDIS_HOST}:${REDIS_PORT}`,
    },
    '🎬  Transcoding worker is ready and listening for jobs'
  );

  // ── Graceful shutdown ──────────────────────────────────────────────────
  // On SIGTERM (Docker stop, Kubernetes pod eviction):
  //  1. Stop accepting new jobs.
  //  2. Wait for in-flight job(s) to complete.
  //  3. Close the Redis connection cleanly.
  const shutdown = async (signal) => {
    logger.info({ signal }, 'Shutdown signal received — draining worker...');
    await worker.close();
    logger.info('Worker drained. Goodbye.');
    process.exit(0);
  };

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT',  () => shutdown('SIGINT'));

  // Catch-all for unhandled promise rejections so we get a full stack trace
  process.on('unhandledRejection', (reason, promise) => {
    logger.error({ reason, promise }, 'Unhandled promise rejection — investigate immediately');
  });
}

// ─────────────────────────────────────────────────────────────────────────────
main().catch((err) => {
  logger.error({ err }, 'Fatal: worker failed to start');
  process.exit(1);
});
