'use strict';
const { Router } = require('express');
const { requireAuth }      = require('../middleware/auth');
const { requireOwnership } = require('../middleware/rbac');
const db = require('../db');

const router = Router();

// ── GET /api/v1/analytics/overview — creator's overall stats ─────────────────
// Returns totals across all videos owned by the authenticated user
router.get('/overview', requireAuth, async (req, res, next) => {
  try {
    const { rows: [stats] } = await db.query(
      `SELECT
          COUNT(v.id)::INT                                   AS total_videos,
          COALESCE(SUM(va.views), 0)::BIGINT                AS total_views,
          COALESCE(SUM(va.watch_seconds), 0)::BIGINT        AS total_watch_seconds,
          COALESCE(SUM(va.likes), 0)::BIGINT                AS total_likes,
          COALESCE(SUM(va.comments), 0)::BIGINT             AS total_comments,
          COALESCE(SUM(va.shares), 0)::BIGINT               AS total_shares,
          MAX(u.subscriber_count)                            AS subscriber_count
         FROM videos v
         LEFT JOIN video_analytics va ON va.video_id = v.id
         JOIN users u ON u.id = v.owner_id
        WHERE v.owner_id = $1 AND v.deleted_at IS NULL`,
      [req.user.id],
    );
    res.json({ overview: stats });
  } catch (err) { next(err); }
});

// ── GET /api/v1/analytics/timeseries — daily views for the last N days ────────
router.get('/timeseries', requireAuth, async (req, res, next) => {
  try {
    const days = Math.min(Number(req.query.days) || 30, 365);

    const { rows } = await db.query(
      `SELECT
          d.date::TEXT,
          COALESCE(SUM(va.views), 0)::INT               AS views,
          COALESCE(SUM(va.watch_seconds), 0)::BIGINT    AS watch_seconds,
          COALESCE(SUM(va.likes), 0)::INT               AS likes,
          COALESCE(SUM(va.unique_viewers), 0)::INT      AS unique_viewers
         FROM generate_series(
           CURRENT_DATE - INTERVAL '1 day' * ($2 - 1),
           CURRENT_DATE,
           '1 day'::INTERVAL
         ) AS d(date)
         LEFT JOIN video_analytics va
               ON va.date = d.date::DATE
              AND va.video_id IN (
                SELECT id FROM videos WHERE owner_id=$1 AND deleted_at IS NULL
              )
        GROUP BY d.date
        ORDER BY d.date ASC`,
      [req.user.id, days],
    );
    res.json({ days, timeseries: rows });
  } catch (err) { next(err); }
});

// ── GET /api/v1/analytics/top-videos — creator's best performing videos ────────
router.get('/top-videos', requireAuth, async (req, res, next) => {
  try {
    const { limit = 10, metric = 'views', days = 30 } = req.query;
    const allowedMetrics = ['views', 'watch_seconds', 'likes', 'unique_viewers'];
    const safeMetric = allowedMetrics.includes(metric) ? metric : 'views';

    const { rows } = await db.query(
      `SELECT
          v.id, v.title, v.thumbnail_key, v.duration_seconds, v.created_at,
          COALESCE(SUM(va.views), 0)::BIGINT          AS views,
          COALESCE(SUM(va.watch_seconds), 0)::BIGINT  AS watch_seconds,
          COALESCE(SUM(va.likes), 0)::BIGINT          AS likes,
          COALESCE(SUM(va.unique_viewers), 0)::BIGINT AS unique_viewers,
          ROUND(
            CASE WHEN SUM(va.views) > 0
              THEN SUM(va.watch_seconds)::FLOAT / SUM(va.views) / NULLIF(v.duration_seconds, 0) * 100
              ELSE 0
            END
          )::INT AS avg_completion_pct
         FROM videos v
         LEFT JOIN video_analytics va
               ON va.video_id = v.id
              AND va.date >= CURRENT_DATE - ($3::INT * INTERVAL '1 day')
        WHERE v.owner_id = $1 AND v.deleted_at IS NULL AND v.status = 'ready'
        GROUP BY v.id
        ORDER BY ${safeMetric} DESC
        LIMIT $2`,
      [req.user.id, Number(limit), Number(days)],
    );
    res.json({ top_videos: rows });
  } catch (err) { next(err); }
});

