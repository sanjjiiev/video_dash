-- =============================================================================
-- 001_init.sql  —  Initial schema for HUB 2.0
--
-- Run with:
--   psql -U $POSTGRES_USER -d $POSTGRES_DB -f db/migrations/001_init.sql
-- Or automatically via the postgres Docker image's /docker-entrypoint-initdb.d/
-- =============================================================================

-- Enable the pgcrypto extension for gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ─────────────────────────────────────────────────────────────────────────────
-- USERS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  email         VARCHAR(255) UNIQUE NOT NULL,
  password_hash VARCHAR(255)        NOT NULL,
  -- 'admin'    : can manage all content and users
  -- 'uploader' : can upload and manage their own videos
  -- 'viewer'   : read-only access to ready videos
  role          VARCHAR(20)  NOT NULL DEFAULT 'viewer'
                             CHECK (role IN ('admin','uploader','viewer')),
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);


-- ─────────────────────────────────────────────────────────────────────────────
-- REFRESH TOKENS  (httpOnly cookie rotation)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS refresh_tokens (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  -- Store ONLY the SHA-256 hash of the token — never the plaintext
  token_hash  VARCHAR(64) NOT NULL UNIQUE,
  expires_at  TIMESTAMPTZ NOT NULL,
  revoked     BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user ON refresh_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_hash ON refresh_tokens(token_hash);


-- ─────────────────────────────────────────────────────────────────────────────
-- VIDEOS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS videos (
  id               UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id         UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title            VARCHAR(500) NOT NULL,
  description      TEXT,

  -- Lifecycle: pending → processing → ready | failed
  status           VARCHAR(20)  NOT NULL DEFAULT 'pending'
                                CHECK (status IN ('pending','processing','ready','failed')),

  -- MinIO object key for the master HLS playlist
  master_key       VARCHAR(500),

  -- MinIO object key for the generated thumbnail (populated in Phase 3+)
  thumbnail_key    VARCHAR(500),

  -- Informational — populated by ffprobe after transcoding completes
  duration_seconds NUMERIC(10,2),

  -- For correlating with BullMQ logs
  job_id           VARCHAR(255),

  -- Human-readable error (populated on status = 'failed')
  error_message    TEXT,

  -- Soft-delete: hide from listings without losing data or MinIO objects
  deleted_at       TIMESTAMPTZ,

  created_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at       TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_videos_owner   ON videos(owner_id);
CREATE INDEX IF NOT EXISTS idx_videos_status  ON videos(status);
CREATE INDEX IF NOT EXISTS idx_videos_created ON videos(created_at DESC);


-- ─────────────────────────────────────────────────────────────────────────────
-- VIDEO RENDITIONS  (one row per quality tier per video)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS video_renditions (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  video_id     UUID        NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
  name         VARCHAR(10) NOT NULL CHECK (name IN ('1080p','720p','480p')),
  -- video + audio combined target bitrate in kbps
  bitrate_k    INTEGER,
  -- MinIO prefix for the playlist and segments (e.g. "videos/abc123/1080p")
  minio_prefix VARCHAR(500) NOT NULL,
  UNIQUE (video_id, name)
);

CREATE INDEX IF NOT EXISTS idx_renditions_video ON video_renditions(video_id);


-- ─────────────────────────────────────────────────────────────────────────────
-- WATCH TELEMETRY  (lightweight analytics; no PII beyond user_id)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS watch_events (
  id               UUID     PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID     REFERENCES users(id) ON DELETE SET NULL,
  video_id         UUID     NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
  -- Seconds of video actually watched in this session
  watch_duration   INTEGER  NOT NULL DEFAULT 0,
  -- Hashed IP for abuse detection (not raw — never store raw IPs in telemetry)
  ip_hash          VARCHAR(64),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_watch_video   ON watch_events(video_id);
CREATE INDEX IF NOT EXISTS idx_watch_user    ON watch_events(user_id);
CREATE INDEX IF NOT EXISTS idx_watch_created ON watch_events(created_at DESC);


-- ─────────────────────────────────────────────────────────────────────────────
-- updated_at trigger (auto-update on every row change)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION trigger_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_updated_at_users
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

CREATE TRIGGER set_updated_at_videos
  BEFORE UPDATE ON videos
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
