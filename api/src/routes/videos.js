'use strict';

/**
 * routes/videos.js
 *
 * GET  /api/v1/videos                    — Paginated video listing
 * GET  /api/v1/videos/:id                — Single video metadata
 * POST /api/v1/videos/upload             — Multipart upload → enqueue transcode job
 * POST /api/v1/videos/presign            — Get presigned PUT URL for direct-to-MinIO upload
 * POST /api/v1/videos/:id/confirm        — Confirm direct upload complete, enqueue job
 * PATCH /api/v1/videos/:id/status        — [Internal/Worker] Update video status
 * DELETE /api/v1/videos/:id              — Soft-delete a video
 *
 * Worker webhook (called by the worker after job completion):
 * POST /api/v1/videos/:id/complete       — Mark video as ready, store rendition info
 */

const express   = require('express');
const { body, query: queryParam, param, validationResult } = require('express-validator');
const { v4: uuidv4 } = require('uuid');

const db          = require('../db');
const logger      = require('../logger');
const { requireAuth, requireRole } = require('../middleware/auth');
const { uploadLimiter, apiLimiter } = require('../middleware/rateLimiter');
const { uploadMiddleware }          = require('../middleware/upload');
const { createPresignedUploadUrl }  = require('../services/minioService');
const { enqueueTranscodeJob }       = require('../services/queueService');
const { createError }               = require('../middleware/errorHandler');

