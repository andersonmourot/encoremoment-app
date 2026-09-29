# Roadmap

Status of EncoreMoment and the work still to do. This is the handoff checklist —
start here when picking the project up in Cursor (read [AGENTS.md](AGENTS.md) and
[`.cursor/rules/encoremoment.mdc`](.cursor/rules/encoremoment.mdc) first for the
conventions, and [CONTRIBUTING.md](CONTRIBUTING.md) for build/deploy/REST details).

- **Live API:** https://inthemoment-api.fly.dev
- **Repo:** https://github.com/andersonmourot/encoremoment-app

## Shipped

| Area | What | Where |
| --- | --- | --- |
| Scaffold | SwiftUI app + `EncoreMomentCore` package + Xcode project (XcodeGen) | app + core |
| Persistence | `FileEventStore` (on-device JSON), edit + publish/draft, share/deep links | core + app |
| REST client | `APIEventStore` over an injectable `HTTPTransport` | core |
| Backend | Vapor + Fluent + SQLite, full event/media CRUD, deployed to Fly.io | `Server/` |
| Account auth | JWT + bcrypt, Keychain token, profile-owned writes | core + app + server |
| Fan features | Favorites, follow creators, download-all, Saved tab, All/Following filter | core + app |
| Unified accounts | One sign-up flow with a profile plus server-synced favorites/follows | core + app + server |
| UI polish | `AsyncContentView` loading/error/empty states, shimmer, global action alert | app |
| Analytics | Per-event view/download counts; `AnalyticsStore` + creator-only read endpoints | core + app + server |
| Comments & likes | `SocialStore`, comment threads + like button, author/owner delete | core + app + server |
| Media uploads | Creator photo/video uploads to server storage, public `/uploads/{file}` URLs | app + server |

## Known constraints / debt

- **Media uploads use server-local storage.** This works for the MVP/Fly volume,
  but should move to S3/R2 or another object store before serious scale.
- **iOS UI is unverified in CI.** The app target needs Apple's SDK; CI only builds
  + tests the core and builds the server. Verify the app by running the
  `EncoreMoment` scheme in Xcode on a Mac.
- **No pagination.** `/events` and comment lists return everything; fine for now,
  will need cursors as data grows.
- **Auth is access-token only.** No refresh tokens, password reset, or email
  verification. `JWT_SECRET` is a single env var on Fly.
- **SQLite + single Fly machine.** One region (`iad`), one volume. No backups
  configured. Consider Postgres + a backup strategy before scaling.
- **No rate limiting / spam controls** on comments, likes, or auth.
- **Comment `authorName` is denormalized** at write time, so it won't update if a
  user later changes their display name (acceptable for MVP).

## Next up (suggested order)

1. **Move media uploads to cloud object storage** — replace server-local uploads
   with S3/R2 + presigned URLs, CDN-friendly public URLs, and lifecycle/backups.
2. **Fan feed** — a chronological feed of new media from followed creators (the
   Discover "Following" filter is the seed; add a dedicated, time-ordered feed).
3. **Push / email notifications** — notify creators of comments/likes and fans of
   new posts from followed creators (APNs + an email provider).
4. **Creator profile pages & discovery** — browse/search creators, not just events.
5. **Moderation tools** — report comments, creator can hide/remove, basic blocklist.
6. **Analytics dashboard** — charts/trends over time (today it's raw counts only).

## Pre-handoff checklist for Cursor

- [ ] `swift build && swift test` passes (core, on Linux or macOS).
- [ ] `cd Server && swift build` passes.
- [ ] `xcodegen generate` then build the `EncoreMoment` scheme in Xcode on a Mac.
- [ ] Copy `.env.example` → set `EM_API_BASE_URL` (app) / `JWT_SECRET` +
      `DATABASE_PATH` (server) as needed.
- [ ] Confirm Fly access (`flyctl auth login`) if you'll deploy the backend.
