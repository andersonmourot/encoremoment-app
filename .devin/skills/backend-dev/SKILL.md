---
name: backend-dev
description: Build and run the EncoreMoment Vapor backend locally on port 8080 (Server/ directory, Swift package). Use when running or testing the API locally.
---

# Local backend (Vapor + Fluent + SQLite)

The backend lives in `Server/` as its own Swift package depending on the root
`EncoreMomentCore` package via a path dependency.

## Build & run

```sh
cd Server
swift build          # cold build is SLOW (~1 hr CPU on this machine — Vapor tree)
                     # incremental builds are fine
swift run EncoreMomentServer serve --hostname 0.0.0.0 --port 8080
```

Or run the built binary directly:

```sh
./.build/debug/EncoreMomentServer serve --hostname 0.0.0.0 --port 8080
```

Verify: `curl http://localhost:8080/health` → `{"status":"ok"}`

## Environment variables (all optional locally)

| Var | Default | Notes |
| --- | --- | --- |
| `JWT_SECRET` | `dev-secret-change-me-in-production` | Set a real value in production only |
| `DATABASE_PATH` | `db.sqlite` (in CWD) | `/data/db.sqlite` on Fly via mounted volume |
| `UPLOADS_PATH` | `uploads/` next to the DB | Local media storage fallback |
| `R2_BUCKET` `R2_ENDPOINT` `R2_ACCESS_KEY_ID` `R2_SECRET_ACCESS_KEY` `R2_PUBLIC_BASE_URL` | unset | If unset, uploads go to the local dir |

On boot the server runs `autoMigrate()` then `seedIfEmpty()` — a fresh DB gets
seeded automatically.

## API surface

- `GET /` → "EncoreMoment API is up"; `GET /health` → `{"status":"ok"}`
- Auth: `POST /auth/register`, `POST /auth/login` → `{ token, creator? }`;
  bearer JWT required on write routes (ownership derived from token).
- Read routes are public; favorites/follows sync via `/me/preferences`,
  `/me/favorites/{id}`, `/me/follows/{id}`.
- **All JSON dates are ISO-8601** — must stay in sync with the app's stores.
- Full REST reference: `CONTRIBUTING.md`.

## Point the iOS app at it

```sh
SIMCTL_CHILD_EM_API_BASE_URL=http://localhost:8080 \
  xcrun simctl launch booted com.encoremoment.app
```

or set `EM_API_BASE_URL=http://localhost:8080` in the Xcode scheme's Run
arguments. Without it the app talks to the live backend.

## Production

- Fly app `inthemoment-api` (`fly.toml`), volume `inthemoment_data`,
  live at `https://inthemoment-api.fly.dev`. These names intentionally still
  say "inthemoment" — renaming would orphan the deployed app/data.
- Dockerfile builds the `EncoreMomentServer` product.
- Deploy: `flyctl deploy --remote-only --app inthemoment-api`
  (requires `flyctl` auth; secrets via `flyctl secrets set`).
