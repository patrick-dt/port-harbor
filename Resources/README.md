# App assets

| Path | Purpose |
|------|---------|
| `AppIcon.png` | Master app icon (square, ideally 1024×1024). `scripts/package-app.sh` converts it to `AppIcon.icns` for Finder / Spotlight. |
| `Sources/PortHarbor/Resources/FrameworkIcons/framework-*.svg` | Vector sources for Astro / Next.js (runtime draws SwiftUI paths; SVGs are the editable source). |
| `Sources/PortHarbor/Resources/FrameworkIcons/framework-sanity.png` | Sanity mark (raster — no SVG provided). |

Replace `AppIcon.png` with your own art, then re-run `./scripts/package-app.sh`.

The menu bar still uses the SF Symbol `server.rack`.
