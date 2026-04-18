'use strict';

/**
 * auth.js middleware
 *
 * Verifies the JWT access token that must be present as either:
 *   A) Authorization: Bearer <token>  header  (preferred for API clients)
 *   B) hub_access  httpOnly cookie            (used by browser / Flutter WebView)
 *
 * On success: populates req.user = { id, email, role }
 * On failure: returns 401 JSON — never throws to Express error handler
 *             (401s are expected, not exceptional)
 */

const jwt    = require('jsonwebtoken');
const config = require('../config');

/**
 * requireAuth — attach to any route that needs a logged-in user.
 */
function requireAuth(req, res, next) {
  const token = extractToken(req);
  if (!token) {
    return res.status(401).json({ error: 'Authentication required' });
  }

  try {
    const payload = jwt.verify(token, config.jwt.accessSecret);
    req.user = {
      id:    payload.sub,   // UUID
      email: payload.email,
      role:  payload.role,
    };
    next();
  } catch (err) {
    if (err.name === 'TokenExpiredError') {
      return res.status(401).json({ error: 'Token expired', code: 'TOKEN_EXPIRED' });
    }
    return res.status(401).json({ error: 'Invalid token' });
  }
}

/**
 * requireRole — use AFTER requireAuth.
 * Example: router.delete('/:id', requireAuth, requireRole('admin'), handler)
 *
 * @param {...string} roles - Allowed roles
 */
function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.user) return res.status(401).json({ error: 'Authentication required' });
    if (!roles.includes(req.user.role)) {
      return res.status(403).json({ error: 'Insufficient permissions' });
    }
    next();
  };
}

/**
 * optionalAuth — populates req.user if a valid token is present but
 * does NOT block the request if absent or invalid. Useful for public
 * endpoints that behave differently for logged-in users.
 */
function optionalAuth(req, res, next) {
  const token = extractToken(req);
  if (token) {
    try {
      const payload = jwt.verify(token, config.jwt.accessSecret);
      req.user = { id: payload.sub, email: payload.email, role: payload.role };
    } catch { /* silent — unauthenticated request is fine */ }
  }
  next();
}

// ─────────────────────────────────────────────────────────────────────────────

function extractToken(req) {
  // 1. Authorization header (Bearer scheme)
  const authHeader = req.headers['authorization'];
  if (authHeader?.startsWith('Bearer ')) {
    return authHeader.slice(7).trim();
  }
  // 2. httpOnly cookie (set by /auth/login)
  if (req.cookies?.hub_access) {
    return req.cookies.hub_access;
  }
  return null;
}

module.exports = { requireAuth, requireRole, optionalAuth };
