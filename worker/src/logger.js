'use strict';

/**
 * logger.js
 *
 * Structured JSON logger using Winston. In production, all logs are emitted
 * as JSON so they can be ingested by Loki, Datadog, or any log aggregator.
 * In development (NODE_ENV=development), a colorized, human-readable format
 * is used instead.
 */

const { createLogger, format, transports } = require('winston');

const { combine, timestamp, errors, json, colorize, printf } = format;

// ── Development format (pretty, colorized) ──────────────────────────────────
const devFormat = combine(
  colorize({ all: true }),
  timestamp({ format: 'HH:mm:ss' }),
  errors({ stack: true }),
  printf(({ level, message, timestamp: ts, jobId, videoId, ...meta }) => {
    const prefix = jobId ? `[job:${jobId}]` : '';
    const vid    = videoId ? `[vid:${videoId}]` : '';
    const metaStr = Object.keys(meta).length ? ` ${JSON.stringify(meta)}` : '';
    return `${ts} ${level} ${prefix}${vid} ${message}${metaStr}`;
  })
);

// ── Production format (structured JSON) ─────────────────────────────────────
const prodFormat = combine(
  timestamp(),
  errors({ stack: true }),
  json()
);

const isDev = process.env.NODE_ENV === 'development';

const logger = createLogger({
  level: process.env.LOG_LEVEL ?? 'info',
  format: isDev ? devFormat : prodFormat,
  transports: [
    new transports.Console(),
  ],
  // Don't crash the worker process if the logger itself fails
  exitOnError: false,
});

module.exports = logger;
