#!/bin/zsh

set -euo pipefail

APP_NAME="API Tracker"
DEFAULT_DMG="$(cd "$(dirname "$0")/.." && pwd)/API-Tracker-latest.dmg"
DMG_PATH="${1:-$DEFAULT_DMG}"
MOUNT_POINT="/Volumes/API Tracker Test"

if [[ ! -f "$DMG_PATH" ]]; then
  echo "DMG not found: $DMG_PATH" >&2
  echo "Usage: $0 /path/to/file.dmg" >&2
  exit 1
fi

echo "Quitting running app (if any): $APP_NAME"
osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

for _ in {1..20}; do
  if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    break
  fi
  sleep 0.3
done

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  echo "Failed to quit $APP_NAME. Please close it manually and retry." >&2
  exit 1
fi

# Detach previous API Tracker mounts so the app path stays stable. This helps macOS
# Keychain remember the app identity when you click "Always Allow".
hdiutil info | awk '/\/Volumes\/API Tracker/ {print $NF}' | while IFS= read -r mp; do
  [[ -d "$mp" ]] || continue
  hdiutil detach "$mp" -force >/dev/null 2>&1 || true
done

echo "Mounting DMG: $DMG_PATH"
hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_POINT" "$DMG_PATH" >/tmp/api_tracker_hdiutil_attach.log 2>&1 || {
  cat /tmp/api_tracker_hdiutil_attach.log >&2
  exit 1
}

if [[ -z "$MOUNT_POINT" || ! -d "$MOUNT_POINT" ]]; then
  echo "Failed to mount DMG: $DMG_PATH" >&2
  exit 1
fi

APP_PATH="$MOUNT_POINT/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found in DMG: $APP_PATH" >&2
  exit 1
fi

echo "Opening app from DMG: $APP_PATH"
open "$APP_PATH"

echo "Done."
