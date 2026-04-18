'use strict';

/**
 * db.js — PostgreSQL connection pool singleton.
 *
 * Uses the `pg` Pool which manages a fixed number of connections and
 * automatically handles reconnection. The pool is shared across all
 * request handlers — never create per-request connections.
 */

const { Pool }  = require('pg');
const config    = require('./config');
const logger    = require('./logger');

const pool = new Pool({
  host:               config.db.host,
  port:               config.db.port,
  database:           config.db.database,
  user:               config.db.user,
  password:           config.db.password,
  ssl:                config.db.ssl ? { rejectUnauthorized: true } : false,
  max:                config.db.max,
  idleTimeoutMillis:  config.db.idleTimeoutMs,
  connectionTimeoutMillis: config.db.connectionTimeoutMs,
});

// Log pool-level errors (e.g., Postgres server restarted)
pool.on('error', (err) => {
  logger.error({ err }, 'Unexpected pg pool error');
});

/**
 * Execute a parameterized query.
 * @param {string}   text   - SQL with $1, $2 … placeholders
 * @param {Array}    params - Bound parameters
 * @returns {Promise<import('pg').QueryResult>}
 */
async function query(text, params) {
  const start = Date.now();
  const result = await pool.query(text, params);
  logger.debug({ query: text, durationMs: Date.now() - start, rows: result.rowCount });
  return result;
}

/**
 * Check the database connection (used in /health endpoint).
 */
async function ping() {
  const result = await pool.query('SELECT 1 AS alive');
  return result.rows[0].alive === 1;
}

/**
 * Gracefully drain the pool on shutdown.
 */
async function close() {
  await pool.end();
  logger.info('Database pool closed');
}

module.exports = { query, ping, close, pool };
