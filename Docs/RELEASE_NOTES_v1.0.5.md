# QuotaPulse v1.0.5 Release Notes

Release date: 2026-07-02

## Highlights

- Added optional pinned menu bar values:
  - DeepSeek balance, formatted as `¥xx`
  - Codex 5-hour remaining quota, formatted as `xx%`
  - Codex weekly remaining quota, formatted as `xx%`
  - each item supports custom prefix text, for example `DS ¥12` or `5h 73%`
- Changed Codex dashboard reset rows to show the next refresh time point instead of a relative countdown.
- Improved DeepSeek balance trend behavior:
  - each day now uses the last query result of that day
  - delta labels are protected from chart-edge clipping
  - missing days remain represented on the axis without creating fake data points
- Added a dedicated Settings > General > Menu Bar section for configuring pinned values.

## Behavior notes

- Pinned menu bar values use the latest refreshed data already held by QuotaPulse.
- Enabling pinned values does not add extra DeepSeek or Codex network requests.
- If a selected metric has no successful latest data, that metric is omitted from the menu bar until data becomes available.

## Distribution notes

- This build is distributed unsigned (DMG + ZIP).
- If macOS blocks first launch, allow it in:
  - System Settings -> Privacy & Security -> Open Anyway

## Included verification

- Debug unit tests passed (`xcodebuild test-without-building`, 19 tests, 0 failures)
- Debug app and widget builds passed
- Automated DMG startup verification passed (`./scripts/auto-verify.sh`)
