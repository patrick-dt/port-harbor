# App assets

| Path | Purpose |
|------|---------|
| `AppIcon.png` | Master app icon (square, ideally 1024×1024). `scripts/package-app.sh` converts it to `AppIcon.icns` for Finder / Spotlight. |
| `Sources/PortHarbor/Resources/FrameworkIcons/framework-*.svg` | Runtime vector marks for Astro and Next.js (loaded as `NSImage`). |
| `Sources/PortHarbor/Resources/FrameworkIcons/framework-sanity.png` | Runtime Sanity mark (raster — no SVG provided). |

Replace `AppIcon.png` with your own art, then re-run `./scripts/package-app.sh`.

The menu bar still uses the SF Symbol `server.rack`.
