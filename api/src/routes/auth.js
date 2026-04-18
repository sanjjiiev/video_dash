'use strict';

/**
 * routes/auth.js
 *
 * POST /api/v1/auth/register  — Create a new user account
 * POST /api/v1/auth/login     — Issue access + refresh tokens
 * POST /api/v1/auth/refresh   — Rotate refresh token, issue new access token
 * POST /api/v1/auth/logout    — Revoke the current refresh token
 * GET  /api/v1/auth/me        — Return current user profile
 *
 * Token strategy:
 *  - Access token:  short-lived (15min), sent as JSON body + httpOnly cookie
 *  - Refresh token: long-lived (7d), stored hashed in DB, sent as httpOnly cookie ONLY
 *    (never in JSON body — prevents token leakage via XSS)
 */

const express  = require('express');
const bcrypt   = require('bcryptjs');
const jwt      = require('jsonwebtoken');
const crypto   = require('crypto');
const { body, validationResult } = require('express-validator');

const db       = require('../db');
const config   = require('../config');
const logger   = require('../logger');
const { requireAuth }   = require('../middleware/auth');
const { authLimiter }   = require('../middleware/rateLimiter');
const { createError }   = require('../middleware/errorHandler');

const router = express.Router();

// ── Token generation helpers ──────────────────────────────────────────────────

function signAccessToken(user) {
  return jwt.sign(
    { sub: user.id, email: user.email, role: user.role },
    config.jwt.accessSecret,
    { expiresIn: config.jwt.accessExpiresIn, issuer: 'hub-api' }
  );
}

function generateRefreshToken() {
  // 48 bytes → 64-char base64url token (URL-safe, no padding)
  return crypto.randomBytes(48).toString('base64url');
}

function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

function setRefreshCookie(res, token) {
  res.cookie('hub_refresh', token, {
    httpOnly: true,
    secure:   !config.isDev,     // HTTPS only in production
    sameSite: config.isDev ? 'lax' : 'strict',
    maxAge:   7 * 24 * 60 * 60 * 1000, // 7 days in ms
    path:     '/api/v1/auth',   // scoped to auth routes only
  });
}

