#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_FILE="$PROJECT_ROOT/ApiUsageTrackerForMac.xcodeproj"
SCHEME="ApiUsageTrackerForMac"
APP_NAME="QuotaPulse"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PROJECT_ROOT/DerivedData/AutoVerify}"
DMG_PATH="${DMG_PATH:-$PROJECT_ROOT/QuotaPulse-latest.dmg}"
MOUNT_POINT="/Volumes/QuotaPulse Verify"
LAUNCH_TIMEOUT_SECONDS="${LAUNCH_TIMEOUT_SECONDS:-20}"
HEALTH_CHECK_SECONDS="${HEALTH_CHECK_SECONDS:-8}"
PRINT_APP_LOG_TAIL="${PRINT_APP_LOG_TAIL:-0}"
START_TS="$(date +%s)"

log() {
  echo "[auto-verify] $*"
}

fail() {
  echo "[auto-verify] ERROR: $*" >&2
  exit 1
}

quit_running_app() {
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true

  local waited=0
  while pgrep -x "$APP_NAME" >/dev/null 2>&1; do
    if (( waited >= 20 )); then
      fail "Failed to stop running app: $APP_NAME"
    fi
    sleep 0.3
    waited=$((waited + 1))
  done
}

detach_existing_mounts() {
  hdiutil info | awk '/\/Volumes\/QuotaPulse/ {print $NF}' | while IFS= read -r mount_path; do
    [[ -d "$mount_path" ]] || continue
    hdiutil detach "$mount_path" -force >/dev/null 2>&1 || true
  done
}

cleanup() {
  quit_running_app
  if [[ -d "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" -force >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT INT TERM

for cmd in xcodebuild hdiutil open osascript pgrep stat; do
  command -v "$cmd" >/dev/null 2>&1 || fail "Missing required command: $cmd"
done

log "Building app ($CONFIGURATION)..."
xcodebuild \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=NO >/tmp/api_tracker_auto_verify_build.log 2>&1 || {
    tail -n 80 /tmp/api_tracker_auto_verify_build.log >&2
    fail "Build failed"
  }

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
[[ -d "$APP_PATH" ]] || fail "Built app not found under DerivedData ($CONFIGURATION)"

log "Packaging installer DMG -> $DMG_PATH"
"$PROJECT_ROOT/scripts/create-installer-dmg.sh" "$APP_PATH" "$DMG_PATH" "QuotaPulse" >/tmp/api_tracker_auto_verify_dmg.log 2>&1 || {
  cat /tmp/api_tracker_auto_verify_dmg.log >&2
  fail "Failed to create installer DMG"
}

log "Preparing clean runtime state..."
quit_running_app
detach_existing_mounts

log "Mounting DMG..."
hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_POINT" "$DMG_PATH" >/tmp/api_tracker_auto_verify_attach.log 2>&1 || {
  cat /tmp/api_tracker_auto_verify_attach.log >&2
  fail "Failed to mount DMG"
}

APP_FROM_DMG="$MOUNT_POINT/$APP_NAME.app"
[[ -d "$APP_FROM_DMG" ]] || fail "App not found in mounted DMG: $APP_FROM_DMG"

log "Launching app from DMG..."
open "$APP_FROM_DMG"

log "Waiting for process startup..."
startup_ok=false
for _ in $(seq 1 "$LAUNCH_TIMEOUT_SECONDS"); do
  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    startup_ok=true
    break
  fi
  sleep 1
done

[[ "$startup_ok" == true ]] || fail "App did not launch within ${LAUNCH_TIMEOUT_SECONDS}s"

log "Running health check (${HEALTH_CHECK_SECONDS}s)..."
sleep "$HEALTH_CHECK_SECONDS"

if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  fail "App exited unexpectedly during health check"
fi

latest_crash=""
latest_crash_ts=0
diag_dir="$HOME/Library/Logs/DiagnosticReports"
if [[ -d "$diag_dir" ]]; then
  while IFS= read -r crash_file; do
    crash_ts="$(stat -f %m "$crash_file" 2>/dev/null || echo 0)"
    if (( crash_ts > latest_crash_ts )); then
      latest_crash_ts="$crash_ts"
      latest_crash="$crash_file"
    fi
  done < <(find "$diag_dir" -maxdepth 1 -type f -name "$APP_NAME*.crash" -print 2>/dev/null)
fi

if [[ -n "$latest_crash" ]] && (( latest_crash_ts >= START_TS )); then
  fail "Crash report detected during verification: $latest_crash"
fi

if [[ "$PRINT_APP_LOG_TAIL" == "1" ]] && [[ -f "$HOME/Documents/api_tracker.log" ]]; then
  log "Recent app log tail:"
  tail -n 12 "$HOME/Documents/api_tracker.log" || true
fi

log "Verification passed."
log "DMG ready: $DMG_PATH"
