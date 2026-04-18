'use strict';

/**
 * app.js — Express application factory.
 *
 * Keeps application setup separate from the HTTP server (index.js)
 * so it can be imported cleanly in tests without binding to a port.
 */

const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const compression = require('compression');
const cookieParser = require('cookie-parser');
const { v4: uuidv4 } = require('uuid');

const config = require('./config');
const logger = require('./logger');
const db = require('./db');
const { errorHandler } = require('./middleware/errorHandler');
const { apiLimiter } = require('./middleware/rateLimiter');

// Routes — Phase 1 & 2
const authRoutes = require('./routes/auth');
const videoRoutes = require('./routes/videos');
const streamRoutes = require('./routes/stream');
const keyRoutes = require('./routes/keys');

// Routes — Phase 4
const chaptersRoutes     = require('./routes/chapters');
const subscriptionRoutes = require('./routes/subscriptions');
const analyticsRoutes    = require('./routes/analytics');
const commentsRoutes     = require('./routes/comments');
const playlistsRoutes    = require('./routes/playlists');

const app = express();

// ── Trust proxy (Nginx is the first hop) ─────────────────────────────────────
// Required for express-rate-limit to see the real client IP (X-Forwarded-For)
// Set to 1 because we have exactly one reverse proxy (Nginx) in front.
app.set('trust proxy', 1);

// ── Security headers (Helmet) ─────────────────────────────────────────────────
app.use(helmet({
  // Allow HLS video to be played inline in browsers
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      mediaSrc: ["'self'", 'blob:'],
      connectSrc: ["'self'", ...config.server.corsOrigins],
      scriptSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
    },
  },
  // Prevent clickjacking — video players should not be iframed from unknown origins
  frameguard: { action: 'sameorigin' },
  // HSTS — only in production
  hsts: config.isDev ? false : { maxAge: 31536000, includeSubDomains: true },
}));

// ── CORS ──────────────────────────────────────────────────────────────────────
app.use(cors({
  origin: (origin, cb) => {
    // Allow requests with no origin (mobile apps, curl, Postman)
    if (!origin || config.server.corsOrigins.includes(origin)) return cb(null, true);
    cb(new Error(`CORS: origin ${origin} is not allowed`));
  },
  credentials: true,    // Required for httpOnly cookies to be sent cross-origin
  methods: ['GET', 'POST', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Worker-Secret'],
}));

// ── Body parsers ──────────────────────────────────────────────────────────────
// We only parse JSON for non-upload routes.
// The upload route uses multipart (handled by Multer) — no body-parser needed there.
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: false, limit: '1mb' }));
app.use(cookieParser());

// ── Compression ───────────────────────────────────────────────────────────────
// Compress JSON responses. Skip binary/video streams (already compressed).
app.use(compression({
  filter: (req, res) => {
    const ct = res.getHeader('Content-Type') ?? '';
    if (ct.includes('video/') || ct.includes('application/octet-stream')) return false;
    return compression.filter(req, res);
  },
}));

// ── Request ID (for log correlation) ─────────────────────────────────────────
app.use((req, res, next) => {
  req.id = req.headers['x-request-id'] ?? uuidv4();
  res.setHeader('X-Request-ID', req.id);
  next();
});

// ── Access logging ────────────────────────────────────────────────────────────
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    logger.info({
      requestId: req.id,
      method: req.method,
      path: req.path,
      status: res.statusCode,
      ms: Date.now() - start,
      ip: req.ip,
    }, 'HTTP request');
  });
  next();
});

// ─────────────────────────────────────────────────────────────────────────────
// Routes
// ─────────────────────────────────────────────────────────────────────────────
app.use('/api/v1/auth', authRoutes);
app.use('/api/v1/videos', videoRoutes);
app.use('/api/v1', streamRoutes);  // /hls/* + /internal/hls-auth + /videos/:id/stream
app.use('/api/v1/keys', keyRoutes);

// Phase 4 routes
app.use('/api/v1/videos/:videoId/chapters',  chaptersRoutes);
app.use('/api/v1/videos/:videoId/comments',  commentsRoutes);
app.use('/api/v1/subscriptions',             subscriptionRoutes);
app.use('/api/v1/analytics',                 analyticsRoutes);
app.use('/api/v1/playlists',                 playlistsRoutes);

// ── Health check (no auth, used by Docker healthcheck + load balancer) ────────
app.get('/health', (req, res) => {
  res.status(200).send('OK');
});


// ── 404 handler ───────────────────────────────────────────────────────────────
app.use((req, res) => {
  res.status(404).json({ error: `Route ${req.method} ${req.path} not found` });
});

// ── Global error handler (MUST be last) ──────────────────────────────────────
app.use(errorHandler);

module.exports = app;