const router = express.Router();

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/videos  — Public paginated listing (only 'ready' videos)
// ─────────────────────────────────────────────────────────────────────────────
router.get('/',
  apiLimiter,
  [
    queryParam('page').optional().isInt({ min: 1 }).toInt(),
    queryParam('limit').optional().isInt({ min: 1, max: 50 }).toInt(),
    queryParam('search').optional().isString().trim().escape(),
  ],
  async (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Invalid query params', details: errors.array() });
    }

    const page  = req.query.page  ?? 1;
    const limit = req.query.limit ?? 20;
    const offset = (page - 1) * limit;
    const search = req.query.search;

    try {
      const whereClause = search
        ? `WHERE v.status = 'ready' AND v.deleted_at IS NULL AND v.title ILIKE $3`
        : `WHERE v.status = 'ready' AND v.deleted_at IS NULL`;

      const params = search
        ? [limit, offset, `%${search}%`]
        : [limit, offset];

      const result = await db.query(
        `SELECT v.id, v.title, v.description, v.duration_seconds, v.thumbnail_key,
                v.created_at, u.email AS owner_email
         FROM videos v
         JOIN users u ON u.id = v.owner_id
         ${whereClause}
         ORDER BY v.created_at DESC
         LIMIT $1 OFFSET $2`,
        params
      );

      const countResult = await db.query(
        `SELECT COUNT(*) AS total FROM videos v
         ${whereClause.replace('$3', '$1')}`,
        search ? [`%${search}%`] : []
      );

      res.json({
        videos: result.rows,
        pagination: {
          page,
          limit,
          total: parseInt(countResult.rows[0].total, 10),
          totalPages: Math.ceil(countResult.rows[0].total / limit),
        },
      });
    } catch (err) {
      next(err);
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/videos/:id  — Single video detail
// ─────────────────────────────────────────────────────────────────────────────
router.get('/:id',
  apiLimiter,
  [param('id').isUUID()],
  async (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ error: 'Invalid video ID' });

    try {
      const result = await db.query(
        `SELECT v.id, v.title, v.description, v.status, v.duration_seconds,
                v.thumbnail_key, v.created_at, v.job_id,
                u.email AS owner_email,
                json_agg(
                  json_build_object('name', r.name, 'bitrate_k', r.bitrate_k)
                  ORDER BY r.name DESC
                ) FILTER (WHERE r.id IS NOT NULL) AS renditions
         FROM videos v
         JOIN users u ON u.id = v.owner_id
         LEFT JOIN video_renditions r ON r.video_id = v.id
         WHERE v.id = $1 AND v.deleted_at IS NULL
         GROUP BY v.id, u.email`,
        [req.params.id]
      );

      if (!result.rows[0]) {
        return res.status(404).json({ error: 'Video not found' });
      }
      res.json(result.rows[0]);
    } catch (err) {
      next(err);
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/videos/upload  — Multipart upload (streams directly to MinIO)
// ─────────────────────────────────────────────────────────────────────────────
router.post('/upload',
  requireAuth,
  requireRole('uploader', 'admin'),
  uploadLimiter,
  uploadMiddleware.single('video'),   // streams to MinIO inside the middleware
  [body('title').notEmpty().trim().isLength({ max: 500 })],
  async (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    }

    if (!req.file) {
      return res.status(400).json({ error: 'No video file provided' });
    }

    const { videoId, key: s3Key } = req.file;
    const { title, description = '' } = req.body;

    try {
      // Insert video record (status: pending)
      await db.query(
        `INSERT INTO videos (id, owner_id, title, description, status)
         VALUES ($1, $2, $3, $4, 'pending')`,
        [videoId, req.user.id, title, description]
      );

      // Enqueue the transcoding job
      const jobId = await enqueueTranscodeJob({ videoId, s3Key, title });

      // Update job_id and status in DB
      await db.query(
        `UPDATE videos SET job_id = $1, status = 'processing' WHERE id = $2`,
        [jobId, videoId]
      );

      logger.info({ videoId, jobId, userId: req.user.id }, 'Video uploaded and queued for transcoding');

      res.status(202).json({
        message: 'Upload received. Transcoding started.',
        videoId,
        jobId,
        status: 'processing',
      });
    } catch (err) {
      next(err);
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/videos/presign — Generate presigned URL for large file upload
// ─────────────────────────────────────────────────────────────────────────────
router.post('/presign',
  requireAuth,
  requireRole('uploader', 'admin'),
  [body('title').notEmpty().trim().isLength({ max: 500 })],
  async (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    }

    const videoId = uuidv4();
    const { title, description = '' } = req.body;

    try {
      const { uploadUrl, objectKey } = await createPresignedUploadUrl(videoId);

      // Pre-create the video record so /confirm can find it
      await db.query(
        `INSERT INTO videos (id, owner_id, title, description, status)
         VALUES ($1, $2, $3, $4, 'pending')`,
        [videoId, req.user.id, title, description]
      );

      res.json({ videoId, uploadUrl, objectKey, expiresInSeconds: 3600 });
    } catch (err) {
      next(err);
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/videos/:id/confirm — Client calls this after direct-to-MinIO upload
// ─────────────────────────────────────────────────────────────────────────────
router.post('/:id/confirm',
  requireAuth,
  [param('id').isUUID()],
  async (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ error: 'Invalid video ID' });

    const videoId = req.params.id;
    const s3Key   = `${videoId}/source.mp4`;

    try {
      const result = await db.query(
        `SELECT id, owner_id, title, status FROM videos WHERE id = $1`,
        [videoId]
      );
      const video = result.rows[0];
      if (!video) return res.status(404).json({ error: 'Video not found' });
      if (video.owner_id !== req.user.id && req.user.role !== 'admin') {
        return res.status(403).json({ error: 'Not your video' });
      }
      if (video.status !== 'pending') {
        return res.status(409).json({ error: `Video is already in status: ${video.status}` });
      }

      const jobId = await enqueueTranscodeJob({ videoId, s3Key, title: video.title });
      await db.query(
        `UPDATE videos SET job_id = $1, status = 'processing' WHERE id = $2`,
        [jobId, videoId]
      );

      res.status(202).json({ videoId, jobId, status: 'processing' });
    } catch (err) {
      next(err);
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/videos/:id/complete — Internal webhook from the worker
// (Protected by a shared secret — NOT JWT, since the worker has no user session)
// ─────────────────────────────────────────────────────────────────────────────
router.post('/:id/complete',
  [param('id').isUUID()],
  async (req, res, next) => {
    // Simple shared-secret auth for worker→API communication
    const secret = req.headers['x-worker-secret'];
    if (!secret || secret !== process.env.WORKER_SECRET) {
      return res.status(401).json({ error: 'Unauthorized' });
    }

    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ error: 'Invalid video ID' });

    const { masterPlaylist, renditions = [], durationSeconds } = req.body;
    const videoId = req.params.id;

    try {
      await db.query(
        `UPDATE videos
         SET status = 'ready', master_key = $1, duration_seconds = $2, updated_at = NOW()
         WHERE id = $3`,
        [masterPlaylist, durationSeconds ?? null, videoId]
      );

      // Upsert rendition rows
      for (const name of renditions) {
        await db.query(
          `INSERT INTO video_renditions (video_id, name, minio_prefix)
           VALUES ($1, $2, $3)
           ON CONFLICT (video_id, name) DO UPDATE SET minio_prefix = EXCLUDED.minio_prefix`,
          [videoId, name, `videos/${videoId}/${name}`]
        );
      }

      logger.info({ videoId, renditions, masterPlaylist }, 'Video marked as ready');
      res.json({ success: true });
    } catch (err) {
      next(err);
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// DELETE /api/v1/videos/:id  — Soft-delete
// ─────────────────────────────────────────────────────────────────────────────
router.delete('/:id',
  requireAuth,
  [param('id').isUUID()],
  async (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ error: 'Invalid video ID' });

    try {
      const result = await db.query(
        `UPDATE videos SET deleted_at = NOW()
         WHERE id = $1 AND (owner_id = $2 OR $3 = 'admin')
         RETURNING id`,
        [req.params.id, req.user.id, req.user.role]
      );

      if (!result.rows[0]) {
        return res.status(404).json({ error: 'Video not found or access denied' });
      }
      res.json({ message: 'Video deleted' });
    } catch (err) {
      next(err);
    }
  }
);

module.exports = router;
