# Port Harbor

A lightweight macOS menu bar app that shows local dev servers reachable as `localhost` (IPv4/IPv6 loopback and wildcard binds) and lets you open, restart, or stop them with one click.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange)

## Features

- **Auto-discovery** — scans localhost-reachable TCP listeners via `lsof` every 3 seconds
- **Framework detection** — recognizes Next.js, Vite, Nuxt, Django, Rails, Flask, and 15+ more
- **Quick actions** — open in browser, Cursor, Terminal; restart or stop any server
- **Undo for Stop** — a stopped server stays listed for 5 seconds with an Undo that reruns its command
- **Ignore list** — hide apps that merely hold a local port (Raycast, Spotify, …); persisted in `UserDefaults`
- **Keyboard** — `⌘1`–`⌘9` open the first nine servers, `⌘R` rescans, `⌘Q` quits
- **Zero config** — no setup, no background daemon, just a menu bar icon

## Build & Run

```bash
swift build
swift run PortHarbor
# or open in Xcode:
open Package.swift
```

### Install / update the Mac app

```bash
./scripts/package-app.sh
```

That builds a release `.app` and installs it to `/Applications/Port Harbor.app` (menu bar only, no Dock icon). Run the same command again after code changes to replace the installed app — it quits a running copy first, then overwrites `/Applications`.

**App icon:** put a square PNG at `Resources/AppIcon.png` (1024×1024 preferred). The package script turns it into `AppIcon.icns` and embeds it. Swap the file and re-run the script to change the Finder/Spotlight icon. The menu bar still uses SF Symbol `server.rack`.

`swift test` needs a full Xcode install; the Command Line Tools alone don't ship `XCTest`.

## Security Notes

Port Harbor runs **entirely locally** with no network communication. It uses only hardcoded system paths (`/usr/sbin/lsof`, `/bin/ps`, `/bin/kill`) to avoid PATH injection.

### Restart behaviour

The **Restart** action re-launches the original command line reported by `ps`. Before execution:

- The command is split into arguments and executed directly via `Process` (no shell involved), eliminating shell injection.
- Commands from unknown binaries are rejected if they contain shell metacharacters (`;|&$\`!{}<>`). Known shells and allowlisted dev binaries may carry those characters (e.g. `sh -c …`).
- Validation runs **before** the process is signalled, so a command that can't be relaunched is never turned into a silent stop. Restart is disabled outright for such processes.
- An inline confirmation is always shown before restarting.
- Failure “Copy command” strings are paste-safe (POSIX single-quoted argv), not raw `ps` text.

### Stop behaviour

**Stop** sends `SIGTERM`, waits ~700 ms, and escalates to `SIGKILL` only if the process is still alive. When the listener is its process-group leader, the group is signalled too so wrapper trees (npm/yarn) tear down cleanly.

- Before signalling, Port Harbor re-checks that the PID still matches the expected command, reducing the chance of stopping a recycled PID.
- Recognized dev servers stop with a single click. Anything we can't identify as one — an app bundle holding a port, no working directory, an unknown binary — asks for inline confirmation first.
- The row stays visible for 5 seconds afterwards with an **Undo** that reruns the original command.
- Failures are never swallowed: the reason is shown on the row, with a paste-safe shell command to copy.

### Permissions

The app requires no special entitlements. It uses:

- `lsof` / `ps` / `kill` for process inspection (read-only except stop/restart)
- `NSAppleScript` to open Terminal.app (path is validated as an existing directory before use)

## License

MIT
