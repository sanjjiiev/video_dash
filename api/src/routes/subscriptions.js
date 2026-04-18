'use strict';
const { Router } = require('express');
const { requireAuth } = require('../middleware/auth');
const db = require('../db');

const router = Router();

// ── GET /api/v1/subscriptions — list channels I'm subscribed to ───────────────
router.get('/', requireAuth, async (req, res, next) => {
  try {
    const { rows } = await db.query(
      `SELECT u.id, u.email, u.channel_name, u.avatar_url, u.subscriber_count,
              cs.created_at AS subscribed_at, cs.notify_new
         FROM channel_subscriptions cs
         JOIN users u ON u.id = cs.channel_id
        WHERE cs.subscriber_id = $1
        ORDER BY cs.created_at DESC`,
      [req.user.id],
    );
    res.json({ subscriptions: rows });
  } catch (err) { next(err); }
});

// ── GET /api/v1/subscriptions/feed — videos from subscribed channels ──────────
router.get('/feed', requireAuth, async (req, res, next) => {
  try {
    const { page = 1, limit = 20 } = req.query;
    const offset = (Number(page) - 1) * Number(limit);

    const { rows } = await db.query(
      `SELECT v.*, u.email AS owner_email, u.channel_name, u.avatar_url AS owner_avatar_url
         FROM videos v
         JOIN users u ON u.id = v.owner_id
        WHERE v.owner_id IN (
          SELECT channel_id FROM channel_subscriptions WHERE subscriber_id = $1
        )
          AND v.status = 'ready'
          AND v.deleted_at IS NULL
        ORDER BY v.created_at DESC
        LIMIT $2 OFFSET $3`,
      [req.user.id, Number(limit), offset],
    );

    const { rows: [cnt] } = await db.query(
      `SELECT COUNT(*) AS total FROM videos v
        WHERE v.owner_id IN (
          SELECT channel_id FROM channel_subscriptions WHERE subscriber_id = $1
        ) AND v.status='ready' AND v.deleted_at IS NULL`,
      [req.user.id],
    );

    res.json({
      videos:     rows,
      pagination: { page: Number(page), limit: Number(limit), total: Number(cnt.total) },
    });
  } catch (err) { next(err); }
});

// ── POST /api/v1/subscriptions/:channelId — subscribe ────────────────────────
router.post('/:channelId', requireAuth, async (req, res, next) => {
  try {
    if (req.params.channelId === req.user.id) {
      return res.status(400).json({ error: 'Cannot subscribe to yourself' });
    }

    // Verify channel exists
    const { rows: [channel] } = await db.query(
      'SELECT id, email, channel_name FROM users WHERE id=$1',
      [req.params.channelId],
    );
    if (!channel) return res.status(404).json({ error: 'Channel not found' });

    await db.query(
      `INSERT INTO channel_subscriptions (subscriber_id, channel_id, notify_new)
       VALUES ($1, $2, $3)
       ON CONFLICT (subscriber_id, channel_id) DO NOTHING`,
      [req.user.id, req.params.channelId, req.body.notify_new ?? true],
    );

    res.status(201).json({
      subscribed: true,
      channel: { id: channel.id, name: channel.channel_name || channel.email },
    });
  } catch (err) { next(err); }
});

// ── DELETE /api/v1/subscriptions/:channelId — unsubscribe ────────────────────
router.delete('/:channelId', requireAuth, async (req, res, next) => {
  try {
    await db.query(
      'DELETE FROM channel_subscriptions WHERE subscriber_id=$1 AND channel_id=$2',
      [req.user.id, req.params.channelId],
    );
    res.json({ subscribed: false });
  } catch (err) { next(err); }
});

// ── GET /api/v1/subscriptions/status/:channelId ───────────────────────────────
router.get('/status/:channelId', requireAuth, async (req, res, next) => {
  try {
    const { rows } = await db.query(
      'SELECT notify_new FROM channel_subscriptions WHERE subscriber_id=$1 AND channel_id=$2',
      [req.user.id, req.params.channelId],
    );
    res.json({ subscribed: rows.length > 0, notify_new: rows[0]?.notify_new ?? false });
  } catch (err) { next(err); }
});

// ── PATCH /api/v1/subscriptions/:channelId — toggle notifications ─────────────
router.patch('/:channelId', requireAuth, async (req, res, next) => {
  try {
    await db.query(
      `UPDATE channel_subscriptions SET notify_new=$1
        WHERE subscriber_id=$2 AND channel_id=$3`,
      [req.body.notify_new, req.user.id, req.params.channelId],
    );
    res.json({ ok: true });
  } catch (err) { next(err); }
});

module.exports = router;
