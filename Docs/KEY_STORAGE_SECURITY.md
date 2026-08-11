# API Key Storage and Signing

QuotaPulse stores provider API keys in one aggregate generic-password item in the
macOS Data Protection Keychain. The v3 item uses
`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: after the user unlocks the Mac
once following a restart, background refreshes do not require user presence, and the
item is not migratable to another device.

## Migration invariants

- The v3 Data Protection item is always queried first.
- Legacy file-keychain storage is queried only after `errSecItemNotFound`.
- Authorization, interaction, entitlement, and decode failures never trigger a
  second legacy query.
- Migrated data is written and read back before v3 becomes authoritative.
- A non-secret completion marker prevents deleted keys from being resurrected from
  stale legacy items.
- An empty v3 keyring is retained as a tombstone rather than deleting the item.
- v1.0.10 retains the legacy item as a rollback snapshot. The exact v1.0.9 build can
  read that snapshot, but changes made later in v1.0.10 are not mirrored backwards;
  re-enter changed credentials after an old-version rollback.
- The one-time migration may request authorization for old Keychain items; the prompt
  count depends on their legacy ACLs. A cancelled or failed legacy read blocks ordinary
  settings saves instead of silently replacing credentials.

## Signing

Keychain access control depends on a stable application identity. Use
`scripts/build-secure-local-release.sh`; it refuses to package an app whose signature
does not match the expected TeamIdentifier (`Z7UZX2YQVM` by default), and also rejects
an unapproved change from the installed app's team. It prefers Developer ID Application
and falls back to Apple Development for local installations.

The script re-signs Sparkle's Installer, Downloader, Autoupdate, Updater, and framework
in the order documented by Sparkle. It deliberately does not use `codesign --deep`
for signing because component-specific sandbox entitlements must be preserved only
where Sparkle defines them.

Apple Development signing is suitable for maintaining identity on the developer's
own Mac, but it is not a replacement for Developer ID and notarization for public
distribution.

Do not publish ad-hoc-signed v3 builds: an app without a stable signed identity may
be unable to access its Data Protection Keychain item after an update.

The hosted unit-test process skips persisted-state initialization and application
startup. This prevents unsigned test hosts from reading or migrating a developer's
real API keys.
