# HUB 2.0 — Production-Grade Streaming Platform

> **Hybrid video streaming platform** — works like YouTube/Netflix online and like VLC offline.  
> 100% free, open-source stack. Zero vendor lock-in.

---

## ✅ Platform Status

| Service    | Status  | URL (dev)                         |
|------------|---------|-----------------------------------|
| Nginx CDN  | ✅ Live  | http://localhost                  |
| API        | ✅ Live  | http://localhost/api/v1           |
| MinIO UI   | ✅ Live  | http://localhost:9001             |
| Postgres   | ✅ Live  | localhost:5432                    |
| Redis      | ✅ Live  | localhost:6379                    |

---

## Architecture

```
Flutter App  ──►  Nginx (80)  ──►  Express API (3000)
                      │                    │
                      │ HLS cache          ├── PostgreSQL
                      │ auth_request       ├── Redis (BullMQ)
                      └──► MinIO (9000)    └── MinIO
                                │
                          FFmpeg Worker
                      (AES-128 HLS transcode)
```

---

## Quick Start

### 1. clone + configure
```bash
git clone <repo>
cd video_dash
cp .env.example .env        # edit secrets
```

### 2. Generate secrets (copy into .env)
```powershell
# Windows PowerShell
-join ((48..57)+(65..90)+(97..122) | Get-Random -Count 64 | % {[char]$_})
```

### 3. Start all services
```bash
docker compose up -d --build
```

### 4. Apply Phase 4 schema (first run only if data volume exists)
```powershell
Get-Content db\migrations\003_schema_fixes.sql | docker exec -i hub_postgres psql -U hubuser -d hub
```

### 5. Run Flutter app
```bash
cd flutter_app
flutter pub get
flutter run
```

---

## API Reference

### Auth
| Method | Endpoint                | Auth | Description              |
|--------|-------------------------|------|--------------------------|
| POST   | /auth/register          | ❌   | Create account           |
| POST   | /auth/login             | ❌   | Get JWT + set cookie     |
| POST   | /auth/refresh           | 🍪   | Rotate access token      |
| POST   | /auth/logout            | ✅   | Invalidate tokens        |
| GET    | /auth/me                | ✅   | Current user profile     |

### Videos
| Method | Endpoint                       | Auth | Description              |
|--------|--------------------------------|------|--------------------------|
| GET    | /videos                        | ❌   | Feed (paginated)         |
| GET    | /videos/:id                    | ❌   | Video detail             |
| GET    | /videos/:id/stream             | ✅   | Signed HLS URL           |
| POST   | /videos/presign                | ✅   | Presign MinIO upload     |
| POST   | /videos/:id/confirm            | ✅   | Trigger transcode        |
| PATCH  | /videos/:id                    | ✅   | Update metadata          |
| DELETE | /videos/:id                    | ✅   | Soft delete              |

### Phase 4 — Chapters
| Method | Endpoint                           | Auth      | Description           |
|--------|------------------------------------|-----------|-----------------------|
| GET    | /videos/:id/chapters               | ❌        | List chapters         |
| POST   | /videos/:id/chapters               | ✅ Owner  | Add chapter           |
| PUT    | /videos/:id/chapters               | ✅ Owner  | Bulk replace          |
| DELETE | /videos/:id/chapters/:chapterId   | ✅ Owner  | Delete chapter        |

### Phase 4 — Comments
| Method | Endpoint                                   | Auth         | Description          |
|--------|--------------------------------------------|--------------|----------------------|
| GET    | /videos/:id/comments                       | ❌           | Paginated comments   |
| POST   | /videos/:id/comments                       | ✅           | Post comment/reply   |
| PATCH  | /videos/:id/comments/:cid                 | ✅ Owner/Mod | Edit / pin           |
| DELETE | /videos/:id/comments/:cid                 | ✅ Owner/Mod | Soft delete          |
| POST   | /videos/:id/comments/:cid/like            | ✅           | Like comment         |
| DELETE | /videos/:id/comments/:cid/like            | ✅           | Unlike comment       |

### Phase 4 — Subscriptions
| Method | Endpoint                      | Auth | Description                    |
|--------|-------------------------------|------|--------------------------------|
| GET    | /subscriptions                | ✅   | My subscribed channels         |
| GET    | /subscriptions/feed           | ✅   | Videos from subscriptions      |
| GET    | /subscriptions/status/:id     | ✅   | Check subscription             |
| POST   | /subscriptions/:channelId     | ✅   | Subscribe                      |
| DELETE | /subscriptions/:channelId     | ✅   | Unsubscribe                    |
| PATCH  | /subscriptions/:channelId     | ✅   | Toggle notifications           |

### Phase 4 — Analytics
| Method | Endpoint                     | Auth     | Description               |
|--------|------------------------------|----------|---------------------------|
| GET    | /analytics/overview          | ✅       | Creator dashboard totals  |
| GET    | /analytics/timeseries        | ✅       | Daily views (N days)      |
| GET    | /analytics/top-videos        | ✅       | Best performing videos    |
| GET    | /analytics/video/:id         | ✅ Owner | Per-video deep dive       |
| POST   | /analytics/record-watch      | ✅       | Upsert watch event        |
| GET    | /analytics/notifications     | ✅       | Notification inbox        |
| POST   | /analytics/push-token        | ✅       | Register FCM token        |

