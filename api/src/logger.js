'use strict';
// Identical structured logger pattern used in the worker for consistency.
const { createLogger, format, transports } = require('winston');
const { combine, timestamp, errors, json, colorize, printf } = format;

const isDev = process.env.NODE_ENV === 'development';

const devFormat = combine(
  colorize({ all: true }),
  timestamp({ format: 'HH:mm:ss' }),
  errors({ stack: true }),
  printf(({ level, message, timestamp: ts, requestId, userId, ...meta }) => {
    const rid = requestId ? `[rid:${requestId}]` : '';
    const uid = userId    ? `[uid:${userId}]`    : '';
    const metaStr = Object.keys(meta).length ? ` ${JSON.stringify(meta)}` : '';
    return `${ts} ${level} ${rid}${uid} ${message}${metaStr}`;
  })
);

const prodFormat = combine(timestamp(), errors({ stack: true }), json());

const logger = createLogger({
  level:     process.env.LOG_LEVEL ?? 'info',
  format:    isDev ? devFormat : prodFormat,
  transports: [new transports.Console()],
  exitOnError: false,
});

module.exports = logger;
