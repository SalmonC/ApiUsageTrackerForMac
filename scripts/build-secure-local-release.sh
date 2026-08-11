#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_FILE="$PROJECT_ROOT/ApiUsageTrackerForMac.xcodeproj"
SCHEME="ApiUsageTrackerForMac"
APP_NAME="QuotaPulse"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PROJECT_ROOT/DerivedData/SecureLocalRelease}"
ENTITLEMENTS="$PROJECT_ROOT/Sources/App/Resources/ApiUsageTrackerForMac.entitlements"
INSTALL="${INSTALL:-0}"
EXPECTED_TEAM_IDENTIFIER="${EXPECTED_TEAM_IDENTIFIER:-Z7UZX2YQVM}"
ALLOW_TEAM_CHANGE="${ALLOW_TEAM_CHANGE:-0}"
ALLOW_REQUIREMENT_CHANGE="${ALLOW_REQUIREMENT_CHANGE:-0}"
INSTALLED_APP="/Applications/$APP_NAME.app"

source "$PROJECT_ROOT/VERSION"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/Artifacts/v$VERSION}"
DMG_PATH="${DMG_PATH:-$OUTPUT_DIR/$APP_NAME-$VERSION.dmg}"
ZIP_PATH="${ZIP_PATH:-$OUTPUT_DIR/$APP_NAME-$VERSION.zip}"

find_identity() {
  local requested="${CODESIGN_IDENTITY:-}"
  if [[ -n "$requested" ]]; then
    echo "$requested"
    return
  fi

  local identities
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"

  if [[ -d "$INSTALLED_APP" ]]; then
    local installed_authority
    installed_authority="$(codesign -dv --verbose=4 "$INSTALLED_APP" 2>&1 | awk -F= '/^Authority=/{print $2; exit}' || true)"
    if [[ -n "$installed_authority" ]] && printf '%s\n' "$identities" | grep -Fq "\"$installed_authority\""; then
      echo "$installed_authority"
      return
    fi
  fi

  local developer_id
  developer_id="$(printf '%s\n' "$identities" | awk -F'"' '/Developer ID Application:/ {print $2; exit}')"
  if [[ -n "$developer_id" ]]; then
    echo "$developer_id"
    return
  fi

  local development
  development="$(printf '%s\n' "$identities" | awk -F'"' '/Apple Development:/ {print $2; exit}')"
  if [[ -n "$development" ]]; then
    echo "$development"
    return
  fi

  return 1
}

IDENTITY="$(find_identity)" || {
  echo "No stable code-signing identity is available." >&2
  echo "Install an Apple Development or Developer ID Application certificate first." >&2
  exit 1
}

mkdir -p "$OUTPUT_DIR"

echo "[secure-release] Generating project..."
xcodegen generate --spec "$PROJECT_ROOT/project.yml"

echo "[secure-release] Building unsigned app before applying the stable identity..."
xcodebuild \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGN_IDENTITY="-"

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
[[ -d "$APP_PATH" ]] || { echo "Built app not found: $APP_PATH" >&2; exit 1; }

echo "[secure-release] Signing with: $IDENTITY"
SPARKLE_FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION="$SPARKLE_FRAMEWORK/Versions/B"

# Sparkle's official manual-signing order. Do not use `codesign --deep` here:
# Downloader may carry component-specific entitlements that must not be applied to
# the framework or the host application.
codesign --force --sign "$IDENTITY" --options runtime \
  "$SPARKLE_VERSION/XPCServices/Installer.xpc"
codesign --force --sign "$IDENTITY" --options runtime --preserve-metadata=entitlements \
  "$SPARKLE_VERSION/XPCServices/Downloader.xpc"
codesign --force --sign "$IDENTITY" --options runtime \
  "$SPARKLE_VERSION/Autoupdate"
codesign --force --sign "$IDENTITY" --options runtime \
  "$SPARKLE_VERSION/Updater.app"
codesign --force --sign "$IDENTITY" --options runtime \
  "$SPARKLE_FRAMEWORK"

codesign \
  --force \
  --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --sign "$IDENTITY" \
  "$APP_PATH"

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

TEAM_IDENTIFIER="$(codesign -dvv "$APP_PATH" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2; exit}')"
[[ -n "$TEAM_IDENTIFIER" && "$TEAM_IDENTIFIER" != "not set" ]] || {
  echo "Signed app has no stable TeamIdentifier; refusing to package." >&2
  exit 1
}
[[ "$TEAM_IDENTIFIER" == "$EXPECTED_TEAM_IDENTIFIER" ]] || {
  echo "Signing team changed: expected $EXPECTED_TEAM_IDENTIFIER, got $TEAM_IDENTIFIER." >&2
  echo "Set EXPECTED_TEAM_IDENTIFIER explicitly only for an intentional migration." >&2
  exit 1
}

if [[ -d "$INSTALLED_APP" ]]; then
  INSTALLED_TEAM="$(codesign -dvv "$INSTALLED_APP" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2; exit}' || true)"
  if [[ -n "$INSTALLED_TEAM" && "$INSTALLED_TEAM" != "not set" && "$INSTALLED_TEAM" != "$TEAM_IDENTIFIER" && "$ALLOW_TEAM_CHANGE" != "1" ]]; then
    echo "Installed app uses TeamIdentifier $INSTALLED_TEAM; refusing silent change to $TEAM_IDENTIFIER." >&2
    echo "Set ALLOW_TEAM_CHANGE=1 only after planning a Keychain migration." >&2
    exit 1
  fi

  INSTALLED_REQUIREMENT="$(codesign -d -r- "$INSTALLED_APP" 2>&1 | sed -n 's/^designated => //p' || true)"
  NEW_REQUIREMENT="$(codesign -d -r- "$APP_PATH" 2>&1 | sed -n 's/^designated => //p' || true)"
  if [[ -n "$INSTALLED_REQUIREMENT" && -n "$NEW_REQUIREMENT" && "$INSTALLED_REQUIREMENT" != "$NEW_REQUIREMENT" && "$ALLOW_REQUIREMENT_CHANGE" != "1" ]]; then
    echo "Installed app and new app have different designated requirements; refusing silent Keychain ACL identity change." >&2
    echo "Set ALLOW_REQUIREMENT_CHANGE=1 only after planning a one-time Keychain authorization migration." >&2
    exit 1
  fi
fi

echo "[secure-release] Packaging ZIP and DMG..."
rm -f "$ZIP_PATH" "$DMG_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
"$PROJECT_ROOT/scripts/create-installer-dmg.sh" "$APP_PATH" "$DMG_PATH" "QuotaPulse $VERSION"

if [[ "$INSTALL" == "1" ]]; then
  echo "[secure-release] Replacing /Applications/$APP_NAME.app..."
  osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  rm -rf "/Applications/$APP_NAME.app"
  ditto "$APP_PATH" "/Applications/$APP_NAME.app"
  open "/Applications/$APP_NAME.app"
fi

echo "[secure-release] App: $APP_PATH"
echo "[secure-release] ZIP: $ZIP_PATH"
echo "[secure-release] DMG: $DMG_PATH"
echo "[secure-release] TeamIdentifier: $TEAM_IDENTIFIER"
