'use strict';

/**
 * index.js — HTTP server bootstrap.
 *
 * Startup sequence:
 *  1. Validate env vars (via config.js — throws immediately if missing)
 *  2. Verify DB connectivity
 *  3. Start the HTTP server
 *  4. Register SIGTERM/SIGINT handlers for graceful shutdown
 */

const http = require('http');
const app = require('./app');
const db = require('./db');
const config = require('./config');
const logger = require('./logger');
const { closeQueue } = require('./services/queueService');

const server = http.createServer(app);

async function start() {
  // Verify DB is reachable before accepting traffic
  try {
    await db.ping();
    logger.info({ host: config.db.host, db: config.db.database }, 'Database connected');
  } catch (err) {
    logger.error({ err }, 'Cannot connect to database — refusing to start');
    process.exit(1);
  }

  server.listen(config.server.port, '0.0.0.0', () => {
    logger.info(
      { port: config.server.port, env: config.env },
      '🚀  API server listening'
    );
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Graceful shutdown
// ─────────────────────────────────────────────────────────────────────────────
async function shutdown(signal) {
  logger.info({ signal }, 'Shutdown signal received');

  // 1. Stop accepting new connections
  server.close(async () => {
    logger.info('HTTP server closed');

    // 2. Close BullMQ queue connection
    await closeQueue();

    // 3. Drain the DB pool
    await db.close();

    logger.info('Graceful shutdown complete. Goodbye.');
    process.exit(0);
  });

  // Force exit if graceful shutdown takes too long (15 s)
  setTimeout(() => {
    logger.error('Graceful shutdown timed out — forcing exit');
    process.exit(1);
  }, 15_000);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

process.on('unhandledRejection', (reason) => {
  logger.error({ reason }, 'Unhandled promise rejection');
});

start().catch((err) => {
  logger.error({ err }, 'Fatal startup error');
  process.exit(1);
});
