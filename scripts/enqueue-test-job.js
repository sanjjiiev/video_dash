#!/usr/bin/env node
'use strict';

/**
 * enqueue-test-job.js
 *
 * Development utility: manually enqueue a transcoding job.
 *
 * Usage (from the project root, after `docker compose up`):
 *   node scripts/enqueue-test-job.js <path-to-local-mp4>
 *
 * What it does:
 *  1. Uploads your local MP4 to the `raw-uploads` MinIO bucket.
 *  2. Enqueues a BullMQ job on the `transcode` queue.
 *  3. Prints the job ID so you can monitor Worker logs.
 *
 * Prerequisites:
 *   npm install minio bullmq ioredis uuid   (from the project root, not /worker)
 */

const path  = require('path');
const fs    = require('fs');
const Minio = require('minio');
const { Queue } = require('bullmq');
const { v4: uuidv4 } = require('uuid');

const inputFile = process.argv[2];

if (!inputFile) {
  console.error('Usage: node enqueue-test-job.js <path-to-local.mp4>');
  process.exit(1);
}

const absPath = path.resolve(inputFile);
if (!fs.existsSync(absPath)) {
  console.error(`File not found: ${absPath}`);
  process.exit(1);
}

async function main() {
  const videoId = uuidv4();
  const s3Key   = `${videoId}/source.mp4`;

  // ── MinIO client ──────────────────────────────────────────────────────────
  const minio = new Minio.Client({
    endPoint:  'localhost',
    port:      9000,
    useSSL:    false,
    accessKey: process.env.MINIO_ACCESS_KEY ?? 'minioadmin',
    secretKey: process.env.MINIO_SECRET_KEY ?? 'minioadmin',
  });

  // Ensure raw-uploads bucket exists
  const rawBucket = 'raw-uploads';
  if (!(await minio.bucketExists(rawBucket))) {
    await minio.makeBucket(rawBucket, 'us-east-1');
    console.log(`Created bucket: ${rawBucket}`);
  }

  // Upload the file
  console.log(`Uploading ${absPath} → minio://${rawBucket}/${s3Key} ...`);
  await minio.fPutObject(rawBucket, s3Key, absPath, {
    'Content-Type': 'video/mp4',
  });
  console.log('Upload complete.');

  // ── BullMQ Queue ──────────────────────────────────────────────────────────
  const queue = new Queue('transcode', {
    connection: {
      host: process.env.REDIS_HOST ?? 'localhost',
      port: parseInt(process.env.REDIS_PORT ?? '6379', 10),
    },
  });

  const job = await queue.add(
    'transcode-video',
    {
      videoId,
      s3Key,
      title: `Test Video — ${path.basename(inputFile)}`,
    },
    {
      attempts: 3,              // retry up to 3 times on transient failure
      backoff: { type: 'exponential', delay: 10_000 },
      removeOnComplete: { age: 3600 },  // keep completed jobs for 1 hr
      removeOnFail:     { age: 86400 }, // keep failed jobs for 24 hrs
    }
  );

  console.log(`\n✅  Job enqueued!`);
  console.log(`   Job ID  : ${job.id}`);
  console.log(`   Video ID: ${videoId}`);
  console.log(`\nWatch worker logs with: docker compose logs -f worker`);

  await queue.close();
}

main().catch((err) => {
  console.error('Error:', err.message);
  process.exit(1);
});
