# Releasing

Port Harbor ships the way [OpenUsage](https://github.com/robinebers/openusage) does: a public GitHub repo as the storefront, a DMG on [GitHub Releases](https://github.com/patrick-dt/port-harbor/releases), and (later) a Homebrew cask that points at that DMG.

## Cut a release

1. Move `[Unreleased]` in `CHANGELOG.md` into `## [X.Y.Z] - YYYY-MM-DD`.
2. Merge to `main`.
3. Tag and push:

```bash
git tag -a v0.1.0 -m "v0.1.0"
git push origin v0.1.0
```

Pushing a `v*` tag runs [`.github/workflows/release.yml`](../.github/workflows/release.yml), which builds a universal `.app`, wraps it in `PortHarbor-<version>.dmg`, and attaches that file to a GitHub Release.

A pre-release suffix (`v0.1.0-beta.1`) marks the GitHub Release as a prerelease.

## What people install

Until a Homebrew cask is accepted, the README points at **Direct download** of that DMG: open it, drag Port Harbor to Applications.

Local machine (this Mac only):

```bash
./scripts/package-app.sh
```

## Signing and notarization (Apple Developer Program)

Without a Developer ID, CI ad-hoc-signs the app. Gatekeeper then blocks the DMG on other Macs until the user right-clicks → Open, or you notarize.

To match OpenUsage’s “download and drag” path, enroll in the [Apple Developer Program](https://developer.apple.com/programs/) (~$99/year) and add these repository secrets:

| Secret | What it is |
|--------|------------|
| `APPLE_CERTIFICATE` | base64 of a Developer ID Application `.p12` |
| `APPLE_CERTIFICATE_PASSWORD` | password for that `.p12` |
| `APPLE_ID` | Apple ID email used for notarization |
| `APPLE_PASSWORD` | [app-specific password](https://appleid.apple.com) for that Apple ID |
| `APPLE_TEAM_ID` | Apple Developer team ID |

Export the cert from Keychain Access as `.p12`, then `base64 -i DeveloperID.p12 | pbcopy`. With those secrets set, the same tag pipeline signs with Developer ID, notarizes, and staples — the DMG opens without a Gatekeeper detour.

## Homebrew

Homebrew’s official cask repo wants a stable HTTPS download (the GitHub Release DMG) and a `sha256`. After the first notarized release:

```ruby
cask "port-harbor" do
  version "0.1.0"
  sha256 "…"

  url "https://github.com/patrick-dt/port-harbor/releases/download/v#{version}/PortHarbor-#{version}.dmg"
  name "Port Harbor"
  desc "Menu bar app for local dev servers"
  homepage "https://github.com/patrick-dt/port-harbor"

  app "Port Harbor.app"
end
```

Submit that to [Homebrew/homebrew-cask](https://github.com/Homebrew/homebrew-cask). Until it lands, do not advertise `brew install --cask port-harbor`.

## Sparkle (later)

OpenUsage updates in place via signed Sparkle + an appcast on GitHub Pages. That is the next step after notarization: embed Sparkle, bake `SUFeedURL` / `SUPublicEDKey` into `Info.plist`, and extend the release workflow with `generate_appcast`. Skip it until Developer ID signing works — unsigned Sparkle feeds are not worth the dependency.
