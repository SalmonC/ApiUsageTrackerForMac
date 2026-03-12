# QuotaPulse v1.0.2 Release Notes

Release date: 2026-03-12

## Highlights

- Fixed an intermittent popover positioning bug:
  - the dashboard could sometimes open away from the menu bar icon
  - popover resizing now reuses a captured stable top anchor after the system places the window
- Kept the existing dynamic height behavior without regressing the menu bar attachment logic

## Notes

- This build is distributed unsigned (DMG + ZIP).
- If macOS blocks first launch, allow it in:
  - System Settings -> Privacy & Security -> Open Anyway

## Included verification

- Debug tests passed (`xcodebuild test`, 9 tests, 0 failures)
- Automated package/startup verification passed (`./scripts/auto-verify.sh`)
- Release build passed (`xcodebuild -configuration Release build`)
