'use strict';

/**
 * config.js — Centralized, validated configuration.
 *
 * All env vars are read ONCE at startup. Any missing required var throws
 * immediately so the container fails fast with a clear message rather than
 * crashing at 3 AM with a cryptic "Cannot read property of undefined".
 */

function require_env(key) {
  const val = process.env[key];
  if (!val) throw new Error(`Missing required environment variable: ${key}`);
  return val;
}

function optional_env(key, fallback) {
  return process.env[key] ?? fallback;
}

const config = {
  env: optional_env('NODE_ENV', 'production'),
  isDev: optional_env('NODE_ENV', 'production') === 'development',

  server: {
    port:    parseInt(optional_env('PORT', '3000'), 10),
    host:    optional_env('HOST', '0.0.0.0'),
    // Origin(s) allowed by CORS — comma-separated in env
    corsOrigins: optional_env('CORS_ORIGINS', 'http://localhost:8080').split(',').map(s => s.trim()),
  },

  jwt: {
    accessSecret:  require_env('JWT_ACCESS_SECRET'),
    refreshSecret: require_env('JWT_REFRESH_SECRET'),
    accessExpiresIn:  optional_env('JWT_ACCESS_EXPIRES',  '15m'),
    refreshExpiresIn: optional_env('JWT_REFRESH_EXPIRES', '7d'),
  },

  db: {
    host:     optional_env('POSTGRES_HOST', 'localhost'),
    port:     parseInt(optional_env('POSTGRES_PORT', '5432'), 10),
    database: require_env('POSTGRES_DB'),
    user:     require_env('POSTGRES_USER'),
    password: require_env('POSTGRES_PASSWORD'),
    ssl:      optional_env('POSTGRES_SSL', 'false') === 'true',
    // Connection pool sizing
    max:             parseInt(optional_env('DB_POOL_MAX', '10'), 10),
    idleTimeoutMs:   parseInt(optional_env('DB_IDLE_TIMEOUT_MS', '30000'), 10),
    connectionTimeoutMs: parseInt(optional_env('DB_CONN_TIMEOUT_MS', '5000'), 10),
  },

  redis: {
    host:     optional_env('REDIS_HOST', 'localhost'),
    port:     parseInt(optional_env('REDIS_PORT', '6379'), 10),
    password: optional_env('REDIS_PASSWORD', undefined),
    db:       parseInt(optional_env('REDIS_DB', '0'), 10),
  },

  minio: {
    endpoint:  optional_env('MINIO_ENDPOINT', 'localhost'),
    port:      parseInt(optional_env('MINIO_PORT', '9000'), 10),
    useSSL:    optional_env('MINIO_USE_SSL', 'false') === 'true',
    accessKey: require_env('MINIO_ACCESS_KEY'),
    secretKey: require_env('MINIO_SECRET_KEY'),
    buckets: {
      videos:      optional_env('MINIO_BUCKET', 'videos'),
      keys:        optional_env('MINIO_KEYS_BUCKET', 'encryption-keys'),
      rawUploads:  optional_env('MINIO_RAW_BUCKET', 'raw-uploads'),
    },
    // How long (seconds) presigned upload URLs remain valid
    presignedUploadExpiry: parseInt(optional_env('MINIO_UPLOAD_EXPIRY_S', '3600'), 10),
  },

  queue: {
    name: optional_env('QUEUE_NAME', 'transcode'),
  },

  // bcrypt cost factor — 12 is a solid default; increase for higher security at cost of latency
  bcryptRounds: parseInt(optional_env('BCRYPT_ROUNDS', '12'), 10),

  // Max upload size in bytes (500 MB default)
  maxUploadBytes: parseInt(optional_env('MAX_UPLOAD_BYTES', String(500 * 1024 * 1024)), 10),
};

module.exports = config;
