#!/usr/bin/env bash
# Builds a universal Port Harbor.app and wraps it in a DMG for GitHub Releases.
# Does not install to /Applications (use ./scripts/package-app.sh for that).
#
# Optional env:
#   PORT_HARBOR_VERSION          CFBundleShortVersionString (default: latest v* tag or 0.1.0)
#   CODESIGN_IDENTITY            Developer ID Application identity; otherwise ad-hoc
#   NOTARY_APPLE_ID
#   NOTARY_APP_PASSWORD
#   NOTARY_TEAM_ID               when all three are set, notarize + staple app and DMG
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Port Harbor"
BUNDLE_ID="com.portharbor.app"
BINARY_NAME="PortHarbor"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
SOURCE_ICON="$ROOT/Resources/AppIcon.png"

VERSION="$(git -C "$ROOT" describe --tags --match 'v*' --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
VERSION="${PORT_HARBOR_VERSION:-${VERSION:-0.1.0}}"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
DMG="$DIST/PortHarbor-${VERSION}.dmg"

build_icns() {
  local src="$1"
  local dest_icns="$2"
  local work
  work="$(mktemp -d "${TMPDIR:-/tmp}/portharbor-icon.XXXXXX")"
  local iconset="$work/AppIcon.iconset"
  mkdir -p "$iconset"
  local -a sizes=(16 32 128 256 512)
  local size
  for size in "${sizes[@]}"; do
    sips -z "$size" "$size" "$src" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$src" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$iconset" -o "$dest_icns"
  rm -rf "$work"
}

sign_app() {
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    echo "Signing with Developer ID: $CODESIGN_IDENTITY"
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP"
    codesign --verify --deep --strict --verbose=2 "$APP"
  else
    echo "Ad-hoc signing (set CODESIGN_IDENTITY for Developer ID)."
    codesign --force --sign - --timestamp=none "$APP"
  fi
}

notarize() {
  xcrun notarytool submit "$1" \
    --apple-id "$NOTARY_APPLE_ID" \
    --password "$NOTARY_APP_PASSWORD" \
    --team-id "$NOTARY_TEAM_ID" \
    --wait
}

cd "$ROOT"

echo "==> building $APP_NAME $VERSION ($BUILD_NUMBER) — universal (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64 --product "$BINARY_NAME"

BINARY="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$BINARY_NAME"
if [[ ! -x "$BINARY" ]]; then
  echo "error: built binary not found at $BINARY" >&2
  exit 1
fi

lipo -archs "$BINARY" | grep -q "x86_64" && lipo -archs "$BINARY" | grep -q "arm64" \
  || { echo "Expected a universal (arm64 + x86_64) binary, got: $(lipo -archs "$BINARY")" >&2; exit 1; }

echo "==> staging $APP"
rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BINARY" "$MACOS/$BINARY_NAME"
chmod +x "$MACOS/$BINARY_NAME"

BIN_DIR="$(dirname "$BINARY")"
shopt -s nullglob
RESOURCE_BUNDLES=("$BIN_DIR"/*.bundle)
if ((${#RESOURCE_BUNDLES[@]})); then
  cp -R "${RESOURCE_BUNDLES[@]}" "$MACOS/"
  echo "Resources: copied ${#RESOURCE_BUNDLES[@]} SwiftPM bundle(s)"
fi
if [[ -d "$ROOT/Sources/PortHarbor/Resources/FrameworkIcons" ]]; then
  mkdir -p "$RESOURCES/FrameworkIcons"
  cp -R "$ROOT/Sources/PortHarbor/Resources/FrameworkIcons/." "$RESOURCES/FrameworkIcons/"
fi
shopt -u nullglob

HAS_ICON=0
if [[ -f "$SOURCE_ICON" ]]; then
  build_icns "$SOURCE_ICON" "$RESOURCES/AppIcon.icns"
  cp "$SOURCE_ICON" "$RESOURCES/AppIcon.png"
  HAS_ICON=1
fi

{
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>${BINARY_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${APP_NAME}</string>
	<key>CFBundleDisplayName</key>
	<string>${APP_NAME}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${BUILD_NUMBER}</string>
EOF
  if [[ "$HAS_ICON" -eq 1 ]]; then
    cat <<'EOF'
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIconName</key>
	<string>AppIcon</string>
EOF
  fi
  cat <<EOF
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
EOF
} > "$CONTENTS/Info.plist"

sign_app

NOTARIZE=0
if [[ -n "${NOTARY_APPLE_ID:-}" && -n "${NOTARY_APP_PASSWORD:-}" && -n "${NOTARY_TEAM_ID:-}" ]]; then
  NOTARIZE=1
fi

if [[ "$NOTARIZE" -eq 1 ]]; then
  echo "==> notarizing app"
  APP_ZIP="$DIST/$BINARY_NAME-notarize.zip"
  ditto -c -k --keepParent "$APP" "$APP_ZIP"
  notarize "$APP_ZIP"
  xcrun stapler staple "$APP"
  rm -f "$APP_ZIP"
fi

echo "==> building $DMG"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/portharbor-dmg.XXXXXX")"
cp -R "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG"
fi

if [[ "$NOTARIZE" -eq 1 ]]; then
  echo "==> notarizing dmg"
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  echo "==> notarized + stapled"
fi

echo "Built: $APP"
echo "DMG:   $DMG"
if [[ "$NOTARIZE" -eq 0 ]]; then
  echo "Note: not notarized. Other Macs may need right-click → Open until Apple secrets are set."
  echo "See docs/releasing.md"
fi
