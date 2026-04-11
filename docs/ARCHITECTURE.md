# Architecture

How the app works internally. How the pieces connect.

---

## Overview

Pocket Vault is a menu bar app with two user-facing interfaces sharing the same data layer:

```
PocketVaultApp (@main)
├── MenuBarExtra(.window)          Quick-access popover (browse, copy, search)
├── Window("Pocket Vault")         Full editor (CRUD, import, export, sheets)
└── Settings                       Preferences (Cmd+,)

Shared across all scenes:
  DataManager        SwiftData ModelContainer (singleton)
  LockManager        Lock state, auto-lock timer, sleep detection
  BiometricService   Touch ID / device auth
  SyncService        iCloud sync status and migration
```

The popover is read-only (no editing, no sheets, no create/delete). All mutations happen in the main window. The popover has a "Manage" button that opens the main window.

---

## Data Flow

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
│  SwiftData   │     │   Keychain    │     │  UserDefaults    │
│              │     │               │     │                  │
│  Project     │     │  Secret       │     │  Settings        │
│  EnvFile     │     │  values       │     │  (auto-lock,     │
│  EnvEntry    │     │  (per-entry)  │     │   sync toggle,   │
│  (metadata)  │     │               │     │   biometric       │
│              │     │               │     │   state, etc.)    │
└──────┬───────┘     └──────┬───────┘     └────────┬─────────┘
       │                     │                      │
       │    ┌────────────────┴──────────────┐       │
       └────┤      EnvEditorViewModel       ├───────┘
            │                               │
            │  Reads metadata from SwiftData │
            │  Reads/writes values to        │
            │    Keychain via keychainId     │
            │  Tracks revealed state         │
            │  Handles copy, CRUD            │
            └───────────────────────────────┘
```

### What Goes Where

| Data | Storage | Why |
|------|---------|-----|
| Project name, description | SwiftData | Queryable metadata |
| File name, project reference | SwiftData | Queryable metadata |
| Entry key, sortOrder, isComment | SwiftData | Searchable metadata |
| **Entry value (the secret)** | **Keychain** | Hardware-encrypted at rest |
| Settings (timeouts, toggles) | UserDefaults | Simple key-value prefs |
| Biometric domain state | UserDefaults | Enrollment change detection |

Secret values never touch SwiftData, UserDefaults, or any file on disk. The only way a value leaves the Keychain is when the user copies it to the clipboard (auto-cleared) or exports an `.envvault` file (encrypted).

---

## Models

Three SwiftData `@Model` classes with a flat hierarchy: `Project -> EnvFile -> EnvEntry`.

```
Project
  ├── name: String
  ├── projectDescription: String?
  ├── createdAt: Date
  └── files: [EnvFile]?              CloudKit requires optional relationships

EnvFile
  ├── name: String
  ├── project: Project?
  └── entries: [EnvEntry]?           CloudKit requires optional relationships

EnvEntry
  ├── key: String
  ├── keychainIdentifier: String     "pocketvault-{UUID}" — generated once, never changes
  ├── sortOrder: Int
  ├── isComment: Bool
  ├── comment: String?
  └── file: EnvFile?
```

The `keychainIdentifier` is derived from the entry's SwiftData `id` at creation time. It's the Keychain account name used to store/retrieve the secret value. Renaming a key does not change the identifier.

---

## Two Interfaces

### Menu Bar Popover

`MenuBarExtra("Pocket Vault", image: "StatusBarIcon")` with `.menuBarExtraStyle(.window)`.

Read-only drill-down: Projects -> Files -> Entries. Each entry shows the key, a masked value, reveal toggle, and copy button. Search bar at the top. "Manage" button opens the main window. Lock button locks the app.

No sheets, no editing, no create/delete. This is intentional — `MenuBarExtra(.window)` dismisses when a `.sheet()` is presented (macOS limitation).

### Main Window

`Window("Pocket Vault", id: "main")` with `NavigationSplitView`.

Sidebar shows the project/file tree. Detail pane shows the entry editor for the selected file. All CRUD happens here via sheets. Supports Table View (structured rows) and Raw View (editable `.env` text).

### Activation Policy

When no window is open, the app runs as `LSUIElement` (no Dock icon, no Cmd+Tab). When the main window opens, `AppDelegate` switches to `.regular` (shows in Dock). When it closes, back to `.accessory`.

```swift
// AppDelegate.swift
func showMainWindow() {
    NSApp.setActivationPolicy(.regular)    // Show in Dock
    NSApp.activate()
}

