'use strict';

/**
 * queueService.js
 *
 * Singleton BullMQ Queue for the API to enqueue transcoding jobs.
 * The Queue is connection-shared — we never create a new Queue per request.
 */

const { Queue } = require('bullmq');
const config    = require('../config');
const logger    = require('../logger');

let _queue = null;

function getQueue() {
  if (!_queue) {
    _queue = new Queue(config.queue.name, {
      connection: {
        host:     config.redis.host,
        port:     config.redis.port,
        password: config.redis.password,
        db:       config.redis.db,
      },
      defaultJobOptions: {
        attempts: 3,
        backoff: { type: 'exponential', delay: 10_000 },
        removeOnComplete: { age: 3600 },
        removeOnFail:     { age: 86400 },
      },
    });

    _queue.on('error', (err) => {
      logger.error({ err }, 'BullMQ Queue error');
    });
  }
  return _queue;
}

/**
 * Enqueue a transcoding job for a video.
 *
 * @param {object} params
 * @param {string} params.videoId  - UUID of the video record (already in DB)
 * @param {string} params.s3Key    - MinIO object key of the raw upload
 * @param {string} params.title    - Video title (for log correlation)
 * @returns {Promise<string>} jobId
 */
async function enqueueTranscodeJob({ videoId, s3Key, title }) {
  const queue = getQueue();
  const job   = await queue.add('transcode-video', { videoId, s3Key, title });
  logger.info({ jobId: job.id, videoId, s3Key }, 'Transcoding job enqueued');
  return job.id;
}

/**
 * Gracefully close the queue connection on shutdown.
 */
async function closeQueue() {
  if (_queue) {
    await _queue.close();
    _queue = null;
  }
}

module.exports = { enqueueTranscodeJob, closeQueue };
