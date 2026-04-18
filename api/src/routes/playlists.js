'use strict';
const { Router } = require('express');
const createError = require('http-errors');
const { requireAuth }      = require('../middleware/auth');
const { requireOwnership } = require('../middleware/rbac');
const db = require('../db');

const router = Router();

// ── GET /api/v1/playlists — list user's playlists ─────────────────────────────
router.get('/', requireAuth, async (req, res, next) => {
  try {
    const { rows } = await db.query(
      `SELECT p.*,
              COUNT(pi.video_id)::INT AS item_count
         FROM playlists p
         LEFT JOIN playlist_items pi ON pi.playlist_id = p.id
        WHERE p.owner_id = $1
        GROUP BY p.id
        ORDER BY p.updated_at DESC`,
      [req.user.id],
    );
    res.json({ playlists: rows });
  } catch (err) { next(err); }
});

// ── POST /api/v1/playlists — create playlist ──────────────────────────────────
router.post('/', requireAuth, async (req, res, next) => {
  try {
    const { title, description, visibility = 'private' } = req.body;
    if (!title?.trim()) return next(createError(400, 'title is required'));
    if (!['public','unlisted','private'].includes(visibility)) {
      return next(createError(400, 'visibility must be public|unlisted|private'));
    }

    const { rows } = await db.query(
      `INSERT INTO playlists (owner_id, title, description, visibility)
       VALUES ($1, $2, $3, $4)
       RETURNING *`,
      [req.user.id, title.trim(), description?.trim() ?? null, visibility],
    );
    res.status(201).json({ playlist: rows[0] });
  } catch (err) { next(err); }
});

// ── GET /api/v1/playlists/:id — playlist detail with videos ───────────────────
router.get('/:id', async (req, res, next) => {
  try {
    const { rows: [playlist] } = await db.query(
      'SELECT * FROM playlists WHERE id=$1', [req.params.id]);
    if (!playlist) return next(createError(404, 'Playlist not found'));

    // Non-owner can only see public/unlisted
    const requesterId = req.user?.id;
    if (playlist.visibility === 'private' && playlist.owner_id !== requesterId) {
      return next(createError(403, 'This playlist is private'));
    }

    const { rows: items } = await db.query(
      `SELECT v.id, v.title, v.thumbnail_key, v.duration_seconds, v.view_count,
              pi.position, pi.added_at,
              u.channel_name, u.avatar_url AS owner_avatar
         FROM playlist_items pi
         JOIN videos v ON v.id = pi.video_id
         JOIN users  u ON u.id = v.owner_id
        WHERE pi.playlist_id = $1 AND v.deleted_at IS NULL
        ORDER BY pi.position ASC`,
      [req.params.id],
    );

    res.json({ playlist, items });
  } catch (err) { next(err); }
});

// ── PATCH /api/v1/playlists/:id — update metadata ────────────────────────────
router.patch('/:id',
  requireAuth,
  requireOwnership(async (req, db) => {
    const { rows } = await db.query('SELECT owner_id FROM playlists WHERE id=$1', [req.params.id]);
    return rows[0]?.owner_id;
  }),
  async (req, res, next) => {
    try {
      const { title, description, visibility } = req.body;
      await db.query(
        `UPDATE playlists SET
           title       = COALESCE($1, title),
           description = COALESCE($2, description),
           visibility  = COALESCE($3, visibility),
           updated_at  = NOW()
         WHERE id=$4`,
        [title?.trim() ?? null, description?.trim() ?? null, visibility ?? null, req.params.id],
      );
      res.json({ ok: true });
    } catch (err) { next(err); }
  },
);

// ── DELETE /api/v1/playlists/:id ──────────────────────────────────────────────
router.delete('/:id',
  requireAuth,
  requireOwnership(async (req, db) => {
    const { rows } = await db.query('SELECT owner_id FROM playlists WHERE id=$1', [req.params.id]);
    return rows[0]?.owner_id;
  }),
  async (req, res, next) => {
    try {
      await db.query('DELETE FROM playlists WHERE id=$1', [req.params.id]);
      res.status(204).end();
    } catch (err) { next(err); }
  },
);

