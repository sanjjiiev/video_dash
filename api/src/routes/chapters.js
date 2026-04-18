'use strict';
const { Router } = require('express');
const createError = require('http-errors');
const { requireAuth }      = require('../middleware/auth');
const { requireOwnership } = require('../middleware/rbac');
const db = require('../db');

const router = Router({ mergeParams: true });

// ── GET /api/v1/videos/:videoId/chapters ──────────────────────────────────────
router.get('/', async (req, res, next) => {
  try {
    const { rows } = await db.query(
      `SELECT id, title, start_seconds, position
         FROM video_chapters
        WHERE video_id = $1
        ORDER BY position ASC`,
      [req.params.videoId],
    );
    res.json({ chapters: rows });
  } catch (err) { next(err); }
});

// ── POST /api/v1/videos/:videoId/chapters ─────────────────────────────────────
// Only the video owner (or admin) may add chapters
router.post('/',
  requireAuth,
  requireOwnership(async (req, db) => {
    const { rows } = await db.query('SELECT owner_id FROM videos WHERE id=$1', [req.params.videoId]);
    return rows[0]?.owner_id;
  }),
  async (req, res, next) => {
    try {
      const { title, start_seconds, position } = req.body;

      if (!title || typeof start_seconds !== 'number') {
        return next(createError(400, 'title and start_seconds (number) are required'));
      }

      // Auto-assign position if not provided
      const pos = position ?? (await _nextPosition(req.params.videoId));

      const { rows } = await db.query(
        `INSERT INTO video_chapters (video_id, title, start_seconds, position)
         VALUES ($1, $2, $3, $4)
         ON CONFLICT (video_id, start_seconds)
           DO UPDATE SET title=EXCLUDED.title, position=EXCLUDED.position
         RETURNING *`,
        [req.params.videoId, title.trim(), start_seconds, pos],
      );
      res.status(201).json({ chapter: rows[0] });
    } catch (err) { next(err); }
  },
);

// ── PUT /api/v1/videos/:videoId/chapters (bulk replace) ─────────────────────
// Accept the full chapters array and replace atomically
router.put('/',
  requireAuth,
  requireOwnership(async (req, db) => {
    const { rows } = await db.query('SELECT owner_id FROM videos WHERE id=$1', [req.params.videoId]);
    return rows[0]?.owner_id;
  }),
  async (req, res, next) => {
    try {
      const chapters = req.body.chapters;
      if (!Array.isArray(chapters)) {
        return next(createError(400, 'chapters must be an array'));
      }
      if (chapters.length > 100) {
        return next(createError(400, 'Maximum 100 chapters per video'));
      }

      await db.query('DELETE FROM video_chapters WHERE video_id=$1', [req.params.videoId]);

      if (chapters.length > 0) {
        const values = chapters.map((c, i) =>
          `($1, $${i * 3 + 2}, $${i * 3 + 3}, $${i * 3 + 4})`).join(',');
        const params = [req.params.videoId];
        chapters.forEach((c, i) => {
          params.push(c.title?.trim() || `Chapter ${i + 1}`);
          params.push(Number(c.start_seconds) || 0);
          params.push(i);
        });
        await db.query(
          `INSERT INTO video_chapters (video_id, title, start_seconds, position) VALUES ${values}`,
          params,
        );
      }

      const { rows } = await db.query(
        'SELECT * FROM video_chapters WHERE video_id=$1 ORDER BY position',
        [req.params.videoId],
      );
      res.json({ chapters: rows });
    } catch (err) { next(err); }
  },
);

// ── DELETE /api/v1/videos/:videoId/chapters/:chapterId ───────────────────────
router.delete('/:chapterId',
  requireAuth,
  requireOwnership(async (req, db) => {
    const { rows } = await db.query('SELECT owner_id FROM videos WHERE id=$1', [req.params.videoId]);
    return rows[0]?.owner_id;
  }),
  async (req, res, next) => {
    try {
      const { rowCount } = await db.query(
        'DELETE FROM video_chapters WHERE id=$1 AND video_id=$2',
        [req.params.chapterId, req.params.videoId],
      );
      if (rowCount === 0) return next(createError(404, 'Chapter not found'));
      res.status(204).end();
    } catch (err) { next(err); }
  },
);

async function _nextPosition(videoId) {
  const { rows } = await db.query(
    'SELECT COALESCE(MAX(position)+1, 0) AS next_pos FROM video_chapters WHERE video_id=$1',
    [videoId],
  );
  return rows[0].next_pos;
}

module.exports = router;
