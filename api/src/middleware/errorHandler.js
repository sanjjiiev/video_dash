'use strict';

/**
 * errorHandler.js — Express global error handler.
 *
 * Must be registered LAST with app.use(errorHandler).
 * Catches all errors thrown or passed to next(err) from route handlers.
 *
 * Normalizes different error types into a consistent JSON response:
 *   { error: string, code?: string, details?: any }
 *
 * Security: production responses NEVER leak stack traces or internal details.
 */

const logger = require('../logger');

// Known "safe" error codes that map to specific HTTP statuses
const HTTP_STATUS_MAP = {
  VALIDATION_ERROR:   400,
  UNAUTHORIZED:       401,
  FORBIDDEN:          403,
  NOT_FOUND:          404,
  CONFLICT:           409,
  UNPROCESSABLE:      422,
  TOO_LARGE:          413,
  RATE_LIMITED:       429,
};

function errorHandler(err, req, res, next) { // eslint-disable-line no-unused-vars
  // Log with full context (safe — never sent to client in prod)
  logger.error({
    err:       err.message,
    stack:     err.stack,
    code:      err.code,
    requestId: req.id,
    path:      req.path,
    method:    req.method,
    userId:    req.user?.id,
  }, 'Request error');

  // ── Multer errors (file upload) ──────────────────────────────────────────
  if (err.code === 'LIMIT_FILE_SIZE') {
    return res.status(413).json({ error: 'File too large', code: 'TOO_LARGE' });
  }
  if (err.code === 'LIMIT_UNEXPECTED_FILE') {
    return res.status(400).json({ error: 'Unexpected file field', code: 'VALIDATION_ERROR' });
  }

  // ── express-validator errors (passed as err.array()) ─────────────────────
  if (err.type === 'validation' && Array.isArray(err.errors)) {
    return res.status(400).json({
      error:   'Validation failed',
      code:    'VALIDATION_ERROR',
      details: err.errors.map(e => ({ field: e.path, message: e.msg })),
    });
  }

  // ── Application errors (thrown with err.code from our code) ──────────────
  if (err.code && HTTP_STATUS_MAP[err.code]) {
    return res.status(HTTP_STATUS_MAP[err.code]).json({
      error: err.message,
      code:  err.code,
    });
  }

  // ── PostgreSQL unique violation ───────────────────────────────────────────
  if (err.code === '23505') {
    return res.status(409).json({ error: 'Resource already exists', code: 'CONFLICT' });
  }

  // ── Fallback: 500 Internal Server Error ──────────────────────────────────
  const isDev = process.env.NODE_ENV === 'development';
  res.status(err.statusCode ?? err.status ?? 500).json({
    error:  isDev ? err.message : 'An unexpected error occurred',
    ...(isDev && { stack: err.stack }),
  });
}

/**
 * Helper: create a typed application error.
 * Usage: throw createError('Video not found', 'NOT_FOUND')
 */
function createError(message, code, extra = {}) {
  const err = new Error(message);
  err.code  = code;
  Object.assign(err, extra);
  return err;
}

module.exports = { errorHandler, createError };