func hideFromDock() {
    // Only hide if no visible windows remain
    NSApp.setActivationPolicy(.accessory)  // Hide from Dock
}
```

---

## Security

### Authentication

Device-only auth via `LAContext.evaluatePolicy(.deviceOwnerAuthentication)`. This triggers Touch ID with macOS password fallback — the same model as Apple Passwords and 2FAS. No separate master password.

The app starts locked on every launch. `LockManager` handles:
- Auto-lock after configurable inactivity (default 5 min)
- Lock on system sleep and screen sleep
- Manual lock via button or Cmd+L
- `recordActivity()` called from all user interactions to reset the timer

### Keychain

Service name: `app.pocketvault.keychain`
Account format: `pocketvault-{UUID}`

Each `EnvEntry` has a unique `keychainIdentifier`. `KeychainService` provides CRUD operations against the Security framework. Values are AES-256 encrypted at rest by the OS (hardware-backed on Apple Silicon).

### Encrypted Export (.envvault)

For portable backups. Uses `CryptoService`:
1. User enters a password
2. PBKDF2-HMAC-SHA256 (260K iterations, 16-byte random salt) derives a 256-bit key
3. AES-256-GCM encrypts the JSON payload
4. Binary format: `PVLT` magic + version + salt + iterations + sealed data

`VaultService` serializes all projects/files/entries (pulling values from Keychain) into a `VaultData` JSON structure, then `CryptoService` encrypts it.

---

## iCloud Sync

Opt-in. Two parallel sync channels:

1. **SwiftData + CloudKit** syncs metadata (projects, files, entry keys/sort orders)
2. **iCloud Keychain** syncs secret values (end-to-end encrypted by Apple)

This keeps secrets out of the CloudKit database entirely.

### How It Works

- `DataManager` reads the `cloudKitSyncEnabled` UserDefaults flag at init
- If enabled, configures `ModelConfiguration` with CloudKit container `iCloud.app.pocketvault`
- Toggling sync requires app restart (ModelContainer can't be reconfigured at runtime)
- `SyncService` handles Keychain migration (local-only <-> syncable) and conflict resolution
- Conflicts: duplicate project names get `_conflict_<timestamp>` suffix

### Keychain Migration

When sync is toggled:
- **On**: Reads each `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` item, writes a new syncable copy, deletes the old one
- **Off**: Reverse migration back to local-only
- Progress tracked in UserDefaults for crash recovery

---

## Import / Export

### .env Import

```
User picks .env file -> EnvParser parses KEY=VALUE lines -> ImportView shows preview
  -> User selects target project/file, conflict resolution (skip/overwrite/rename)
  -> ImportService writes to SwiftData + Keychain
```

`EnvParser` handles: `KEY=VALUE`, quoted values, comments, empty lines, multiline, `export` prefix, inline comments.

### .env Export

`ExportService` reads entries from SwiftData, pulls values from Keychain, formats via `EnvParser.format()`, writes via `NSSavePanel`. Can export a single file or an entire project.

### .envvault Export/Import

Full vault backup. `VaultService.exportAll()` serializes everything, `CryptoService` encrypts. Import is the reverse: decrypt, deserialize, write to SwiftData + Keychain.

---

## Service Dependency Graph

```
PocketVaultApp
  ├── LockManager              Standalone. Tracks lock state + timers.
  ├── BiometricService          Standalone. Wraps LAContext.
  ├── SyncService               Uses DataManager, KeychainService.
  └── DataManager (singleton)   Owns ModelContainer.

EnvEditorViewModel
  ├── KeychainService           Read/write secret values.
  ├── LockManager               recordActivity() on interactions.
  └── SwiftData ModelContext     CRUD for entries.

ImportService
  ├── EnvParser                 Parse .env content.
  ├── KeychainService           Write imported values.
  └── SwiftData ModelContext     Write imported entries.

ExportService
  ├── EnvParser                 Format entries to .env text.
  ├── KeychainService           Read values for export.
  └── NSSavePanel               File save dialog.

VaultService
  ├── KeychainService           Read all values for export, write on import.
  └── SwiftData ModelContext     Read/write all models.

CryptoService                   Standalone. PBKDF2 + AES-256-GCM.

ClipboardManager                Standalone singleton. Auto-clear NSPasteboard.

SearchService                   Uses SwiftData queries only. Never searches values.
```

---

## Build Settings

| Setting | Value |
|---------|-------|
| `SWIFT_DEFAULT_ACTOR_ISOLATION` | `MainActor` |
| `SWIFT_APPROACHABLE_CONCURRENCY` | `YES` |
| `INFOPLIST_KEY_LSUIElement` | `YES` |
| Bundle ID | `app.pocketvault` |
| iCloud Container | `iCloud.app.pocketvault` |
| Target | macOS 15.6 |
| Swift | 6 |
| Dependencies | Zero third-party |

The project uses `PBXFileSystemSynchronizedRootGroup` — files in `pocketvault/` are auto-discovered by Xcode. No manual "Add to project" step needed.
