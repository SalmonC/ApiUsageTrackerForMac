#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT_FILE="$PROJECT_ROOT/ApiUsageTrackerForMac.xcodeproj"
SCHEME="ApiUsageTrackerForMac"
APP_NAME="QuotaPulse"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$PROJECT_ROOT/DerivedData/ReleaseBuild}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/Artifacts/release}"
DMG_PATH="${DMG_PATH:-$OUTPUT_DIR/${APP_NAME}-${CONFIGURATION}.dmg}"
ZIP_PATH="${ZIP_PATH:-$OUTPUT_DIR/${APP_NAME}-${CONFIGURATION}.zip}"

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [[ -z "$CODESIGN_IDENTITY" ]]; then
  echo "CODESIGN_IDENTITY is required. Example: Developer ID Application: Your Name (TEAMID)" >&2
  exit 1
fi

if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "NOTARY_PROFILE is required. Create one with: xcrun notarytool store-credentials" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "[release] Building signed app..."
xcodebuild \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$CODESIGN_IDENTITY"

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found: $APP_PATH" >&2
  exit 1
fi

echo "[release] Re-signing app bundle..."
codesign --force --deep --options runtime --sign "$CODESIGN_IDENTITY" "$APP_PATH"

echo "[release] Building zip for Sparkle..."
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "[release] Submitting app for notarization..."
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "[release] Stapling app..."
xcrun stapler staple "$APP_PATH"

echo "[release] Creating DMG..."
"$PROJECT_ROOT/scripts/create-installer-dmg.sh" "$APP_PATH" "$DMG_PATH" "QuotaPulse"

echo "[release] Done."
echo "[release] App : $APP_PATH"
echo "[release] Zip : $ZIP_PATH"
echo "[release] DMG : $DMG_PATH"
