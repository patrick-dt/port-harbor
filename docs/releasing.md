# Releasing

Install for now is **clone + `./scripts/package-app.sh`**. That builds on the user’s Mac, so Gatekeeper never sees a downloaded binary.

A notarized DMG (GitHub Releases, Homebrew cask, Sparkle) needs the [Apple Developer Program](https://developer.apple.com/programs/) (~$99/year). Until then, do not advertise a download button or `brew install --cask`.

## Versions

Keep a changelog. When you want a named version:

1. Move `[Unreleased]` in `CHANGELOG.md` into `## [X.Y.Z] - YYYY-MM-DD`.
2. Merge to `main`.
3. Tag:

```bash
git tag -a v0.1.0 -m "v0.1.0"
git push origin v0.1.0
```

Tags do **not** publish a DMG. The unsigned release workflow is manual (`workflow_dispatch` on [release.yml](../.github/workflows/release.yml)) so a tag cannot accidentally put a Gatekeeper-blocked image on the releases page.

## After a Developer ID

`scripts/release.sh` already builds a universal `.app` and DMG. Add these repository secrets, then you can turn tag-push publishing back on:

| Secret | What it is |
|--------|------------|
| `APPLE_CERTIFICATE` | base64 of a Developer ID Application `.p12` |
| `APPLE_CERTIFICATE_PASSWORD` | password for that `.p12` |
| `APPLE_ID` | Apple ID email used for notarization |
| `APPLE_PASSWORD` | [app-specific password](https://appleid.apple.com) for that Apple ID |
| `APPLE_TEAM_ID` | Apple Developer team ID |

Export the cert from Keychain Access as `.p12`, then `base64 -i DeveloperID.p12 | pbcopy`. With those set, the pipeline can sign, notarize, and staple — the same path [OpenUsage](https://github.com/robinebers/openusage) uses.

Then:

1. Point the README at the latest DMG.
2. Submit a Homebrew cask whose `url` is that GitHub Release asset.
3. Optionally embed Sparkle for in-app updates.
