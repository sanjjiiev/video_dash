'use strict';

/**
 * routes/keys.js
 *
 * GET /api/v1/keys/:videoId
 *
 * THE most security-critical endpoint in the entire platform.
 *
 * This is the key URI baked into every .m3u8 playlist by FFmpeg during
 * transcoding (set via KEY_SERVER_BASE_URL + /api/v1/keys/:videoId).
 *
 * The HLS player (media_kit / mpv) calls this ONCE per video session to
 * obtain the 16-byte AES-128 decryption key, then decrypts the .ts segments
 * locally in memory — the key is never written to disk by the player.
 *
 * Security measures:
 *  1. requireAuth: valid JWT required — unauthenticated players get 0 bytes.
 *  2. Video ownership check: the video must be 'ready' and not deleted.
 *     (Fine-grained ACL — e.g., subscription check — can be added here in Phase 4.)
 *  3. keyLimiter: 60 requests/minute per user — blocks key enumeration.
 *  4. Only 16 raw bytes are returned. No JSON wrapper — the HLS spec requires
 *     the response body to be the raw key.
 *  5. Response headers prevent caching by proxy layers.
 */

const express = require('express');
const { param, validationResult } = require('express-validator');

const db       = require('../db');
const logger   = require('../logger');
const { requireAuth }    = require('../middleware/auth');
const { keyLimiter }     = require('../middleware/rateLimiter');
const { getEncryptionKey } = require('../services/minioService');

const router = express.Router();

router.get('/:videoId',
  requireAuth,
  keyLimiter,
  [param('videoId').isUUID().withMessage('Invalid video ID format')],
  async (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Invalid video ID' });
    }

    const { videoId } = req.params;
    const userId      = req.user.id;

    try {
      // ── Access control ──────────────────────────────────────────────────
      // The video must exist, be in 'ready' state, and not be deleted.
      // In Phase 4, replace with subscription/purchase check.
      const result = await db.query(
        `SELECT id FROM videos
         WHERE id = $1 AND status = 'ready' AND deleted_at IS NULL`,
        [videoId]
      );

      if (!result.rows[0]) {
        // Return 404 rather than 403 to avoid leaking video existence to unauthorized parties
        logger.warn({ userId, videoId }, 'Key requested for non-existent or non-ready video');
        return res.status(404).end();
      }

      // ── Fetch the raw AES-128 key from MinIO ─────────────────────────────
      const keyBuffer = await getEncryptionKey(videoId);

      // Validate key length (must be exactly 16 bytes for AES-128)
      if (!keyBuffer || keyBuffer.length !== 16) {
        logger.error({ videoId, len: keyBuffer?.length }, 'Invalid key length in MinIO');
        return res.status(500).end();
      }

      // ── Serve the raw bytes ───────────────────────────────────────────────
      // Per RFC 8216 §5.2: the key file MUST be exactly 16 octets.
      // No JSON, no text — raw binary response only.
      res
        .status(200)
        .set('Content-Type', 'application/octet-stream')
        .set('Content-Length', '16')
        // Prevent any caching — players must always fetch fresh from the API
        .set('Cache-Control', 'no-store, no-cache, must-revalidate')
        .set('Pragma', 'no-cache')
        .end(keyBuffer);

      logger.info({ userId, videoId }, 'AES-128 key served successfully');

    } catch (err) {
      // If key is not found in MinIO, log and return 404 (not 500)
      if (err.code === 'NoSuchKey' || err.code === 'NotFound') {
        logger.error({ videoId, err: err.message }, 'Encryption key not found in MinIO');
        return res.status(404).end();
      }
      next(err);
    }
  }
);

module.exports = router;
