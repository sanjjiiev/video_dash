-- ===========================================================================
-- 002_phase4.sql — Phase 4: Chapters, Subscriptions, Analytics, Push tokens
-- ===========================================================================

-- ── Required extensions ───────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ── Subscription plans ────────────────────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE subscription_plan AS ENUM ('free', 'pro', 'premium');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS subscription_plan  subscription_plan NOT NULL DEFAULT 'free',
  ADD COLUMN IF NOT EXISTS subscription_expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS channel_name       VARCHAR(100),
  ADD COLUMN IF NOT EXISTS channel_description TEXT,
  ADD COLUMN IF NOT EXISTS avatar_url         TEXT,
  ADD COLUMN IF NOT EXISTS subscriber_count   INT NOT NULL DEFAULT 0;

-- ── Video chapters ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS video_chapters (
  id             UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
  video_id       UUID         NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
  title          VARCHAR(200) NOT NULL,
  start_seconds  FLOAT        NOT NULL,
  position       INT          NOT NULL,
  created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  UNIQUE(video_id, position),
  UNIQUE(video_id, start_seconds)
);
CREATE INDEX IF NOT EXISTS idx_chapters_video ON video_chapters(video_id, position);

-- ── Channel subscriptions (user follows channel) ──────────────────────────
CREATE TABLE IF NOT EXISTS channel_subscriptions (
  id             UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
  subscriber_id  UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  channel_id     UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  notify_new     BOOLEAN      NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  UNIQUE(subscriber_id, channel_id),
  CHECK(subscriber_id != channel_id)
);
CREATE INDEX IF NOT EXISTS idx_subs_subscriber ON channel_subscriptions(subscriber_id);
CREATE INDEX IF NOT EXISTS idx_subs_channel    ON channel_subscriptions(channel_id);

-- Trigger: keep subscriber_count in sync
CREATE OR REPLACE FUNCTION update_subscriber_count() RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE users SET subscriber_count = subscriber_count + 1 WHERE id = NEW.channel_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE users SET subscriber_count = GREATEST(0, subscriber_count - 1) WHERE id = OLD.channel_id;
  END IF;
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_subscriber_count ON channel_subscriptions;
CREATE TRIGGER trg_subscriber_count
  AFTER INSERT OR DELETE ON channel_subscriptions
  FOR EACH ROW EXECUTE FUNCTION update_subscriber_count();

-- ── Push notification tokens ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS push_tokens (
  id          UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token       TEXT         NOT NULL,
  platform    VARCHAR(20)  NOT NULL CHECK(platform IN ('ios','android','web')),
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  UNIQUE(user_id, token)
);
CREATE INDEX IF NOT EXISTS idx_push_user ON push_tokens(user_id);

-- ── Notification log ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS notifications (
  id          UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type        VARCHAR(50)  NOT NULL,   -- 'new_video','like','comment','subscribe'
  title       TEXT         NOT NULL,
  body        TEXT,
  payload     JSONB,
  read        BOOLEAN      NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_notif_user ON notifications(user_id, read, created_at DESC);

-- ── Daily analytics aggregates ────────────────────────────────────────────
-- Populated by the API's watch-event endpoint via an upsert
CREATE TABLE IF NOT EXISTS video_analytics (
  video_id        UUID   NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
  date            DATE   NOT NULL DEFAULT CURRENT_DATE,
  views           INT    NOT NULL DEFAULT 0,
  unique_viewers  INT    NOT NULL DEFAULT 0,
  watch_seconds   BIGINT NOT NULL DEFAULT 0,
  likes           INT    NOT NULL DEFAULT 0,
  dislikes        INT    NOT NULL DEFAULT 0,
  comments        INT    NOT NULL DEFAULT 0,
  shares          INT    NOT NULL DEFAULT 0,
  PRIMARY KEY(video_id, date)
);
CREATE INDEX IF NOT EXISTS idx_analytics_video_date ON video_analytics(video_id, date DESC);

-- ── Video likes / dislikes (deduplicated) ─────────────────────────────────
CREATE TABLE IF NOT EXISTS video_reactions (
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  video_id   UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
  reaction   VARCHAR(10) NOT NULL CHECK(reaction IN ('like','dislike')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY(user_id, video_id)
);

-- ── Comment likes ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS comment_likes (
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  comment_id UUID NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY(user_id, comment_id)
);

-- ── Playlists ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS playlists (
  id          UUID         PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_id    UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title       VARCHAR(200) NOT NULL,
  description TEXT,
  visibility  VARCHAR(20)  NOT NULL DEFAULT 'private' CHECK(visibility IN ('public','unlisted','private')),
  created_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS playlist_items (
  playlist_id UUID NOT NULL REFERENCES playlists(id)  ON DELETE CASCADE,
  video_id    UUID NOT NULL REFERENCES videos(id)     ON DELETE CASCADE,
  position    INT  NOT NULL,
  added_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY(playlist_id, video_id)
);

-- ── Watch Later (special built-in playlist per user) ─────────────────────
CREATE TABLE IF NOT EXISTS watch_later (
  user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  video_id   UUID NOT NULL REFERENCES videos(id) ON DELETE CASCADE,
  added_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY(user_id, video_id)
);

-- ── Chapters seed for easy testing ───────────────────────────────────────
-- (populated via the chapters API in production)
