# Pocket Vault

> **Beta:** This is a pre-release build. Expect rough edges. Please [report issues](https://github.com/anomalyco/pocketvault/issues).

A native macOS app with a menu bar companion for securely managing `.env` environment variables.

The vault is a single encrypted blob (AES-256-GCM) stored locally and, optionally, mirrored to your private CloudKit database. The encryption key lives in iCloud Keychain so it travels with your Apple ID and never touches a server in the clear. SwiftData is used purely as an in-memory view of the vault — the vault file is the single source of truth. Zero third-party dependencies.

---

## Download

**[Download PocketVault-1.0.0.dmg](https://github.com/iyushkarki/pocketvault/releases/download/v1.0.0-beta.1/PocketVault-1.0.0.dmg)**

Requires macOS 15.6 or later. Notarized by Apple.

1. Open the `.dmg` and drag Pocket Vault to Applications.
2. Launch from Applications or Spotlight — Pocket Vault opens as a normal macOS app and also adds a menu bar companion.
3. On first launch, complete the onboarding in the main window to set up your vault.

---

## Features

- **Menu bar quick access** -- browse projects, reveal and copy values in one click
- **Full editor window** -- create projects, manage files, add/edit/delete entries
- **Touch ID / device authentication** -- app starts locked, unlock with biometrics
- **iCloud sync** -- optional, gated on iCloud Keychain availability; conflicts and remote deletions always surface to you
- **Import/export .env files** -- standard KEY=VALUE format with conflict resolution
- **Encrypted backups** -- portable `.pocketvault` snapshot format (PBKDF2 + AES-256-GCM)
- **Auto-lock** -- configurable timeout, locks on sleep/screen lock
- **Auto-clear clipboard** -- configurable timeout after copying a secret
- **Table and Raw view** -- toggle between structured editor and raw `.env` text

## Requirements

- macOS 15.6 or later
- Apple Silicon or Intel Mac

## Build

```bash
# Debug build (no signing)
xcodebuild -project pocketvault.xcodeproj \
  -scheme pocketvault \
  -configuration Debug build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

# Or open in Xcode
open pocketvault.xcodeproj
```

## Project Structure

```
pocketvault/
├── App/
│   └── PocketVaultApp.swift           # @main -- bootstrap, scenes, onboarding flow
│
├── Core/
│   ├── Config/AppConfig.swift         # Bundle ID, Keychain service name, UserDefaults keys
│   ├── Data/
│   │   ├── DataManager.swift          # In-memory SwiftData ModelContainer (rebuilt from snapshot)
│   │   └── VaultRepository.swift      # @MainActor source of truth: snapshot ↔ SwiftData ↔ disk
│   ├── Models/
│   │   ├── Project.swift              # SwiftData Project (transient view model)
│   │   ├── EnvFile.swift              # SwiftData EnvFile (transient view model)
│   │   ├── EnvEntry.swift             # SwiftData EnvEntry (key, value, sortOrder, comment)
│   │   ├── VaultSnapshot.swift        # The persisted vault (Codable)
│   │   └── CloudVaultManifest.swift   # CloudKit metadata (revision, deletion tombstone)
│   └── Services/
│       ├── AppRelauncher.swift        # Safe in-place app restart helper
│       ├── BiometricService.swift     # Touch ID / device auth (LAContext)
│       ├── CryptoService.swift        # PBKDF2 + AES-256-GCM for .pocketvault backups
│       ├── EncryptedVaultStore.swift  # On-disk vault file (AES-256-GCM via VaultKeyService)
│       ├── VaultKeyService.swift      # Master key in iCloud Keychain (synchronizable)
│       ├── BackupService.swift        # Snapshot ↔ encrypted .pocketvault file
│       ├── ICloudKeychainAvailability.swift  # Probe + System Settings deep-link
│       ├── CloudVaultStore.swift      # CloudKit record I/O for the vault blob + manifest
│       ├── CloudVaultSubscription.swift  # CKQuerySubscription + 60s scheduler fallback
│       ├── SyncCoordinator.swift      # State machine: off / ready / syncing / conflict / remoteDeleted
│       ├── SearchService.swift        # Cross-project search
│       ├── ImportService.swift        # .env import → SwiftData → captureFromSwiftData
│       ├── ExportService.swift        # .env export via NSSavePanel
│       ├── EnvParser.swift            # .env file parser and formatter
│       ├── LockManager.swift          # Auto-lock, sleep lock, activity tracking
│       ├── NameValidator.swift        # Shared project/file naming rules
│       └── ClipboardManager.swift     # Auto-clear clipboard after timeout
│
├── Design/
│   ├── Components/
│   │   ├── EmptyStateView.swift       # Reusable empty state
│   │   ├── SecureValueField.swift     # Masked value with reveal toggle
│   │   └── EnvEntryRow.swift          # Key-value row component
│   └── Theme/AppTheme.swift           # Colors, fonts, spacing, sizing tokens
│
├── Features/
│   ├── Import/
│   │   ├── ImportView.swift           # .env import sheet
│   │   ├── VaultExportView.swift      # Encrypted .pocketvault export (BackupService)
│   │   └── VaultImportView.swift      # Encrypted .pocketvault import (BackupService.merge)
│   ├── Lock/
│   │   └── MasterPasswordUnlockView.swift  # UnlockView device auth screen
│   ├── MainWindow/
│   │   ├── MainWindowView.swift       # NavigationSplitView root + conflict/remote-deleted sheets
│   │   └── SidebarView.swift          # Project/file tree
│   ├── MenuBar/
│   │   ├── MenuBarView.swift          # Quick-access popover
│   │   ├── SettingsView.swift         # Settings tabs (sync gated on iCloud Keychain)
│   │   └── Subviews/
│   │       ├── QuickSearchView.swift
│   │       ├── ConflictResolutionSheet.swift
│   │       └── RemoteDeletedSheet.swift
│   ├── Onboarding/
│   │   └── OnboardingView.swift       # First-run flow with iCloud Keychain check
│   ├── Projects/Subviews/
│   │   ├── CreateProjectSheet.swift
│   │   └── EditProjectSheet.swift
│   └── EnvEditor/
│       ├── EnvEditorView.swift        # Entry list with Table/Raw toggle
│       ├── EnvEditorViewModel.swift   # CRUD + captureFromSwiftData on every save
│       └── Subviews/
│           ├── AddEntrySheet.swift
│           ├── EditEntrySheet.swift
│           ├── CreateFileSheet.swift
│           └── EditFileSheet.swift
│
└── Assets.xcassets/
    ├── AppIcon.appiconset/            # App icon (all sizes)
    └── StatusBarIcon.imageset/        # Menu bar icon (template)
```

## Architecture

```
                   ┌─────────────────────────┐
                   │  iCloud Keychain        │  ← master key only
                   │  (synchronizable)       │
                   └──────────┬──────────────┘
                              │ unwraps
                              ▼
   SwiftUI views ──► SwiftData (in-memory)
        │                     │
        │ captureFromSwiftData│
        ▼                     ▼
   VaultRepository ──► VaultSnapshot ──► EncryptedVaultStore (AES-256-GCM blob on disk)
                                    │
                                    │ scheduleUpload (1.5s debounce)
                                    ▼
                              SyncCoordinator
                                    │
                              ┌─────┴─────┐
                              ▼           ▼
                       CloudVaultStore  CloudVaultSubscription
                       (CKRecord I/O)   (CKQuerySubscription + 60s scheduler)
                              │
                              ▼
                       CloudKit private DB
```

- **Single source of truth** is the encrypted vault blob on disk. SwiftData is rebuilt from `VaultSnapshot` at launch and after every cloud pull.
- **Writes flow** view → SwiftData → `VaultRepository.captureFromSwiftData(context:)` → save to disk → `SyncCoordinator` schedules an upload.
- **iCloud sync is hard-gated** on iCloud Keychain. If unavailable, the toggle in Settings/Onboarding is disabled and a deep-link to System Settings is shown.
- **Conflicts always ask the user** (never auto-merge). Remote deletions show a "Keep local / Wipe local" sheet on every other Mac.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift 5 |
| UI | SwiftUI |
| State | `@Observable` (Observation framework) |
| Data | SwiftData + CloudKit |
| Secrets | macOS Keychain (Security framework) |
| Crypto | CryptoKit + CommonCrypto |
| Auth | LocalAuthentication (Touch ID) |
| Target | macOS 15.6 |
| Dependencies | None (Apple frameworks only) |
