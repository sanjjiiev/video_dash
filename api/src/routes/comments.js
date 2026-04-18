'use strict';
const { Router } = require('express');
const createError = require('http-errors');
const { requireAuth } = require('../middleware/auth');
const db = require('../db');

const router = Router({ mergeParams: true });

// ── GET /api/v1/videos/:videoId/comments ──────────────────────────────────────
// Paginated top-level comments with reply counts
router.get('/', async (req, res, next) => {
  try {
    const { page = 1, limit = 20, sort = 'newest' } = req.query;
    const offset = (Number(page) - 1) * Number(limit);
    const orderBy = sort === 'top' ? 'like_count DESC, c.created_at DESC' : 'c.created_at DESC';

    const { rows } = await db.query(
      `SELECT
          c.id, c.body, c.like_count, c.pinned, c.created_at,
          u.id AS author_id, u.email AS author_email, u.channel_name AS author_name,
          u.avatar_url AS author_avatar,
          (SELECT COUNT(*)::INT FROM comments r WHERE r.parent_id = c.id) AS reply_count
         FROM comments c
         JOIN users u ON u.id = c.user_id
        WHERE c.video_id = $1 AND c.parent_id IS NULL AND c.deleted_at IS NULL
        ORDER BY c.pinned DESC, ${orderBy}
        LIMIT $2 OFFSET $3`,
      [req.params.videoId, Number(limit), offset],
    );

    const { rows: [cnt] } = await db.query(
      `SELECT COUNT(*)::INT AS total FROM comments
        WHERE video_id=$1 AND parent_id IS NULL AND deleted_at IS NULL`,
      [req.params.videoId],
    );

    res.json({ comments: rows, total: cnt.total });
  } catch (err) { next(err); }
});

// ── GET /api/v1/videos/:videoId/comments/:commentId/replies ──────────────────
router.get('/:commentId/replies', async (req, res, next) => {
  try {
    const { page = 1, limit = 10 } = req.query;
    const offset = (Number(page) - 1) * Number(limit);

    const { rows } = await db.query(
      `SELECT
          c.id, c.body, c.like_count, c.created_at,
          u.id AS author_id, u.email AS author_email,
          u.channel_name AS author_name, u.avatar_url AS author_avatar
         FROM comments c
         JOIN users u ON u.id = c.user_id
        WHERE c.parent_id = $1 AND c.deleted_at IS NULL
        ORDER BY c.created_at ASC
        LIMIT $2 OFFSET $3`,
      [req.params.commentId, Number(limit), offset],
    );

    res.json({ replies: rows });
  } catch (err) { next(err); }
});

// ── POST /api/v1/videos/:videoId/comments ────────────────────────────────────
router.post('/', requireAuth, async (req, res, next) => {
  try {
    const { body, parent_id } = req.body;
    if (!body?.trim()) return next(createError(400, 'Comment body is required'));
    if (body.trim().length > 10000) return next(createError(400, 'Comment too long (max 10,000 chars)'));

    // Validate parent exists in same video if provided
    if (parent_id) {
      const { rows } = await db.query(
        'SELECT id FROM comments WHERE id=$1 AND video_id=$2', [parent_id, req.params.videoId]);
      if (!rows.length) return next(createError(404, 'Parent comment not found'));
    }

    const { rows } = await db.query(
      `INSERT INTO comments (video_id, user_id, parent_id, body)
       VALUES ($1, $2, $3, $4)
       RETURNING id, body, like_count, pinned, created_at`,
      [req.params.videoId, req.user.id, parent_id ?? null, body.trim()],
    );

    res.status(201).json({ comment: rows[0] });
  } catch (err) { next(err); }
});

// ── PATCH /api/v1/videos/:videoId/comments/:commentId ────────────────────────
// Edit own comment or pin (moderator/admin)
router.patch('/:commentId', requireAuth, async (req, res, next) => {
  try {
    const { body, pinned } = req.body;

    // Fetch comment
    const { rows } = await db.query(
      'SELECT user_id FROM comments WHERE id=$1 AND video_id=$2 AND deleted_at IS NULL',
      [req.params.commentId, req.params.videoId],
    );
    if (!rows.length) return next(createError(404, 'Comment not found'));

    const isOwner = rows[0].user_id === req.user.id;
    const isMod   = ['moderator', 'admin'].includes(req.user.role);

    // Only owner can edit body; only mod/admin can pin
    if (body !== undefined) {
      if (!isOwner && !isMod) return next(createError(403, 'Cannot edit this comment'));
      await db.query('UPDATE comments SET body=$1 WHERE id=$2',
          [body.trim(), req.params.commentId]);
    }
    if (pinned !== undefined && isMod) {
      await db.query('UPDATE comments SET pinned=$1 WHERE id=$2',
          [Boolean(pinned), req.params.commentId]);
    }

    res.json({ ok: true });
  } catch (err) { next(err); }
});

// ── DELETE /api/v1/videos/:videoId/comments/:commentId ───────────────────────
router.delete('/:commentId', requireAuth, async (req, res, next) => {
  try {
    const { rows } = await db.query(
      'SELECT user_id FROM comments WHERE id=$1 AND video_id=$2 AND deleted_at IS NULL',
      [req.params.commentId, req.params.videoId],
    );
    if (!rows.length) return next(createError(404, 'Comment not found'));

    const isOwner = rows[0].user_id === req.user.id;
    const isMod   = ['moderator', 'admin'].includes(req.user.role);
    if (!isOwner && !isMod) return next(createError(403, 'Cannot delete this comment'));

    // Soft-delete (preserves thread structure)
    await db.query(
      "UPDATE comments SET deleted_at=NOW(), body='[deleted]' WHERE id=$1",
      [req.params.commentId],
    );
    res.status(204).end();
  } catch (err) { next(err); }
});

// ── POST /api/v1/videos/:videoId/comments/:commentId/like ─────────────────────
router.post('/:commentId/like', requireAuth, async (req, res, next) => {
  try {
    await db.query(
      `INSERT INTO comment_likes (user_id, comment_id) VALUES ($1, $2)
       ON CONFLICT DO NOTHING`,
      [req.user.id, req.params.commentId],
    );
    // Sync like_count
    await db.query(
      `UPDATE comments SET like_count = (
         SELECT COUNT(*) FROM comment_likes WHERE comment_id=$1
       ) WHERE id=$1`,
      [req.params.commentId],
    );
    res.json({ liked: true });
  } catch (err) { next(err); }
});

// ── DELETE /api/v1/videos/:videoId/comments/:commentId/like ──────────────────
router.delete('/:commentId/like', requireAuth, async (req, res, next) => {
  try {
    await db.query(
      'DELETE FROM comment_likes WHERE user_id=$1 AND comment_id=$2',
      [req.user.id, req.params.commentId],
    );
    await db.query(
      `UPDATE comments SET like_count = (
         SELECT COUNT(*) FROM comment_likes WHERE comment_id=$1
       ) WHERE id=$1`,
      [req.params.commentId],
    );
    res.json({ liked: false });
  } catch (err) { next(err); }
});

module.exports = router;
