# API Key Storage and Signing

QuotaPulse stores provider API keys in one aggregate generic-password item in the
macOS login Keychain. The item uses the standard macOS Keychain ACL bound to the
app's stable code-signing identity. It does not request user-presence access control,
so background refreshes can read it after the user has logged in without a recurring
device-password prompt.

The locally distributed main app is intentionally outside App Sandbox. A manually
packaged Personal Team build does not receive a provisioned App Group/Data Protection
Keychain identity: adding those entitlements produces `Container: null` preference
failures and Keychain status `-34018`. Keeping the established preferences domain
therefore preserves existing accounts, cached usage, history, and settings without a
copy or destructive migration. The desktop widget remains unembedded because it
requires a provisioned App Group.

## Keychain migration invariants

- The v3 login-Keychain item is always queried first.
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

Login Keychain ACL access depends on a stable application identity. Use
`scripts/build-secure-local-release.sh`; it refuses to package an app whose signature
does not match the expected TeamIdentifier (`Z7UZX2YQVM` by default). When an installed
copy exists, it reuses that exact signing authority and rejects an unapproved change
to either the team or the complete designated requirement. On a first installation it
prefers Developer ID Application and falls back to Apple Development.

The script re-signs Sparkle's Installer, Downloader, Autoupdate, Updater, and framework
in the order documented by Sparkle. It deliberately does not use `codesign --deep`
for signing because component-specific sandbox entitlements must be preserved only
where Sparkle defines them.

Apple Development signing is suitable for maintaining identity on the developer's
own Mac, but it is not a replacement for Developer ID and notarization for public
distribution. App Sandbox, App Groups, and the Data Protection Keychain should only
be enabled again in a separately provisioned distribution after an explicit storage
migration has been designed and tested.

Do not publish ad-hoc-signed v3 builds: changing the app's designated requirement can
cause macOS to request authorization again or deny the existing login-Keychain item.

The hosted unit-test process skips persisted-state initialization and application
startup. This prevents unsigned test hosts from reading or migrating a developer's
real API keys.