// ── POST /api/v1/playlists/:id/items — add video to playlist ─────────────────
router.post('/:id/items',
  requireAuth,
  requireOwnership(async (req, db) => {
    const { rows } = await db.query('SELECT owner_id FROM playlists WHERE id=$1', [req.params.id]);
    return rows[0]?.owner_id;
  }),
  async (req, res, next) => {
    try {
      const { video_id } = req.body;
      if (!video_id) return next(createError(400, 'video_id required'));

      // Verify video exists
      const { rows: [v] } = await db.query(
        "SELECT id FROM videos WHERE id=$1 AND status='ready' AND deleted_at IS NULL", [video_id]);
      if (!v) return next(createError(404, 'Video not found or not ready'));

      // Next position
      const { rows: [pos] } = await db.query(
        'SELECT COALESCE(MAX(position)+1,0) AS next FROM playlist_items WHERE playlist_id=$1',
        [req.params.id],
      );

      await db.query(
        `INSERT INTO playlist_items (playlist_id, video_id, position)
         VALUES ($1,$2,$3) ON CONFLICT DO NOTHING`,
        [req.params.id, video_id, pos.next],
      );

      // Touch playlist updated_at
      await db.query('UPDATE playlists SET updated_at=NOW() WHERE id=$1', [req.params.id]);

      res.status(201).json({ ok: true });
    } catch (err) { next(err); }
  },
);

// ── DELETE /api/v1/playlists/:id/items/:videoId — remove from playlist ────────
router.delete('/:id/items/:videoId',
  requireAuth,
  requireOwnership(async (req, db) => {
    const { rows } = await db.query('SELECT owner_id FROM playlists WHERE id=$1', [req.params.id]);
    return rows[0]?.owner_id;
  }),
  async (req, res, next) => {
    try {
      await db.query(
        'DELETE FROM playlist_items WHERE playlist_id=$1 AND video_id=$2',
        [req.params.id, req.params.videoId],
      );
      await db.query('UPDATE playlists SET updated_at=NOW() WHERE id=$1', [req.params.id]);
      res.status(204).end();
    } catch (err) { next(err); }
  },
);

// ── PUT /api/v1/playlists/:id/items/reorder — bulk reorder ───────────────────
// Body: { order: ['videoId1', 'videoId2', ...] }
router.put('/:id/items/reorder',
  requireAuth,
  requireOwnership(async (req, db) => {
    const { rows } = await db.query('SELECT owner_id FROM playlists WHERE id=$1', [req.params.id]);
    return rows[0]?.owner_id;
  }),
  async (req, res, next) => {
    try {
      const { order } = req.body;
      if (!Array.isArray(order)) return next(createError(400, 'order must be array of video IDs'));

      // Update positions in a single batch
      const updates = order.map((videoId, i) =>
        db.query(
          'UPDATE playlist_items SET position=$1 WHERE playlist_id=$2 AND video_id=$3',
          [i, req.params.id, videoId],
        )
      );
      await Promise.all(updates);
      await db.query('UPDATE playlists SET updated_at=NOW() WHERE id=$1', [req.params.id]);
      res.json({ ok: true });
    } catch (err) { next(err); }
  },
);

// ── GET /api/v1/playlists/watch-later — special system playlist ───────────────
router.get('/watch-later', requireAuth, async (req, res, next) => {
  try {
    const { rows } = await db.query(
      `SELECT v.id, v.title, v.thumbnail_key, v.duration_seconds, v.view_count,
              wl.added_at,
              u.channel_name, u.avatar_url AS owner_avatar
         FROM watch_later wl
         JOIN videos v ON v.id = wl.video_id
         JOIN users  u ON u.id = v.owner_id
        WHERE wl.user_id = $1 AND v.deleted_at IS NULL
        ORDER BY wl.added_at DESC`,
      [req.user.id],
    );
    res.json({ videos: rows });
  } catch (err) { next(err); }
});

// ── POST /api/v1/playlists/watch-later/:videoId ───────────────────────────────
router.post('/watch-later/:videoId', requireAuth, async (req, res, next) => {
  try {
    await db.query(
      'INSERT INTO watch_later (user_id, video_id) VALUES ($1,$2) ON CONFLICT DO NOTHING',
      [req.user.id, req.params.videoId],
    );
    res.status(201).json({ saved: true });
  } catch (err) { next(err); }
});

// ── DELETE /api/v1/playlists/watch-later/:videoId ────────────────────────────
router.delete('/watch-later/:videoId', requireAuth, async (req, res, next) => {
  try {
    await db.query(
      'DELETE FROM watch_later WHERE user_id=$1 AND video_id=$2',
      [req.user.id, req.params.videoId],
    );
    res.json({ saved: false });
  } catch (err) { next(err); }
});

module.exports = router;