// ── GET /api/v1/analytics/video/:videoId — per-video deep dive ────────────────
router.get('/video/:videoId',
  requireAuth,
  requireOwnership(async (req, db) => {
    const { rows } = await db.query('SELECT owner_id FROM videos WHERE id=$1', [req.params.videoId]);
    return rows[0]?.owner_id;
  }),
  async (req, res, next) => {
    try {
      const days = Math.min(Number(req.query.days) || 30, 365);

      // Timeseries for this specific video
      const { rows: timeseries } = await db.query(
        `SELECT
            d.date::TEXT,
            COALESCE(va.views, 0)            AS views,
            COALESCE(va.watch_seconds, 0)    AS watch_seconds,
            COALESCE(va.likes, 0)            AS likes,
            COALESCE(va.unique_viewers, 0)   AS unique_viewers
           FROM generate_series(
             CURRENT_DATE - INTERVAL '1 day' * ($2 - 1),
             CURRENT_DATE, '1 day'
           ) AS d(date)
           LEFT JOIN video_analytics va
                 ON va.date = d.date::DATE AND va.video_id = $1
          ORDER BY d.date ASC`,
        [req.params.videoId, days],
      );

      // Summary totals
      const { rows: [totals] } = await db.query(
        `SELECT
            COALESCE(SUM(views), 0)::BIGINT         AS total_views,
            COALESCE(SUM(watch_seconds), 0)::BIGINT AS total_watch_seconds,
            COALESCE(SUM(likes), 0)::INT            AS total_likes,
            COALESCE(SUM(dislikes), 0)::INT         AS total_dislikes,
            COALESCE(SUM(comments), 0)::INT         AS total_comments,
            COALESCE(SUM(unique_viewers), 0)::INT   AS total_unique_viewers
           FROM video_analytics WHERE video_id=$1`,
        [req.params.videoId],
      );

      res.json({ timeseries, totals });
    } catch (err) { next(err); }
  },
);

// ── POST /api/v1/analytics/record-watch — upsert watch event ─────────────────
// Called by the player every 30 s (or on completion)
router.post('/record-watch', requireAuth, async (req, res, next) => {
  try {
    const { video_id, seconds_watched } = req.body;
    if (!video_id || typeof seconds_watched !== 'number') {
      return res.status(400).json({ error: 'video_id and seconds_watched required' });
    }

    await db.query(
      `INSERT INTO video_analytics (video_id, date, views, watch_seconds, unique_viewers)
       VALUES ($1, CURRENT_DATE, 1, $2, 1)
       ON CONFLICT (video_id, date) DO UPDATE SET
         views         = video_analytics.views + 1,
         watch_seconds = video_analytics.watch_seconds + EXCLUDED.watch_seconds`,
      [video_id, Math.min(Math.round(seconds_watched), 86400)],
    );

    // Also bump total view count on the video
    await db.query(
      'UPDATE videos SET view_count = view_count + 1 WHERE id=$1',
      [video_id],
    );

    res.json({ ok: true });
  } catch (err) { next(err); }
});

// ── GET /api/v1/analytics/notifications — user's notification inbox ───────────
router.get('/notifications', requireAuth, async (req, res, next) => {
  try {
    const { rows } = await db.query(
      `SELECT * FROM notifications
        WHERE user_id = $1
        ORDER BY created_at DESC LIMIT 50`,
      [req.user.id],
    );
    res.json({ notifications: rows });
  } catch (err) { next(err); }
});

// ── POST /api/v1/analytics/push-token — register device push token ────────────
router.post('/push-token', requireAuth, async (req, res, next) => {
  try {
    const { token, platform } = req.body;
    if (!token || !['ios', 'android', 'web'].includes(platform)) {
      return res.status(400).json({ error: 'token and platform (ios|android|web) required' });
    }
    await db.query(
      `INSERT INTO push_tokens (user_id, token, platform)
       VALUES ($1, $2, $3)
       ON CONFLICT (user_id, token) DO NOTHING`,
      [req.user.id, token, platform],
    );
    res.json({ ok: true });
  } catch (err) { next(err); }
});

module.exports = router;
