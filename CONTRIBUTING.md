# Contributing to Pocket Vault

Thanks for your interest. This document covers how to build the project locally, report issues, and submit pull requests.

---

## Requirements

- macOS 15.6 or later
- Xcode 16 or later
- No Apple Developer account required for local development

---

## Building Locally

Clone the repo and build without signing:

```bash
git clone https://github.com/YOUR_USERNAME/pocketvault.git
cd pocketvault

xcodebuild -project pocketvault.xcodeproj \
  -scheme pocketvault \
  -configuration Debug build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

Or open in Xcode directly:

```bash
open pocketvault.xcodeproj
```

Set the scheme to `pocketvault` and destination to `My Mac`, then run.

**Note:** Unsigned debug builds use an unscoped iCloud Keychain namespace for the master key. The master key created in a dev build will not be readable by a signed production build — this is expected. Vault contents themselves live in an encrypted blob on disk (and in CloudKit when sync is on), not in the Keychain.

---

## Project Structure

See [README.md](README.md) for the full directory breakdown and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for system design.

---

## Reporting Issues

Before opening an issue:
- Check existing issues to avoid duplicates
- Reproduce on the latest commit on `main`

When filing a bug, include:
- macOS version
- Steps to reproduce
- What you expected vs. what happened
- Any relevant console output from Console.app (filter by `pocketvault`)

For feature requests, describe the problem you are trying to solve rather than jumping straight to a proposed solution.

---

## Pull Requests

1. Fork the repo and create a branch from `main`
2. Branch naming: `fix/short-description` or `feat/short-description`
3. Keep changes focused — one logical change per PR
4. Test your change manually on a debug build before submitting
5. Open the PR against `main` with a clear description of what changed and why

PRs that touch `VaultRepository`, `SyncCoordinator`, `CloudVaultStore`, the encrypted vault blob format in `CryptoService`, or the `BackupService` snapshot format should include a brief note on how you tested the change (e.g. fresh install, sync toggle on/off, conflict resolution flow, two-device merge).

---

## Code Style

- Swift 5, `@MainActor` isolation by default across the module
- No third-party dependencies — keep it that way
- No force unwraps or `try!` outside of `fatalError`-equivalent situations
- Prefer throwing functions over returning optionals when failure has a reason worth surfacing
- Match the existing file/type structure described in ARCHITECTURE.md
- After any mutation to SwiftData entities (`Project`, `EnvFile`, `EnvEntry`), call `VaultRepository.shared.captureFromSwiftData(context:)` so the encrypted blob and sync engine stay in lockstep. SwiftData is purely an in-memory projection — the encrypted snapshot on disk is the source of truth.

---

## What Not to Send

- Changes to the encrypted vault blob format in `CryptoService` or the `VaultSnapshot` schema without a documented migration path
- Reintroducing per-secret Keychain storage — only the master key belongs in iCloud Keychain
- New third-party Swift packages
- UI changes without a clear rationale — the current design is intentional