function setAccessCookie(res, token) {
  res.cookie('hub_access', token, {
    httpOnly: true,
    secure:   !config.isDev,
    sameSite: config.isDev ? 'lax' : 'strict',
    maxAge:   15 * 60 * 1000,  // 15 minutes
    path:     '/',
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/auth/register
// ─────────────────────────────────────────────────────────────────────────────
router.post('/register',
  authLimiter,
  [
    body('email').isEmail().normalizeEmail(),
    body('password').isLength({ min: 8 }).withMessage('Password must be at least 8 characters'),
  ],
  async (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    }

    const { email, password, role } = req.body;
    // Only admins can create admins/uploaders — default is viewer
    const assignedRole = 'viewer';

    try {
      const hash = await bcrypt.hash(password, config.bcryptRounds);
      const result = await db.query(
        `INSERT INTO users (email, password_hash, role)
         VALUES ($1, $2, $3)
         RETURNING id, email, role, created_at`,
        [email, hash, assignedRole]
      );
      const user = result.rows[0];
      logger.info({ userId: user.id, email }, 'User registered');
      res.status(201).json({ id: user.id, email: user.email, role: user.role });
    } catch (err) {
      next(err); // pg unique violation (23505) → errorHandler returns 409
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/auth/login
// ─────────────────────────────────────────────────────────────────────────────
router.post('/login',
  authLimiter,
  [
    body('email').isEmail().normalizeEmail(),
    body('password').notEmpty(),
  ],
  async (req, res, next) => {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({ error: 'Validation failed', details: errors.array() });
    }

    const { email, password } = req.body;

    try {
      const result = await db.query(
        'SELECT id, email, password_hash, role FROM users WHERE email = $1',
        [email]
      );

      const user = result.rows[0];

      // Constant-time comparison — prevent user enumeration via timing
      const passwordMatch = user
        ? await bcrypt.compare(password, user.password_hash)
        : await bcrypt.compare(password, '$2b$12$invalidhashpaddingtoconstanttime');

      if (!user || !passwordMatch) {
        // Generic message — never reveal whether the email exists
        return res.status(401).json({ error: 'Invalid email or password' });
      }

      // Issue tokens
      const accessToken  = signAccessToken(user);
      const refreshToken = generateRefreshToken();
      const tokenHash    = hashToken(refreshToken);
      const expiresAt    = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);

      await db.query(
        'INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)',
        [user.id, tokenHash, expiresAt]
      );

      setAccessCookie(res, accessToken);
      setRefreshCookie(res, refreshToken);

      logger.info({ userId: user.id }, 'User logged in');

      res.json({
        accessToken,
        user: { id: user.id, email: user.email, role: user.role },
      });
    } catch (err) {
      next(err);
    }
  }
);

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/auth/refresh  — Rotate refresh token
// ─────────────────────────────────────────────────────────────────────────────
router.post('/refresh', authLimiter, async (req, res, next) => {
  const incomingToken = req.cookies?.hub_refresh;
  if (!incomingToken) {
    return res.status(401).json({ error: 'No refresh token provided' });
  }

  const tokenHash = hashToken(incomingToken);

  try {
    // Look up the hashed token — checks revoked flag and expiry in one query
    const result = await db.query(
      `SELECT rt.id AS token_id, rt.expires_at, rt.revoked,
              u.id, u.email, u.role
       FROM refresh_tokens rt
       JOIN users u ON u.id = rt.user_id
       WHERE rt.token_hash = $1`,
      [tokenHash]
    );

    const record = result.rows[0];

    if (!record || record.revoked || new Date(record.expires_at) < new Date()) {
      // Token reuse detected or expired — invalidate all tokens for this user (optional)
      if (record) {
        await db.query('UPDATE refresh_tokens SET revoked = TRUE WHERE user_id = $1', [record.id]);
      }
      return res.status(401).json({ error: 'Refresh token invalid or expired' });
    }

    // Rotate: revoke old token, issue new pair
    await db.query('UPDATE refresh_tokens SET revoked = TRUE WHERE id = $1', [record.token_id]);

    const user         = { id: record.id, email: record.email, role: record.role };
    const accessToken  = signAccessToken(user);
    const newRefresh   = generateRefreshToken();
    const newHash      = hashToken(newRefresh);
    const expiresAt    = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);

    await db.query(
      'INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)',
      [user.id, newHash, expiresAt]
    );

    setAccessCookie(res, accessToken);
    setRefreshCookie(res, newRefresh);

    res.json({ accessToken, user: { id: user.id, email: user.email, role: user.role } });
  } catch (err) {
    next(err);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// POST /api/v1/auth/logout
// ─────────────────────────────────────────────────────────────────────────────
router.post('/logout', async (req, res, next) => {
  const token = req.cookies?.hub_refresh;
  if (token) {
    try {
      await db.query(
        'UPDATE refresh_tokens SET revoked = TRUE WHERE token_hash = $1',
        [hashToken(token)]
      );
    } catch (err) {
      logger.warn({ err }, 'Failed to revoke refresh token on logout');
    }
  }
  res.clearCookie('hub_access');
  res.clearCookie('hub_refresh', { path: '/api/v1/auth' });
  res.json({ message: 'Logged out successfully' });
});

// ─────────────────────────────────────────────────────────────────────────────
// GET /api/v1/auth/me
// ─────────────────────────────────────────────────────────────────────────────
router.get('/me', requireAuth, async (req, res, next) => {
  try {
    const result = await db.query(
      'SELECT id, email, role, created_at FROM users WHERE id = $1',
      [req.user.id]
    );
    if (!result.rows[0]) return res.status(404).json({ error: 'User not found' });
    res.json(result.rows[0]);
  } catch (err) {
    next(err);
  }
});

module.exports = router;
