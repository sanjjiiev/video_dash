'use strict';

/**
 * routes/stream.js
 *
 * GET  /api/v1/videos/:id/stream       — Get the HLS stream URL for a video
 * GET  /api/v1/hls/:videoId/*          — Proxy HLS objects from MinIO (auth-gated)
 * GET  /api/v1/internal/hls-auth       — Nginx auth_request validation endpoint
 *
 * HLS delivery flow:
 *
 *  1. Authenticated client calls GET /api/v1/videos/:id/stream
 *     → Returns { streamUrl: "https://yourdomain.com/hls/<videoId>/master.m3u8" }
 *
 *  2. Flutter media_kit player opens that URL.
 *     → Nginx receives GET /hls/<videoId>/master.m3u8
 *     → Nginx makes an auth_request subrequest to /api/v1/internal/hls-auth
 *     → If auth passes (200), Nginx proxies the request to GET /api/v1/hls/<videoId>/master.m3u8
 *     → API fetches from MinIO and streams back
 *     → Nginx caches .ts segments for 24 h (immutable), .m3u8 for 60 s
 *
 *  3. Player reads the master playlist, picks a rendition, requests segments.
 *     → All segment requests go through the same Nginx → auth_request → API → MinIO path.
 *     → After the first request, Nginx cache serves segments directly (no MinIO hit).
 *
 *  4. Player requests the AES-128 decryption key (phase: keys.js route).
 *     → API fetches the raw bytes from the private keys bucket, returns them.
 */

const express = require('express');
const { param, validationResult } = require('express-validator');

const db        = require('../db');
const logger    = require('../logger');
const { requireAuth } = require('../middleware/auth');
const { apiLimiter }  = require('../middleware/rateLimiter');
const { streamHlsObject, VIDEOS_BUCKET } = require('../services/minioService');

const router = express.Router();

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/videos/:id/stream — Returns the HLS stream URL
// ─────────────────────────────────────────────────────────────────────────────
router.get('/:id/stream',
  requireAuth,
  apiLimiter,
  [param('id').isUUID()],
  async (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) return res.status(400).json({ error: 'Invalid video ID' });

    try {
      const result = await db.query(
        `SELECT id, status, master_key FROM videos WHERE id = $1 AND deleted_at IS NULL`,
        [req.params.id]
      );

      const video = result.rows[0];
      if (!video) return res.status(404).json({ error: 'Video not found' });
      if (video.status !== 'ready') {
        return res.status(409).json({ error: `Video is not ready yet. Status: ${video.status}` });
      }

      // The streamUrl uses /hls/ prefix — Nginx routes this through auth_request + caching
      const baseUrl   = process.env.PUBLIC_BASE_URL ?? 'http://localhost';
      const streamUrl = `${baseUrl}/hls/${req.params.id}/master.m3u8`;

      logger.info({ userId: req.user.id, videoId: req.params.id }, 'Stream URL issued');

      res.json({ streamUrl, videoId: req.params.id });
    } catch (err) {
      next(err);
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/internal/hls-auth
//
// INTERNAL — called only by Nginx's auth_request directive.
// The client never calls this directly; Nginx does as a subrequest.
//
// Nginx passes:
//   X-Original-URI : the full original request URI, e.g. /hls/abc123/1080p/seg0001.ts
//   Cookie         : forwarded verbatim from the client request
//   Authorization  : forwarded verbatim
//
// Returns 200 → auth OK, Nginx continues to serve.
// Returns 401 → auth failed, Nginx returns 401 to client.
// ─────────────────────────────────────────────────────────────────────────────
router.get('/internal/hls-auth', async (req, res) => {
  const jwt    = require('jsonwebtoken');
  const config = require('../config');

  let token = null;

  // 1. Try Authorization header
  const authHeader = req.headers['authorization'];
  if (authHeader?.startsWith('Bearer ')) token = authHeader.slice(7);

  // 2. Try cookie
  if (!token && req.cookies?.hub_access) token = req.cookies.hub_access;

  if (!token) return res.status(401).end();

  try {
    jwt.verify(token, config.jwt.accessSecret);
    res.status(200).end();  // AUTH OK
  } catch {
    res.status(401).end();  // AUTH FAILED
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/hls/:videoId/*
//
// Proxies any HLS artifact (master.m3u8, rendition playlists, .ts segments)
// from the private MinIO bucket to the client.
//
// Auth is applied via two mechanisms:
//   A) This route is called by Nginx AFTER auth_request already passed → trusted.
//   B) Direct API access (e.g. Flutter using Authorization header) → requireAuth.
//
// For simplicity, we apply requireAuth here too so the API is always self-contained.
// In production, you may use a gateway-only approach where this route is
// private (not exposed by Nginx directly) and Nginx only calls it after auth_request.
// ─────────────────────────────────────────────────────────────────────────────
router.get('/hls/:videoId/*',
  requireAuth,
  async (req, res, next) => {
    const { videoId } = req.params;
    // req.params[0] captures everything after /hls/:videoId/
    const subPath = req.params[0];

    if (!videoId || !subPath) {
      return res.status(400).json({ error: 'Invalid HLS path' });
    }

    // Sanitize: prevent path traversal
    if (subPath.includes('..') || subPath.includes('//')) {
      return res.status(400).json({ error: 'Invalid path' });
    }

    try {
      // Verify the video exists and is ready (lightweight DB check)
      const result = await db.query(
        `SELECT id FROM videos WHERE id = $1 AND status = 'ready' AND deleted_at IS NULL`,
        [videoId]
      );
      if (!result.rows[0]) {
        return res.status(404).json({ error: 'Video not found or not ready' });
      }

      // Stream the object from MinIO
      const objectKey = `videos/${videoId}/${subPath}`;
      await streamHlsObject(VIDEOS_BUCKET, objectKey, res);
    } catch (err) {
      next(err);
    }
  }
);

module.exports = router;
