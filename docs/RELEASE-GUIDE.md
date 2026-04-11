# Release Guide

Checklist and version policy for shipping Pocket Vault.

See `DISTRIBUTION.md` for the exact DMG creation, notarization, and upload commands.

---

## Shipping Model

- Distribution: direct download DMG from website + GitHub Releases
- Signing: `Developer ID Application: Solyx Studios, LLC (2SCYKGKSF3)`
- No App Store, no sandbox, no StoreKit
- GitHub Releases hosts the DMG asset. Website download button links to the asset URL.

---

## Version Numbering

| Version | When |
|---------|------|
| `1.0.0` | First public release |
| `1.0.1` | Bug fixes |
| `1.1.0` | New features |
| `2.0.0` | Major or breaking changes |

Set both in **Target → General → Identity** before archiving:
- **Version** — marketing version shown to users (`CFBundleShortVersionString`)
- **Build** — increment by 1 for every archive (`CFBundleVersion`)

---

## CloudKit Before Release

If the CloudKit schema is still in development, deploy to production before shipping:

1. Run a signed build with sync enabled
2. Exercise project / file / entry creation
3. Verify data appears in CloudKit Dashboard (development environment)
4. Deploy schema to production in CloudKit Dashboard
5. Test again with a fresh signed build
6. Test on a second Mac on the same iCloud account

Skipping this means sync works locally in dev but fails for real users.

---

## Pre-Release Checklist

### Code

- [ ] Zero warnings in Xcode
- [ ] Release build succeeds with Developer ID signing
- [ ] Test on a clean Mac with no existing data
- [ ] Touch ID unlock works
- [ ] iCloud sync works (enable in onboarding, verify across two Macs)
- [ ] `.env` import and export work
- [ ] `.envvault` export and import work
- [ ] Auto-lock and unlock work
- [ ] Light mode and dark mode look correct
- [ ] Delete All Data in Settings works

### CloudKit

- [ ] CloudKit schema deployed to production
- [ ] Second-Mac sync test completed

### Distribution

- [ ] Version and build number bumped in Xcode
- [ ] Archive exported with Developer ID signing
- [ ] DMG created, notarized, stapled (see `DISTRIBUTION.md`)
- [ ] App inside DMG passes: `spctl --assess --verbose=4` → `accepted source=Notarized Developer ID`
- [ ] GitHub Release published with tag `vX.Y.Z`
- [ ] Website download link updated to new DMG asset URL
