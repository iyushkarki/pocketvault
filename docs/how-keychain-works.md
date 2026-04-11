# How Keychain and iCloud Sync Work

## What syncs via CloudKit (SwiftData)

Metadata only — the SwiftData models (`Project`, `EnvFile`, `EnvEntry`). These contain:

- Project names, descriptions
- File names
- Entry keys (e.g. `DATABASE_URL`) and `keychainIdentifier` references
- Sort order, timestamps

This syncs through `NSPersistentCloudKitContainer` (SwiftData's CloudKit integration). Encrypted in transit (TLS) and at rest on Apple's servers — Apple manages those keys.

## What syncs via iCloud Keychain

The actual secret values. When sync is enabled, `KeychainService` stores items with:

```
kSecAttrSynchronizable = true
kSecAttrAccessible = kSecAttrAccessibleWhenUnlocked
```

This tells macOS to sync the Keychain item via iCloud Keychain, which is Apple's end-to-end encrypted sync system.

### The encryption chain

1. Secret stored in Keychain on Device A
2. macOS encrypts it using a device-derived key (tied to Secure Enclave on Apple Silicon)
3. iCloud Keychain wraps it using a syncing identity key negotiated between your devices via a key agreement protocol
4. The wrapped blob goes to Apple's servers — Apple cannot read it (end-to-end encrypted)
5. Device B downloads the blob, unwraps it using its own syncing identity key
6. Device B's Secure Enclave decrypts it locally

**Key point:** Apple never sees the plaintext secret values. Your app doesn't implement any of this — the Security framework handles it automatically when `kSecAttrSynchronizable = true` is set.

## When sync is off

```
kSecAttrAccessible = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
```

This tells macOS to never sync the item. It stays on the local device's Secure Enclave only.

## Why the split design

Keeping secrets out of CloudKit entirely means:
- Apple's CloudKit servers never hold secret values, even encrypted ones
- Secret sync uses iCloud Keychain's battle-tested key agreement protocol
- If CloudKit sync breaks or lags, secrets are still safe locally

## Migration when toggling sync

`SyncService` handles migrating existing Keychain items when the user toggles sync:

- **Enabling sync**: reads each `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` item → writes a new syncable copy → deletes the old one
- **Disabling sync**: reverse — writes a local-only copy, deletes the syncable one
- Progress is tracked in UserDefaults for crash recovery (migration can be resumed if interrupted)
- Requires app restart because `ModelContainer` (for the CloudKit/SwiftData side) cannot be reconfigured at runtime
