# Port Harbor

A lightweight macOS menu bar app that shows all local dev servers running on `127.0.0.1` and lets you open, restart, or stop them with one click.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange)

## Features

- **Auto-discovery** — scans localhost TCP listeners via `lsof` every 3 seconds
- **Framework detection** — recognizes Next.js, Vite, Nuxt, Django, Rails, Flask, and 15+ more
- **Quick actions** — open in browser, Cursor, Terminal; restart or stop any server
- **Zero config** — no setup, no background daemon, just a menu bar icon

## Build & Run

```bash
swift build
swift run PortHarbor
# or open in Xcode:
open Package.swift
```

## Security Notes

Port Harbor runs **entirely locally** with no network communication. It uses only hardcoded system paths (`/usr/sbin/lsof`, `/bin/ps`, `/bin/kill`) to avoid PATH injection.

### Restart behaviour

The **Restart** action re-launches the original command line reported by `ps`. Before execution:

- The command is split into arguments and executed directly via `Process` (no shell involved), eliminating shell injection.
- Commands from unknown binaries are rejected if they contain shell metacharacters (`;|&$\`!{}<>`).
- A confirmation dialog is always shown before restarting.

### Permissions

The app requires no special entitlements. It uses:

- `lsof` / `ps` / `kill` for process inspection (read-only except stop/restart)
- `NSAppleScript` to open Terminal.app (path is validated as an existing directory before use)

## License

MIT
