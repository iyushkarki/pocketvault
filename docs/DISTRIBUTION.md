# Distribution

Step-by-step guide to go from a clean Xcode project to a notarized DMG on GitHub Releases. These are the exact commands that work — no placeholders.

---

## Credentials

| Thing | Value |
|-------|-------|
| Apple ID | `aayush.karki022@gmail.com` |
| Team ID | `2SCYKGKSF3` |
| App-specific password | `pjhn-sxnw-fkuq-lrri` |

---

## 1. Archive in Xcode

1. Set scheme to `pocketvault`, destination to `My Mac`
2. Bump version in **Target → General → Identity**:
   - **Version** → e.g. `1.0.0` (semantic version, what users see)
   - **Build** → increment by 1 each archive (e.g. `1`, `2`, `3`)
3. **Product → Archive**
4. Organizer opens → select the archive → **Distribute App → Direct Distribution**
5. Xcode signs and notarizes the `.app` — wait for it to complete
6. Export the `.app` to `docs/pocketvault.app` (overwrite the previous one)

The exported `.app` is already notarized at this point.

---

## 2. Create the DMG

Install `create-dmg` if not already installed:

```bash
brew install create-dmg
```

Run from the repo root:

```bash
create-dmg \
  --volname "Pocket Vault" \
  --window-pos 200 120 \
  --window-size 560 380 \
  --icon-size 120 \
  --icon "pocketvault.app" 140 185 \
  --hide-extension "pocketvault.app" \
  --app-drop-link 420 185 \
  --no-internet-enable \
  "PocketVault-1.0.0.dmg" \
  "docs/pocketvault.app"
```

Replace `1.0.0` in the output filename with the current version. This gives users the drag-to-Applications window inside the DMG.

---

## 3. Notarize the DMG

The `.app` inside is already notarized, but the DMG wrapper needs its own notarization ticket or Gatekeeper will block it.

```bash
xcrun notarytool submit PocketVault-1.0.0.dmg \
  --apple-id aayush.karki022@gmail.com \
  --team-id 2SCYKGKSF3 \
  --password pjhn-sxnw-fkuq-lrri \
  --wait
```

Wait for `status: Accepted`. If it fails, fetch the log:

```bash
xcrun notarytool log SUBMISSION_ID \
  --apple-id aayush.karki022@gmail.com \
  --team-id 2SCYKGKSF3 \
  --password pjhn-sxnw-fkuq-lrri
```

---

## 4. Staple

Embeds the notarization ticket into the DMG so Gatekeeper works offline:

```bash
xcrun stapler staple PocketVault-1.0.0.dmg
```

---

## 5. Verify

Mount the DMG and check the app inside — this is the correct check for DMGs (not `--type install` which is for `.pkg` installers):

```bash
hdiutil attach PocketVault-1.0.0.dmg -nobrowse
spctl --assess --verbose=4 "/Volumes/Pocket Vault/pocketvault.app"
hdiutil detach "/Volumes/Pocket Vault"
```

Expected output: `accepted source=Notarized Developer ID`

---

## 6. GitHub Release

```bash
gh release create v1.0.0 PocketVault-1.0.0.dmg \
  --title "Pocket Vault 1.0.0" \
  --notes "Initial release."
```

Or do it manually on GitHub: Releases → Draft a new release → attach the DMG → publish.

Tag format must be `vMAJOR.MINOR.PATCH`. The in-app update checker strips the leading `v` and compares against `CFBundleShortVersionString`.

---

## Quick Reference (copy-paste for next release)

```bash
# 1. Create DMG (run from repo root, update version in filename)
create-dmg \
  --volname "Pocket Vault" \
  --window-pos 200 120 \
  --window-size 560 380 \
  --icon-size 120 \
  --icon "pocketvault.app" 140 185 \
  --hide-extension "pocketvault.app" \
  --app-drop-link 420 185 \
  --no-internet-enable \
  "PocketVault-X.Y.Z.dmg" \
  "docs/pocketvault.app"

# 2. Notarize
xcrun notarytool submit PocketVault-X.Y.Z.dmg \
  --apple-id aayush.karki022@gmail.com \
  --team-id 2SCYKGKSF3 \
  --password pjhn-sxnw-fkuq-lrri \
  --wait

# 3. Staple
xcrun stapler staple PocketVault-X.Y.Z.dmg

# 4. Verify
hdiutil attach PocketVault-X.Y.Z.dmg -nobrowse
spctl --assess --verbose=4 "/Volumes/Pocket Vault/pocketvault.app"
hdiutil detach "/Volumes/Pocket Vault"

# 5. Release
gh release create vX.Y.Z PocketVault-X.Y.Z.dmg \
  --title "Pocket Vault X.Y.Z" \
  --notes "Release notes here."
```
