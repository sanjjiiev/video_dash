'use strict';

/**
 * rateLimiter.js
 *
 * Named rate-limit presets for different endpoint sensitivities.
 * All limiters use an in-memory store (default) — swap to RedisStore
 * when running multiple API replicas behind a load balancer.
 */

const rateLimit = require('express-rate-limit');

// Shared error response format
const handler = (req, res) => {
  res.status(429).json({
    error: 'Too many requests — please slow down and try again shortly.',
    retryAfter: Math.ceil(req.rateLimit.resetTime / 1000),
  });
};

/**
 * authLimiter — strict limit for login/register endpoints to prevent
 * brute-force and credential stuffing attacks.
 * 10 requests per 15 minutes per IP.
 */
const authLimiter = rateLimit({
  windowMs:        15 * 60 * 1000,
  max:             10,
  standardHeaders: true,
  legacyHeaders:   false,
  handler,
  keyGenerator: (req) => req.ip,
  skip: () => process.env.NODE_ENV === 'test',
});

/**
 * uploadLimiter — prevents upload spam.
 * 20 uploads per hour per user (falls back to IP if unauthenticated).
 */
const uploadLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max:      20,
  standardHeaders: true,
  legacyHeaders:   false,
  handler,
  keyGenerator: (req) => req.user?.id ?? req.ip,
  skip: () => process.env.NODE_ENV === 'test',
});

/**
 * apiLimiter — general API rate limit.
 * 200 requests per minute per user/IP.
 */
const apiLimiter = rateLimit({
  windowMs: 60 * 1000,
  max:      200,
  standardHeaders: true,
  legacyHeaders:   false,
  handler,
  keyGenerator: (req) => req.user?.id ?? req.ip,
  skip: () => process.env.NODE_ENV === 'test',
});

/**
 * keyLimiter — AES key delivery endpoint.
 * HLS players request this once per video per session, but aggressive
 * limiting prevents key enumeration attacks.
 * 60 requests per minute per user.
 */
const keyLimiter = rateLimit({
  windowMs: 60 * 1000,
  max:      60,
  standardHeaders: true,
  legacyHeaders:   false,
  handler,
  keyGenerator: (req) => req.user?.id ?? req.ip,
  skip: () => process.env.NODE_ENV === 'test',
});

module.exports = { authLimiter, uploadLimiter, apiLimiter, keyLimiter };
