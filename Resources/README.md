# App assets

| File | Purpose |
|------|---------|
| `AppIcon.png` | Master app icon (square, ideally 1024×1024). `scripts/package-app.sh` converts it to `AppIcon.icns` for Finder / Spotlight. |

Replace `AppIcon.png` with your own art, then re-run `./scripts/package-app.sh`.

The menu bar still uses the SF Symbol `server.rack` (template icons for the status item can be added later).
