-- =============================================================================
-- 002_social.sql  —  Social & analytics tables for HUB 2.0 Phase 4
--
-- Run after 001_init.sql:
--   psql -U $POSTGRES_USER -d $POSTGRES_DB -f db/migrations/002_social.sql
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- Extend USERS table with social columns
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS channel_name     VARCHAR(100),
  ADD COLUMN IF NOT EXISTS avatar_url       VARCHAR(500),
  ADD COLUMN IF NOT EXISTS subscriber_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS view_count       BIGINT  NOT NULL DEFAULT 0;

-- ─────────────────────────────────────────────────────────────────────────────
-- Extend VIDEOS table with social counters
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE videos
  ADD COLUMN IF NOT EXISTS view_count    BIGINT  NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS like_count    INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS dislike_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS comment_count INTEGER NOT NULL DEFAULT 0;

-- ─────────────────────────────────────────────────────────────────────────────
-- VIDEO LIKES / DISLIKES
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS video_reactions (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  video_id   UUID        NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
  -- 'like' or 'dislike'
  reaction   VARCHAR(10) NOT NULL CHECK (reaction IN ('like','dislike')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, video_id)
);

CREATE INDEX IF NOT EXISTS idx_reactions_video ON video_reactions(video_id);
CREATE INDEX IF NOT EXISTS idx_reactions_user  ON video_reactions(user_id);


-- ─────────────────────────────────────────────────────────────────────────────
-- VIDEO COMMENTS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS video_comments (
  id          UUID   PRIMARY KEY DEFAULT gen_random_uuid(),
  video_id    UUID   NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
  user_id     UUID   NOT NULL REFERENCES users(id)  ON DELETE CASCADE,
  -- NULL = top-level; non-null = reply
  parent_id   UUID   REFERENCES video_comments(id) ON DELETE CASCADE,
  text        TEXT   NOT NULL,
  like_count  INTEGER NOT NULL DEFAULT 0,
  deleted_at  TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_comments_video  ON video_comments(video_id);
CREATE INDEX IF NOT EXISTS idx_comments_parent ON video_comments(parent_id);
CREATE INDEX IF NOT EXISTS idx_comments_user   ON video_comments(user_id);


-- ─────────────────────────────────────────────────────────────────────────────
-- COMMENT LIKES
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS comment_reactions (
  user_id    UUID NOT NULL REFERENCES users(id)          ON DELETE CASCADE,
  comment_id UUID NOT NULL REFERENCES video_comments(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, comment_id)
);


-- ─────────────────────────────────────────────────────────────────────────────
-- CHANNEL SUBSCRIPTIONS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS channel_subscriptions (
  subscriber_id UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  channel_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  -- whether to send push notifications for new uploads
  notify_new    BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (subscriber_id, channel_id),
  CHECK (subscriber_id <> channel_id)
);

CREATE INDEX IF NOT EXISTS idx_subs_subscriber ON channel_subscriptions(subscriber_id);
CREATE INDEX IF NOT EXISTS idx_subs_channel    ON channel_subscriptions(channel_id);

-- Trigger to keep users.subscriber_count in sync
CREATE OR REPLACE FUNCTION fn_update_subscriber_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE users SET subscriber_count = subscriber_count + 1 WHERE id = NEW.channel_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE users SET subscriber_count = GREATEST(subscriber_count - 1, 0) WHERE id = OLD.channel_id;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_subscriber_count ON channel_subscriptions;
CREATE TRIGGER trg_subscriber_count
  AFTER INSERT OR DELETE ON channel_subscriptions
  FOR EACH ROW EXECUTE FUNCTION fn_update_subscriber_count();


-- ─────────────────────────────────────────────────────────────────────────────
-- SAVED / WATCH-LATER VIDEOS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS saved_videos (
  user_id    UUID        NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
  video_id   UUID        NOT NULL REFERENCES videos(id)  ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, video_id)
);

CREATE INDEX IF NOT EXISTS idx_saved_user  ON saved_videos(user_id);
CREATE INDEX IF NOT EXISTS idx_saved_video ON saved_videos(video_id);


-- ─────────────────────────────────────────────────────────────────────────────
-- VIDEO ANALYTICS  (daily aggregated — avoids massive raw telemetry tables)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS video_analytics (
  video_id       UUID    NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
  date           DATE    NOT NULL,
  views          INTEGER NOT NULL DEFAULT 0,
  watch_seconds  BIGINT  NOT NULL DEFAULT 0,
  likes          INTEGER NOT NULL DEFAULT 0,
  dislikes       INTEGER NOT NULL DEFAULT 0,
  comments       INTEGER NOT NULL DEFAULT 0,
  shares         INTEGER NOT NULL DEFAULT 0,
  unique_viewers INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (video_id, date)
);

CREATE INDEX IF NOT EXISTS idx_analytics_date    ON video_analytics(date DESC);
CREATE INDEX IF NOT EXISTS idx_analytics_video   ON video_analytics(video_id);


-- ─────────────────────────────────────────────────────────────────────────────
-- NOTIFICATIONS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS notifications (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  -- 'new_video' | 'comment' | 'like' | 'subscriber'
  type       VARCHAR(30) NOT NULL,
  title      VARCHAR(200),
  body       TEXT,
  -- Optional related entity IDs
  video_id   UUID        REFERENCES videos(id)       ON DELETE SET NULL,
  actor_id   UUID        REFERENCES users(id)        ON DELETE SET NULL,
  is_read    BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notif_user    ON notifications(user_id, is_read, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notif_created ON notifications(created_at DESC);


-- ─────────────────────────────────────────────────────────────────────────────
-- PUSH TOKENS  (for future FCM / APNs integration)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS push_tokens (
  user_id    UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token      VARCHAR(500) NOT NULL,
  platform   VARCHAR(10)  NOT NULL CHECK (platform IN ('ios','android','web')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, token)
);


-- ─────────────────────────────────────────────────────────────────────────────
-- VIDEO CHAPTERS  (used by chapters_widget.dart)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS video_chapters (
  id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  video_id     UUID         NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
  title        VARCHAR(200) NOT NULL,
  start_second INTEGER      NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  UNIQUE (video_id, start_second)
);

CREATE INDEX IF NOT EXISTS idx_chapters_video ON video_chapters(video_id, start_second);


-- ─────────────────────────────────────────────────────────────────────────────
-- updated_at trigger for comments
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TRIGGER set_updated_at_comments
  BEFORE UPDATE ON video_comments
  FOR EACH ROW EXECUTE FUNCTION trigger_set_updated_at();
