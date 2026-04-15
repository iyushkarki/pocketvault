# Pocket Vault

> **Beta:** This is a pre-release build. Expect rough edges. Please [report issues](https://github.com/anomalyco/pocketvault/issues).

A native macOS menu bar app for securely managing `.env` environment variables.

Secrets are stored in the macOS Keychain (hardware-backed AES-256 encryption on Apple Silicon). Metadata syncs across devices via iCloud. Zero third-party dependencies.

---

## Download

**[Download PocketVault-1.0.0.dmg](https://github.com/iyushkarki/pocketvault/releases/download/v1.0.0-beta.1/PocketVault-1.0.0.dmg)**

Requires macOS 15.6 or later. Notarized by Apple.

1. Open the `.dmg` and drag Pocket Vault to Applications.
2. Launch from Applications or Spotlight — the app lives in your menu bar.
3. On first launch, complete the short onboarding to set up your vault.

---

## Features

- **Menu bar quick access** -- browse projects, reveal and copy values in one click
- **Full editor window** -- create projects, manage files, add/edit/delete entries
- **Touch ID / device authentication** -- app starts locked, unlock with biometrics
- **iCloud sync** -- projects and secrets sync across your Macs (opt-in)
- **Import/export .env files** -- standard KEY=VALUE format with conflict resolution
- **Encrypted backups** -- portable `.envvault` format (PBKDF2 + AES-256-GCM)
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
│   ├── PocketVaultApp.swift           # @main -- MenuBarExtra + Window + Settings scenes
│   └── AppDelegate.swift              # Dock visibility toggling
│
├── Core/
│   ├── Config/AppConfig.swift         # Bundle ID, Keychain service name, UserDefaults keys
│   ├── Data/DataManager.swift         # SwiftData ModelContainer (CloudKit-capable)
│   ├── Models/
│   │   ├── Project.swift              # Project model (name, description, files)
│   │   ├── EnvFile.swift              # File model (name, project, entries)
│   │   └── EnvEntry.swift             # Entry model (key, keychainIdentifier, sortOrder)
│   └── Services/
│       ├── KeychainService.swift      # Keychain CRUD (Security framework)
│       ├── BiometricService.swift     # Touch ID / device auth (LAContext)
│       ├── CryptoService.swift        # PBKDF2 + AES-256-GCM for .envvault
│       ├── VaultService.swift         # Serialize/deserialize vault data
│       ├── SyncService.swift          # iCloud sync orchestration
│       ├── SearchService.swift        # Cross-project search
│       ├── ImportService.swift        # .env import with conflict resolution
│       ├── ExportService.swift        # .env export via NSSavePanel
│       ├── EnvParser.swift            # .env file parser and formatter
│       ├── LockManager.swift          # Auto-lock, sleep lock, activity tracking
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
│   │   ├── VaultExportView.swift      # Encrypted .envvault export
│   │   └── VaultImportView.swift      # Encrypted .envvault import
│   ├── Lock/
│   │   └── MasterPasswordUnlockView.swift  # Device auth unlock screen
│   ├── MainWindow/
│   │   ├── MainWindowView.swift       # NavigationSplitView root
│   │   └── SidebarView.swift          # Project/file tree
│   ├── MenuBar/
│   │   ├── MenuBarView.swift          # Quick-access popover
│   │   ├── SettingsView.swift         # Settings tabs
│   │   └── Subviews/QuickSearchView.swift
│   ├── Projects/Subviews/
│   │   ├── CreateProjectSheet.swift
│   │   └── EditProjectSheet.swift
│   └── EnvEditor/
│       ├── EnvEditorView.swift        # Entry list with Table/Raw toggle
│       ├── EnvEditorViewModel.swift   # Keychain ops, CRUD, copy
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

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Swift 6 |
| UI | SwiftUI |
| State | `@Observable` (Observation framework) |
| Data | SwiftData + CloudKit |
| Secrets | macOS Keychain (Security framework) |
| Crypto | CryptoKit + CommonCrypto |
| Auth | LocalAuthentication (Touch ID) |
| Target | macOS 15.6 |
| Dependencies | None (Apple frameworks only) |
