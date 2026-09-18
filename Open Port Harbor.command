#!/usr/bin/env bash
# Double-click this file in Finder to start Port Harbor (no IDE needed).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Port Harbor"
INSTALL_DIR="${PORT_HARBOR_INSTALL_DIR:-/Applications}"
APP="$INSTALL_DIR/$APP_NAME.app"
DIST_APP="$ROOT/dist/$APP_NAME.app"

pause_on_error() {
  local status=$?
  echo
  read -r -p "Press Enter to close…"
  exit "$status"
}
trap pause_on_error ERR

if [[ ! -d "$APP" && ! -d "$DIST_APP" ]]; then
  if ! command -v swift >/dev/null 2>&1; then
    echo "Port Harbor needs the Swift toolchain."
    echo "Command Line Tools are enough (no Xcode app required):"
    echo "  xcode-select --install"
    exit 1
  fi
  echo "Building Port Harbor (first launch)…"
  "$ROOT/scripts/package-app.sh"
fi

if [[ -d "$APP" ]]; then
  open "$APP"
elif [[ -d "$DIST_APP" ]]; then
  open "$DIST_APP"
else
  echo "error: $APP_NAME.app was not found after build." >&2
  exit 1
fi
