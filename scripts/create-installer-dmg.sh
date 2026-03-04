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
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DMG_BG_PATH="$SCRIPT_DIR/assets/dmg-background.png"
DMG_BG_GEN_SCRIPT="$SCRIPT_DIR/generate-dmg-background.swift"

[[ -d "$APP_PATH" ]] || { echo "App not found: $APP_PATH" >&2; exit 1; }

if [[ -f "$DMG_BG_GEN_SCRIPT" ]]; then
  swift "$DMG_BG_GEN_SCRIPT" >/tmp/quotapulse_generate_bg.log 2>&1 || {
    cat /tmp/quotapulse_generate_bg.log >&2
    echo "Failed to generate DMG background image" >&2
    exit 1
  }
fi

WORK_DIR="$(mktemp -d /tmp/quotapulse-dmg.XXXXXX)"
RW_DMG="$WORK_DIR/temp-rw.dmg"
MOUNT_POINT="/Volumes/${VOL_NAME}"

cleanup() {
  if [[ -d "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 || true
  fi
  if [[ -d "$WORK_DIR" ]]; then
    rm -r "$WORK_DIR" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

# Detach previous mounts using the same volume path to avoid conflicts.
hdiutil info | awk -v vol="/Volumes/${VOL_NAME}" '$0 ~ vol {print $NF}' | while IFS= read -r mp; do
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
rm -f "$MOUNT_POINT/Applications"
ln -s /Applications "$MOUNT_POINT/Applications"
if [[ -f "$DMG_BG_PATH" ]]; then
  mkdir -p "$MOUNT_POINT/.background"
  cp "$DMG_BG_PATH" "$MOUNT_POINT/.background/dmg-background.png"
fi

# Configure Finder layout (drag-to-Applications style window).
if ! osascript >/tmp/quotapulse_dmg_finder_layout.log 2>&1 <<APPLESCRIPT
set dmgFolder to POSIX file "${MOUNT_POINT}" as alias

tell application "Finder"
  open dmgFolder
  delay 0.4

  set dmgWindow to container window of dmgFolder
  set current view of dmgWindow to icon view
  set toolbar visible of dmgWindow to false
  set statusbar visible of dmgWindow to false
  set bounds of dmgWindow to {120, 90, 940, 560}

  set opts to the icon view options of dmgWindow
  set arrangement of opts to not arranged
  set icon size of opts to 116
  set text size of opts to 14
  set shows icon preview of opts to true
  set shows item info of opts to false
  if exists file ".background:dmg-background.png" of dmgFolder then
    set background picture of opts to file ".background:dmg-background.png" of dmgFolder
  end if

  set position of item "${APP_NAME}.app" of dmgFolder to {210, 240}
  set position of item "Applications" of dmgFolder to {595, 240}

  update dmgFolder without registering applications
  delay 0.8
  close dmgWindow
  delay 0.4
end tell
APPLESCRIPT
then
  cat /tmp/quotapulse_dmg_finder_layout.log >&2
  echo "Failed to configure DMG Finder layout" >&2
  exit 1
fi

sync
sync
hdiutil detach "$MOUNT_POINT" -force >/tmp/quotapulse_detach_dmg.log 2>&1

rm -f "$DMG_PATH"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/tmp/quotapulse_convert_dmg.log 2>&1

if [[ "$DMG_PATH" != *.dmg && -f "$DMG_PATH.dmg" ]]; then
  mv "$DMG_PATH.dmg" "$DMG_PATH"
fi

echo "Created installer DMG: $DMG_PATH"
