# Agent & Contributor Guide

Conventions for anyone working in this repo — humans and AI assistants (Cursor,
Copilot, Claude, etc.) alike. Keep this short and follow it.

## The golden rules

1. **Never hand-edit `EncoreMoment.xcodeproj`.** It is generated from `project.yml`
   by [XcodeGen](https://github.com/yonaskolb/XcodeGen). To add/remove/rename
   source files, change the files on disk (XcodeGen globs `App/EncoreMoment`) and
   run `xcodegen generate`. Commit the regenerated `.xcodeproj`.
2. **Shared models live in `EncoreMomentCore` only.** `Creator`, `Event`,
   `MediaItem` are used by *both* the iOS app and the `Server`. Change them in one
   place; never duplicate them. They are plain `Codable`/`Sendable` DTOs — keep
   UIKit/SwiftUI/Vapor out of `Sources/EncoreMomentCore`.
3. **The app talks to data only through protocol abstractions.** `EventStore`
   (events/media), `FanPreferencesStore` (favorites/follows), `AnalyticsStore`
   (views/downloads), and `SocialStore` (comments/likes) each have in-memory +
   REST implementations. Don't call networking from views — add behavior to a
   store or to `AppModel`.
4. **Dates are ISO-8601 everywhere.** The app, `APIEventStore`, and the server all
   use `.iso8601` JSON coding. Don't change one side without the others.

## Project layout

| Path | What | Builds where |
| --- | --- | --- |
| `Sources/EncoreMomentCore/` | Shared models, `EventStore` + stores, auth client | Linux/CI + Apple |
| `Tests/EncoreMomentCoreTests/` | XCTest for the core | Linux/CI |
| `App/EncoreMoment/` | SwiftUI app + `AppModel` + services | Xcode (macOS) only |
| `Server/` | Vapor + Fluent + SQLite backend | Linux/CI + Apple |

## How to verify changes

```bash
swift build && swift test          # core (always run this)
cd Server && swift build           # server
xcodegen generate                  # after any App/ file change
```

The iOS app target needs Apple's SDK and is **not** built in CI — verify it by
building the `EncoreMoment` scheme in Xcode on a Mac. CI (`.github/workflows/ci.yml`)
builds + tests the core and builds the server on Linux.

## Backends

`AppModel.makeDefaultStore()` returns the production store:

```swift
APIEventStore(baseURL: AppConfig.apiBaseURL,
              transport: AuthenticatedTransport { TokenHolder.shared.token })
```

The same pattern backs the other concerns: `AnalyticsStore` (`InMemory` +
`APIAnalyticsStore`) and `SocialStore` (`InMemory` + `APISocialStore`). Recording
views/downloads is anonymous; reading analytics is creator-only. Likes/comments
read publicly but require a token to write. `AppModel` swaps the
`FanPreferencesStore` between `FileFanPreferencesStore` (anonymous) and
`APIFanPreferencesStore` (signed in) on sign-in/out.

Swap stores for tests/previews by injecting `AppModel(store:…)`. `AppConfig.apiBaseURL`
honors the `EM_API_BASE_URL` env var so you can point at a local server.

## Auth model

- There is one account type. `POST /auth/register` creates an account with a
  `Creator` profile; `POST /auth/login` returns `{ token, creator? }`. `creator`
  is optional only for older accounts that do not have a profile.
- The JWT carries the user id (`sub`) and an optional `creatorId` for the owned
  profile. Auth responses also include the `userId`/`id` so the app can attribute
  comments and decide who may delete them (author or the event's owning creator).
- Read routes are public; event/creator write routes require a **creator** token and
  enforce ownership (server derives the creator from the token, not the body).
- Fan favorites/follows sync per-account via `/me/preferences` + `/me/favorites/{id}`
  + `/me/follows/{id}` (any authenticated user). The app uses `APIFanPreferencesStore`
  when signed in and the on-device `FileFanPreferencesStore` when anonymous.

## Style

- Match the surrounding code. Terse; comments only where intent isn't obvious.
- Keep `Sources/EncoreMomentCore` free of platform frameworks.
- Prefer small, focused changes. Add/keep tests for core logic.
- Don't commit secrets. `JWT_SECRET` and tokens come from the environment / Keychain.
