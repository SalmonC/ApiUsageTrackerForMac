# QuotaPulse v1.0.1 Release Notes

Release date: 2026-03-05

## Highlights

- Fixed Settings account-name editing flow:
  - Blur commit works when clicking outside the field (inside app and outside app)
  - Enter key commit is stable
  - Re-clicking the same input no longer exits edit mode unexpectedly
- Kept expected save semantics:
  - Name draft updates immediately in Settings
  - Dashboard applies the final name only after clicking **Save Settings**
- Fixed dashboard flicker during refresh:
  - Disabled list scroll indicators to avoid frequent show/hide during dynamic height updates
  - Increased height report threshold to reduce popover micro-resize jitter
- Refactored shared sorting logic for app and widget to improve consistency

## Notes

- This build is distributed unsigned (DMG + ZIP).
- If macOS blocks first launch, allow it in:
  - System Settings -> Privacy & Security -> Open Anyway

## Included verification

- Debug tests passed (`xcodebuild test`, 9 tests, 0 failures)
- Release build passed (`xcodebuild -configuration Release build`)

