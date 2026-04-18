-- =============================================================================
-- 003_schema_fixes.sql  —  Adds tables missed from 001+002 initial runs
--
-- Safe to run repeatedly (all statements are idempotent).
-- Apply to a running DB:
--   docker exec hub_postgres psql -U hubuser -d hub -f /docker-entrypoint-initdb.d/003_schema_fixes.sql
-- =============================================================================

-- ── view_count on videos ─────────────────────────────────────────────────────
ALTER TABLE videos
  ADD COLUMN IF NOT EXISTS view_count      BIGINT      NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS like_count      INT         NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS dislike_count   INT         NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS comment_count   INT         NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS visibility      VARCHAR(20) NOT NULL DEFAULT 'public'
                                           CHECK (visibility IN ('public','unlisted','private'));

-- ── Comments ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS comments (
  id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  video_id    UUID         NOT NULL REFERENCES videos(id)   ON DELETE CASCADE,
  user_id     UUID         NOT NULL REFERENCES users(id)    ON DELETE CASCADE,
  parent_id   UUID         REFERENCES comments(id)          ON DELETE CASCADE,  -- NULL = top-level
  body        TEXT         NOT NULL CHECK(length(body) BETWEEN 1 AND 10000),
  like_count  INT          NOT NULL DEFAULT 0,
  pinned      BOOLEAN      NOT NULL DEFAULT FALSE,
  deleted_at  TIMESTAMPTZ,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_comments_video  ON comments(video_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_comments_user   ON comments(user_id);
CREATE INDEX IF NOT EXISTS idx_comments_parent ON comments(parent_id);

-- Trigger: keep comment_count in sync on videos
CREATE OR REPLACE FUNCTION inc_comment_count() RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.parent_id IS NULL THEN
    UPDATE videos SET comment_count = comment_count + 1 WHERE id = NEW.video_id;
  ELSIF TG_OP = 'DELETE' AND OLD.parent_id IS NULL THEN
    UPDATE videos SET comment_count = GREATEST(0, comment_count - 1) WHERE id = OLD.video_id;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_comment_count ON comments;
CREATE TRIGGER trg_comment_count
  AFTER INSERT OR DELETE ON comments
  FOR EACH ROW EXECUTE FUNCTION inc_comment_count();

-- updated_at trigger for comments
DROP TRIGGER IF EXISTS set_updated_at_comments ON comments;
CREATE TRIGGER set_updated_at_comments
  BEFORE UPDATE ON comments
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();

-- ── Comment likes (deduplicated) ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS comment_likes (
  user_id     UUID NOT NULL REFERENCES users(id)    ON DELETE CASCADE,
  comment_id  UUID NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, comment_id)
);

-- ── Playlists ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS playlists (
  id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id    UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title       VARCHAR(200) NOT NULL,
  description TEXT,
  visibility  VARCHAR(20)  NOT NULL DEFAULT 'private'
                           CHECK(visibility IN ('public','unlisted','private')),
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_playlists_owner ON playlists(owner_id);

CREATE TABLE IF NOT EXISTS playlist_items (
  playlist_id UUID NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
  video_id    UUID NOT NULL REFERENCES videos(id)    ON DELETE CASCADE,
  position    INT  NOT NULL DEFAULT 0,
  added_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (playlist_id, video_id)
);

-- ── Watch Later ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS watch_later (
  user_id   UUID NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
  video_id  UUID NOT NULL REFERENCES videos(id)  ON DELETE CASCADE,
  added_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, video_id)
);
CREATE INDEX IF NOT EXISTS idx_watch_later_user ON watch_later(user_id, added_at DESC);

-- ── Role check: add 'creator' role to the existing CHECK constraint ────────────
-- We can't ALTER CHECK inline; drop+recreate
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE users ADD CONSTRAINT users_role_check
  CHECK (role IN ('admin','creator','uploader','moderator','viewer'));

-- ── display_name alias ────────────────────────────────────────────────────────
-- channel_name already added in 002; just ensure display_name view exists
-- (we treat channel_name as the canonical display name — nothing more needed)

-- Done
SELECT 'Schema 003 applied successfully' AS status;
