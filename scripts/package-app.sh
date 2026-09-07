#!/usr/bin/env bash
# Builds a double-clickable Port Harbor.app and installs it to /Applications.
# Re-run this after code changes to update the installed app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Port Harbor"
BUNDLE_ID="com.portharbor.app"
BINARY_NAME="PortHarbor"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
INSTALL_DIR="${PORT_HARBOR_INSTALL_DIR:-/Applications}"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
SOURCE_ICON="$ROOT/Resources/AppIcon.png"
INSTALL=1

# Prefer an annotated release tag (vX.Y.Z); fall back for untagged checkouts.
VERSION="$(git -C "$ROOT" describe --tags --match 'v*' --abbrev=0 2>/dev/null | sed 's/^v//' || true)"
VERSION="${PORT_HARBOR_VERSION:-${VERSION:-0.1.0}}"
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"

for arg in "$@"; do
  case "$arg" in
    --no-install) INSTALL=0 ;;
    -h|--help)
      echo "Usage: $0 [--no-install]"
      echo "  Builds dist/Port Harbor.app and copies it to $INSTALL_DIR"
      echo "  Uses Resources/AppIcon.png when present (converted to AppIcon.icns)."
      echo "  PORT_HARBOR_INSTALL_DIR overrides the install location."
      exit 0
      ;;
    *)
      echo "Unknown option: $arg (try --help)" >&2
      exit 1
      ;;
  esac
done

# Convert a square PNG master into AppIcon.icns for Finder / Spotlight.
build_icns() {
  local src="$1"
  local dest_icns="$2"
  local work
  work="$(mktemp -d "${TMPDIR:-/tmp}/portharbor-icon.XXXXXX")"
  local iconset="$work/AppIcon.iconset"
  mkdir -p "$iconset"

  # Required macOS iconset sizes
  local -a sizes=(16 32 128 256 512)
  local size
  for size in "${sizes[@]}"; do
    sips -z "$size" "$size" "$src" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$src" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
  done

  iconutil -c icns "$iconset" -o "$dest_icns"
  rm -rf "$work"
}

cd "$ROOT"
swift build -c release --product "$BINARY_NAME"

BINARY="$(swift build -c release --show-bin-path)/$BINARY_NAME"
if [[ ! -x "$BINARY" ]]; then
  echo "error: built binary not found at $BINARY" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BINARY" "$MACOS/$BINARY_NAME"
chmod +x "$MACOS/$BINARY_NAME"

HAS_ICON=0
if [[ -f "$SOURCE_ICON" ]]; then
  build_icns "$SOURCE_ICON" "$RESOURCES/AppIcon.icns"
  cp "$SOURCE_ICON" "$RESOURCES/AppIcon.png"
  HAS_ICON=1
  echo "Icon: embedded AppIcon.icns from Resources/AppIcon.png"
else
  echo "warning: no Resources/AppIcon.png — app will use the default executable icon" >&2
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

# Ad-hoc sign so macOS will launch it from Finder on this machine.
codesign --force --sign - --timestamp=none "$APP"

echo "Built: $APP (version $VERSION, build $BUILD_NUMBER)"

if [[ "$INSTALL" -eq 1 ]]; then
  # Quit a running copy so Finder/LaunchServices pick up the new binary.
  if pgrep -xq "$BINARY_NAME" >/dev/null 2>&1; then
    echo "Quitting running Port Harbor…"
    pkill -x "$BINARY_NAME" || true
    sleep 0.5
  fi
  mkdir -p "$INSTALL_DIR"
  rm -rf "$INSTALL_DIR/$APP_NAME.app"
  cp -R "$APP" "$INSTALL_DIR/"
  # Nudge LaunchServices / Finder to refresh the icon.
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_DIR/$APP_NAME.app" 2>/dev/null || true
  echo "Installed: $INSTALL_DIR/$APP_NAME.app"
  echo "Launch from Spotlight or Applications. Re-run this script to update."
else
  echo "Skipped install (--no-install). Copy manually if needed:"
  echo "  cp -R \"$APP\" \"$INSTALL_DIR/\""
fi
