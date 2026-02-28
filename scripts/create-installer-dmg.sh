#!/bin/zsh

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 /path/to/App.app /path/to/output.dmg [Volume Name]" >&2
  exit 1
fi

APP_PATH="$1"
DMG_PATH="$2"
VOL_NAME="${3:-QuotaPulse}"
APP_NAME="$(basename "$APP_PATH" .app)"

[[ -d "$APP_PATH" ]] || { echo "App not found: $APP_PATH" >&2; exit 1; }

WORK_DIR="$(mktemp -d /tmp/quotapulse-dmg.XXXXXX)"
RW_DMG="$WORK_DIR/temp-rw.dmg"
MOUNT_POINT="/Volumes/${VOL_NAME}-builder"

cleanup() {
  if [[ -d "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 || true
  fi
  if [[ -d "$WORK_DIR" ]]; then
    rm -r "$WORK_DIR" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

# Detach previous builder mounts to avoid volume conflicts.
hdiutil info | awk '/\/Volumes\/QuotaPulse-builder/ {print $NF}' | while IFS= read -r mp; do
  [[ -d "$mp" ]] || continue
  detached=false
  for _ in {1..12}; do
    if hdiutil detach "$mp" -force >/dev/null 2>&1; then
      detached=true
      break
    fi
    sleep 0.4
  done
  if [[ "$detached" != true ]]; then
    echo "Failed to detach stale mount: $mp" >&2
    exit 1
  fi
done

APP_SIZE_KB=$(du -sk "$APP_PATH" | awk '{print $1}')
DMG_SIZE_KB=$((APP_SIZE_KB + 65536)) # +64MB headroom

hdiutil create -size "${DMG_SIZE_KB}k" -fs HFS+ -volname "$VOL_NAME" "$RW_DMG" >/tmp/quotapulse_create_dmg.log 2>&1
hdiutil attach -readwrite -noverify -noautoopen -mountpoint "$MOUNT_POINT" "$RW_DMG" >/tmp/quotapulse_attach_dmg.log 2>&1

cp -R "$APP_PATH" "$MOUNT_POINT/$APP_NAME.app"
ln -s /Applications "$MOUNT_POINT/Applications"

sync
hdiutil detach "$MOUNT_POINT" -force >/tmp/quotapulse_detach_dmg.log 2>&1

rm -f "$DMG_PATH"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/tmp/quotapulse_convert_dmg.log 2>&1

if [[ "$DMG_PATH" != *.dmg && -f "$DMG_PATH.dmg" ]]; then
  mv "$DMG_PATH.dmg" "$DMG_PATH"
fi

echo "Created installer DMG: $DMG_PATH"
