# Contributing / Developer Guide

A practical guide to building, testing, and deploying EncoreMoment. For the short
list of conventions (especially for AI assistants like Cursor), see [AGENTS.md](AGENTS.md).

## Prerequisites

| To work on… | You need |
| --- | --- |
| Core library & tests | Swift 6.0.3 |
| Vapor server | Swift 6.0.3 |
| iOS app | macOS + Xcode 15+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) |
| Deployment | [flyctl](https://fly.io/docs/flyctl/) + a Fly.io account |

```bash
brew install xcodegen flyctl    # macOS
```

## Repository layout

See the tree in the [README](README.md#architecture). The key idea: `Creator`,
`Event`, and `MediaItem` are defined once in `Sources/EncoreMomentCore` and reused
by both the app and the server, so the client/server JSON contract can't drift.

## Day-to-day commands

```bash
# Core (runs anywhere, including Linux/CI)
swift build
swift test

# Server
cd Server
swift build
JWT_SECRET=dev DATABASE_PATH=/tmp/itm.sqlite \
  swift run EncoreMomentServer serve --hostname 127.0.0.1 --port 8080

# iOS app (macOS)
xcodegen generate          # ALWAYS run after adding/removing/renaming files
open EncoreMoment.xcodeproj # run the "EncoreMoment" scheme on a simulator
```

> **Never hand-edit `EncoreMoment.xcodeproj`** — it is generated from `project.yml`.
> Edit files on disk + `project.yml`, then `xcodegen generate`.

## Pointing the app at a local server

`AppConfig.apiBaseURL` reads the `EM_API_BASE_URL` env var (see `.env.example`).
Set it in the Xcode scheme's environment variables to use a local server instead
of the live one.

## REST API reference

Base URL: `https://inthemoment-api.fly.dev`. All bodies/responses are JSON with
ISO-8601 dates. The contract mirrors `APIEventStore`.

### Auth

There is one account type. Each new account has a `Creator` profile for posting
events, and that same account also saves favorites/follows, likes, and comments.
`creator` is optional in responses only so older accounts without a profile can
continue to decode.

| Method | Path | Body | Returns |
| --- | --- | --- | --- |
| `POST` | `/auth/register` | `{ email, password, displayName, handle }` | `{ token, userId, creator }` |
| `POST` | `/auth/login` | `{ email, password }` | `{ token, userId, creator? }` |
| `GET` | `/auth/me` | — (Bearer token) | `{ id, email, creator? }` |
| `POST` | `/auth/profile` | `{ displayName, handle }` (Bearer token) | `{ token, userId, creator }` |
| `POST` | `/auth/avatar` | multipart `{ file }` (Bearer token) | `Creator` with updated `avatarURL` |
| `DELETE` | `/auth/account` | — (Bearer token) | `204`; deletes the user, creator profile, owned events/media, social rows, fan preferences, and uploaded files |

### Fan preferences (favorites & follows)

Per-account, so they sync across devices. All require `Authorization: Bearer <token>`
and act on the token's user. Each mutating call returns the updated `FanPreferences`
(`{ favoriteEventIDs: [uuid], followedCreatorIDs: [uuid] }`).

| Method | Path | Notes |
| --- | --- | --- |
| `GET` | `/me/preferences` | current favorites + follows + blocked creators |
| `PUT` | `/me/preferences` | union-merge a `FanPreferences` body (used on first sign-in) |
| `POST` · `DELETE` | `/me/favorites/{eventId}` | add / remove a favorite |
| `POST` · `DELETE` | `/me/follows/{creatorId}` | follow / unfollow |
| `GET` | `/me/blocks` | profiles of creators you've blocked |
| `POST` · `DELETE` | `/me/blocks/{creatorId}` | block / unblock a creator. Blocking also unfollows, drops favorites on their events, hides their content in your feeds, and files a moderation report |

Blocking (App Store 1.2): for signed-in users, `/creators`, `/events`, event
media, and `/events/{id}/comments` are filtered server-side against the
caller's blocks (public reads accept an optional token for this). The app also
filters client-side so blocked content disappears instantly and for anonymous
viewers.

### Events & media

Reads are public. Writes require `Authorization: Bearer <token>` and you may only
modify events owned by your creator.

| Method | Path | Auth | Notes |
| --- | --- | --- | --- |
| `GET` | `/events?published=true&creator={uuid}` | public | filters optional |
| `GET` | `/events/{id}` | public | 404 if missing |
| `POST` | `/events` | required | attributed to your creator |
| `PUT` | `/events/{id}` | required (owner) | replaces media set |
| `DELETE` | `/events/{id}` | required (owner) | |
| `POST` | `/events/{id}/uploads` | required (owner, collaborator, or community if enabled) | multipart `{ kind, file, thumbnail? }` upload; creates a `MediaItem` |
| `POST` | `/events/{id}/media` | required (owner, collaborator, or community if enabled) | add one `MediaItem` |
| `DELETE` | `/events/{id}/media/{mediaId}` | required (owner or uploader) | |
| `GET` | `/uploads/{filename}` | public | uploaded media bytes |
| `GET` | `/creators` · `/creators/{id}` | public | |
| `PUT` | `/creators/{id}` | required (self) | |
| `GET` | `/health` | public | `{ "status": "ok" }` |

**Invite-only events & members.** An `Event` with `inviteOnly: true` is visible
only to its owner and invited members — `/events` omits it for everyone else and
`/events/{id}` (plus comments/likes under it) returns `403`. Upload permission:
owner, invited `collaborator`, or anyone signed in when
`allowsCommunityUploads` is on. `viewer`s cannot upload. Media uploaded by the
owner or a collaborator is marked `isOfficial: true` server-side; everything
else is community content.

| Method | Path | Auth | Returns / notes |
| --- | --- | --- | --- |
| `GET` | `/events/{id}/members` | required (owner) | `[EventMember]` |
| `GET` | `/events/{id}/membership` | required | `{ member: EventMember? }` — the caller's own role |
| `POST` | `/events/{id}/members` | required (owner) | `{ handle, role }` → updated `[EventMember]`; also notifies the invitee |
| `DELETE` | `/events/{id}/members/{creatorId}` | required (owner or self) | updated `[EventMember]` |

`EventMember` = `{ id, eventID, creatorID, role: "viewer"|"collaborator", displayName, handle }`.

### Comments & likes

Reads are public. Likes optionally read the token to report `likedByViewer`
(`false` for anonymous callers). Writes require `Authorization: Bearer <token>`.
Comments may be deleted by their **author** or the **event's owning creator**.

| Method | Path | Auth | Returns / notes |
| --- | --- | --- | --- |
| `GET` | `/events/{id}/comments` | public | `[Comment]`, oldest first |
| `POST` | `/events/{id}/comments` | required | `{ body }` → the created `Comment` (1–2000 chars) |
| `DELETE` | `/events/{id}/comments/{commentId}` | required (author/owner) | `204` |
| `GET` | `/events/{id}/likes` | optional | `LikeSummary` `{ eventID, count, likedByViewer }` |
| `POST` | `/events/{id}/like` | required | like (idempotent) → updated `LikeSummary` |
| `DELETE` | `/events/{id}/like` | required | unlike → updated `LikeSummary` |

`Comment` = `{ id, eventID, authorID, authorName, body, createdAt }`. `authorName`
is denormalized at write time (creator display name, else the fan's email local-part).

### Analytics

Recording is **public** (any viewer contributes); reading is **creator-only**.

| Method | Path | Auth | Returns / notes |
| --- | --- | --- | --- |
| `POST` | `/events/{id}/view` | public | `204` — increments view count |
| `POST` | `/events/{id}/download?count=N` | public | `204` — increments downloads by `N` (default 1) |
| `GET` | `/events/{id}/stats` | required (owner) | `EventStats` `{ eventID, views, downloads }` |
| `GET` | `/me/stats` | required (creator) | `[EventStats]` for all of the creator's events |

Recording for an unknown event returns `404` (not a 500).

Errors use Vapor's envelope: `{ "error": true, "reason": "…" }`.

## Deployment (Fly.io)

The server is containerized (`Dockerfile`, multi-stage, static Swift stdlib) and
configured by `fly.toml` (app `inthemoment-api`, region `iad`, 1 GB volume mounted
at `/data`). Uploaded media uses Cloudflare R2 when `R2_BUCKET`, `R2_ENDPOINT`,
`R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, and `R2_PUBLIC_BASE_URL` are present.
Without R2 secrets, uploads fall back to a sibling `uploads` directory next to
`DATABASE_PATH` (for Fly, `/data/uploads`). Override fallback storage with
`UPLOADS_PATH`; set `PUBLIC_BASE_URL` if fallback URLs need a fixed public base.

```bash
flyctl secrets set JWT_SECRET=$(openssl rand -hex 32) --app inthemoment-api
flyctl deploy --remote-only --app inthemoment-api
flyctl logs --app inthemoment-api
```

> A `error releasing builder: deadline_exceeded` message at the end of a deploy is
> a known non-fatal Fly warning — the image still pushes and the machine updates.

## CI

`.github/workflows/ci.yml` runs on every push/PR:

- **core-linux** — `swift build` + `swift test` for `EncoreMomentCore`.
- **server-linux** — `swift build` for the `Server` package.

The iOS app is not built in CI (needs Apple's SDK); verify it in Xcode.

## Testing notes

- Core logic and the network/auth clients are unit-tested with a mock
  `HTTPTransport` (no real network). Add tests alongside new core behavior.
- Keep `Sources/EncoreMomentCore` free of platform frameworks so it keeps building
  on Linux/CI.
