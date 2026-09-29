---
name: ios-build
description: Build, test, and run the EncoreMoment iOS app (EncoreMoment.xcodeproj, scheme EncoreMoment) in the iOS Simulator. Use for any iOS verification or simulator work.
---

# EncoreMoment iOS build & run

Xcode project is `EncoreMoment.xcodeproj` at the repo root, scheme `EncoreMoment`.

**Never hand-edit `EncoreMoment.xcodeproj`.** It is generated from `project.yml`
by XcodeGen. After adding/renaming files under `App/`, run:

```sh
xcodegen generate
```

and commit the regenerated project.

## Required: DEVELOPER_DIR

If `xcode-select -p` shows `/Library/Developer/CommandLineTools`, plain
`xcodebuild`/`simctl`/`swift test` will fail (no XCTest, no simulator). Either
fix it once with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
or prefix commands with:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

## Build (verified working)

```sh
xcodebuild -project EncoreMoment.xcodeproj -scheme EncoreMoment \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug build
```

Build products land in `~/Library/Developer/Xcode/DerivedData/EncoreMoment-*/`.
Anything under `xcuserdata/` or `DerivedData/` is gitignored — never commit it.

## Core tests (no Xcode required)

```sh
swift build && swift test    # EncoreMomentCore — 61 XCTest cases
```

(`swift test` needs full Xcode for XCTest on macOS — see DEVELOPER_DIR above.
On Linux CI it works out of the box.)

## Server build & run

```sh
cd Server && swift build                      # cold Vapor build is slow (~1 hr CPU)
cd Server && swift run EncoreMomentServer serve --hostname 0.0.0.0 --port 8080
```

`JWT_SECRET` has a dev fallback in `configure.swift`; `DATABASE_PATH` defaults
to `db.sqlite`. Production binary name is `EncoreMomentServer` (see Dockerfile).

## Available simulators

`xcrun simctl list devices available` — iPhone 17 Pro, iPhone 17 Pro Max,
iPhone Air, iPhone 17, iPhone 16e, iPads (iOS 26.3 runtime installed).

## Run in the simulator

```sh
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null   # idempotent if already booted
open -a Simulator

APP=~/Library/Developer/Xcode/DerivedData/EncoreMoment-*/Build/Products/Debug-iphonesimulator/EncoreMoment.app
xcrun simctl install booted $APP
xcrun simctl launch booted com.encoremoment.app
```

## Point the app at the local server

Default API is the live backend `https://inthemoment-api.fly.dev`. To use the
local Vapor server instead, pass `EM_API_BASE_URL` when launching:

```sh
SIMCTL_CHILD_EM_API_BASE_URL=http://localhost:8080 \
  xcrun simctl launch booted com.encoremoment.app
```

(In Xcode UI instead: Product > Scheme > Edit Scheme > Run > Arguments >
Environment Variables.)

## Notes

- Bundle ID: `com.encoremoment.app`; deep-link scheme: `encoremoment://`.
- The app reads data through `AppModel` → store protocols (`EventStore`,
  `FanPreferencesStore`, `SocialStore`, `AnalyticsStore`). Views never do
  networking — see `AGENTS.md`.
- Project rules mirror `AGENTS.md` and `.cursor/rules/encoremoment.mdc`.
