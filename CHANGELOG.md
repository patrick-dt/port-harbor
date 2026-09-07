# Changelog

All notable changes to Port Harbor are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Security

- Quote working-directory paths in failure “Copy command” recovery strings so pasting into a shell cannot interpret metacharacters.
- Copy restart/undo recovery commands as paste-safe argv (each argument single-quoted) instead of raw `ps` text.
- Tighten relaunch metacharacter policy: absolute `/usr`/`/bin`/`/opt/homebrew` prefixes alone no longer skip the filter; only known dev binaries and shells may carry metacharacters.
- Re-verify process identity (`ps` command key) before Stop/Restart to reduce PID-reuse TOCTOU during the list freeze window.

### Fixed

- Open IPv4-only listeners at `http://127.0.0.1:<port>` instead of `localhost`, so a sibling bound to `::1` is not opened by mistake.
- IPv4-only rows show `127.0.0.1` next to the port so two processes sharing a port are distinguishable.
- Wrap `containerBackground(..., for: .window)` in `compiler(>=6.0)` so Xcode 15 SDKs still compile.
- CI `swift build` failed on `macos-14` because that image’s SDK has no `ContainerBackgroundPlacement.window`.
- Queue overlapping refreshes so ⌘R during an in-flight scan is no longer a silent no-op.
- Framework detection now uses path/token boundaries, avoiding false Next.js/Vite labels from folder names like `next-app`.
- Express is detected from an `express` token, not from a bare `node … server` command.
- Framework badges render the bundled Astro/Next.js SVGs and Sanity PNG instead of approximate SwiftUI paths.

### Changed

- Stop waits ~0.7s after SIGTERM and, when the listener is its process-group leader, also signals the group before escalating to SIGKILL.
- `package-app.sh` sets `CFBundleShortVersionString` from the latest `v*` git tag (override with `PORT_HARBOR_VERSION`).

### Added

- Colored framework badges: Astro and Next.js as SwiftUI vector marks (plus `.svg` sources); Sanity as bundled PNG; other frameworks keep monogram tiles.
- Sanity Studio detection (`sanity` / `@sanity` in the command line).
- GitHub Actions CI (`macos-15`, `actions/checkout@v5`) running `swift build` and `swift test`.
- Optional `scripts/release.sh` / Release workflow to build a universal DMG later (not advertised until notarized).
- Unit tests for shell quoting, pasteable commands, scan-freeze policy, and framework token matching.