### Phase 4 — Playlists
| Method | Endpoint                            | Auth     | Description              |
|--------|-------------------------------------|----------|--------------------------|
| GET    | /playlists                          | ✅       | My playlists             |
| POST   | /playlists                          | ✅       | Create playlist          |
| GET    | /playlists/:id                      | ❌/✅    | Playlist + videos        |
| PATCH  | /playlists/:id                      | ✅ Owner | Update metadata          |
| DELETE | /playlists/:id                      | ✅ Owner | Delete playlist          |
| POST   | /playlists/:id/items                | ✅ Owner | Add video                |
| DELETE | /playlists/:id/items/:videoId       | ✅ Owner | Remove video             |
| PUT    | /playlists/:id/items/reorder        | ✅ Owner | Reorder videos           |
| GET    | /playlists/watch-later              | ✅       | Watch Later list         |
| POST   | /playlists/watch-later/:videoId     | ✅       | Add to Watch Later       |
| DELETE | /playlists/watch-later/:videoId     | ✅       | Remove from Watch Later  |

---

## Flutter Features

| Feature              | Package             | Location                                      |
|----------------------|---------------------|-----------------------------------------------|
| Video playback       | media_kit           | features/player/                              |
| State management     | flutter_riverpod    | core/providers/                               |
| Navigation           | go_router           | app.dart                                      |
| HTTP client          | dio + interceptors  | core/network/api_client.dart                  |
| Global mini player   | StateNotifier       | core/providers/player_provider.dart           |
| Chapter markers      | CustomPaint         | features/player/widgets/chapters_widget.dart  |
| Comments             | DraggableSheet      | features/player/widgets/comments_section.dart |
| Playlist picker      | BottomSheet         | shared/widgets/playlist_picker_sheet.dart     |
| Subscriptions        | Tabbed screen       | features/subscriptions/                       |
| Analytics dashboard  | CustomPaint charts  | features/analytics/                           |
| Offline downloads    | Dio + StateNotifier | features/downloads/                           |
| Notifications        | Polling → FCM       | core/services/notification_service.dart       |
| Subscription paywall | BottomSheet         | shared/widgets/subscription_gate.dart         |
| Shorts (TikTok)      | PageView + media_kit| features/shorts/                              |

---

## Security Model

| Concern            | Solution                                                      |
|--------------------|---------------------------------------------------------------|
| Authentication     | JWT (15-min access + 7-day refresh httpOnly cookie)           |
| Video access       | Nginx `auth_request` on every HLS chunk                       |
| Encryption         | AES-128 per-video keys in MinIO `encryption-keys` bucket      |
| RBAC               | viewer < creator < moderator < admin role hierarchy           |
| Subscription gate  | `requireSubscription('pro')` → HTTP 402 → Flutter paywall UI |
| Resource ownership | `requireOwnership(fn)` factory — admins bypass               |
| Rate limiting      | express-rate-limit (100 req/15 min per IP)                    |
| Container security | no-new-privileges, read-only rootfs (worker), non-root user   |

---

## Database Schema

```
users              — auth, roles, subscription plan, channel info
refresh_tokens     — httpOnly cookie rotation with hash storage
videos             — lifecycle (pending→processing→ready|failed)
video_renditions   — per-quality MinIO prefix references
video_chapters     — chapter markers with ordered positions
video_reactions    — deduplicated likes/dislikes
watch_events       — lightweight telemetry (hashed IPs)
video_analytics    — daily aggregate UPSERT (views, watch_seconds, likes)
comments           — threaded with soft-delete + like_count
comment_likes      — deduplicated per (user, comment)
channel_subscriptions — subscribe with notify_new toggle + auto subscriber_count trigger
playlists          — user-owned with visibility (public/unlisted/private)
playlist_items     — ordered video references
watch_later        — dedicated system playlist per user
push_tokens        — FCM/APNs token registration
notifications      — inbox log with actionUrl + read state
```

---

## Phase Roadmap

- [x] **Phase 1** — Infrastructure (Docker, Nginx, PostgreSQL, Redis, MinIO)
- [x] **Phase 2** — Core API (auth, videos, HLS stream, AES-128 encryption, BullMQ worker)
- [x] **Phase 3** — Flutter app (player, home, shorts, search, upload, profile, auth)
- [x] **Phase 4** — Advanced features (chapters, comments, subscriptions, analytics, playlists, notifications, mini player, offline downloads)
- [ ] **Phase 5** — Production (Stripe/RevenueCat subscriptions, FCM push, CDN TLS, Kubernetes)

---

## Project Structure

```
video_dash/
├── api/src/
│   ├── routes/          auth, videos, stream, keys, chapters, comments,
│   │                    subscriptions, analytics, playlists
│   ├── middleware/       auth, rbac (requireRole/requireSubscription/requireOwnership),
│   │                    rateLimiter, errorHandler, upload
│   └── services/        queueService, minioService
├── worker/src/          FFmpeg AES-128 HLS transcoding worker
├── db/migrations/       001_init, 002_phase4, 003_schema_fixes
├── nginx/               nginx.conf + hub.conf (HLS cache + auth_request)
└── flutter_app/lib/
    ├── core/            theme, colors, providers, network, models, services
    ├── features/        home, player, shorts, search, upload, profile,
    │                    auth, downloads, analytics, subscriptions
    └── shared/          MainShell, MiniPlayer, NotificationBell,
                         SubscriptionGate, PlaylistPickerSheet
```
