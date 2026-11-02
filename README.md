# Ensign

A ship's ensign is the flag that shows which nation it sails under. Ensign does the same for your Mac: it sits in the menu bar and shows the public IP — and, if you like, the country flag — the internet currently sees you as.

It re-checks on every network change (Wi-Fi switch, VPN or WARP on/off), on wake, and every 15 minutes, and shows `offline` when there's no network.

## Build & run

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

`make` lists the targets. Each one is a thin wrapper over `scripts/*.sh`.

| Target | What it does |
|---|---|
| `make install` | Release build → replaces `/Applications/Ensign.app` → launches it. **Use this after changes.** |
| `make run` | Debug build, launched from `build/`. For development only. |
| `make test` | EnsignKit unit tests (`swift test`, no Xcode project needed). |
| `make release` | Release build plus signature/entitlement checks (fails on `get-task-allow` or a missing sandbox). |
| `make share` | Release build zipped to `~/Downloads/Ensign-<git describe>.zip`. |
| `make clean` | Removes the generated project and all build output. |

Turn on **Launch at login** from the installed copy, not from `make run`. macOS registers the login item at the path the app runs from, and `build/` disappears on `make clean`. `make install` replaces the app at the same path, so the registration survives updates.

The build is signed ad-hoc, so someone you share the zip with will see Gatekeeper refuse it the first time. They need to open it once via System Settings → Privacy & Security → **Open Anyway**.

`Ensign.xcodeproj`, `App/Info.plist` and `App/Ensign.entitlements` are generated from `project.yml`; edit that file, not the generated ones.

Logs: `/usr/bin/log stream --level info --predicate 'subsystem == "com.nilcolor.Ensign"'`

## Layout

- `App/`: SwiftUI shell (MenuBarExtra, Settings, notifications). Kept thin.
- `Packages/EnsignKit/`: everything testable:
  - `Providers.swift`: IP services and their response parsers.
  - `IPResolver.swift`: walks a provider chain until one returns a valid address of the requested family.
  - `GeoEnricher.swift`: fills in city/ISP/hostname for an IP, cached per IP.
  - `NetworkMonitor.swift`: `NWPathMonitor` as an `AsyncStream`, with VPN detection.
  - `IPMonitor.swift`: the state machine: when to check, retry backoff, IP-change callback.
  - `DisplayFormat.swift`: menu bar formats and flag emoji.

## How lookups work

1. **Discovery**: the IPv4 and IPv6 chains run in parallel. The first provider that answers with a valid address of the right family wins; an IPv6 answer from a "v4" provider is rejected and the next one is tried. The menu bar only ever shows IPv4.
2. **Enrichment**: if discovery didn't return city/ISP, `ifconfig.co` then `ipinfo.io` are asked about that specific IP. This runs once per new IP, so the rate-limited services see very little traffic.

Failed checks retry after 5s, 15s, 60s, then fall back to the 15-minute schedule; the last known IP stays visible with ⚠︎.

## App Store notes

- The app is sandboxed with only `network.client`. Signing is ad-hoc (`CODE_SIGN_IDENTITY: "-"` in `project.yml`); set a `DEVELOPMENT_TEAM` and automatic signing before archiving.
- Cloudflare's `/cdn-cgi/trace` is a debug endpoint, not a documented API. Move it out of the default chain before submitting.

## License

MIT, see [LICENSE](LICENSE).
