import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct MainWindowView: View {
    @Environment(LockManager.self) private var lockManager
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.updatedAt, order: .reverse) private var projects: [Project]
    @AppStorage(AppConfig.UserDefaultsKey.lastSelectedFileID) private var lastSelectedFileID = ""
    @State private var selectedFile: EnvFile?
    @State private var pendingSelectedFile: EnvFile?
    @State private var rawEditorHasUnappliedChanges = false
    @State private var showDiscardRawSelectionAlert = false
    @State private var expandedProjectIDs: Set<UUID> = []
    @State private var viewModel = EnvEditorViewModel()
    @State private var searchText = ""
    @State private var showImportSheet = false
    @State private var showCreateProjectSheet = false
    @State private var showCreateFileSheet: Project?
    @State private var fileToEdit: EnvFile?
    @State private var fileToDelete: EnvFile?
    @State private var droppedFileURL: URL?
    @State private var droppedTargetProject: Project?
    @State private var droppedTargetFile: EnvFile?
    @State private var droppedCreatesNewFile = true
    @State private var exportError: String?
    @State private var copyFeedback = false
    @State private var showErrorAlert = false
    @State private var showExportErrorAlert = false
    @State private var showVaultExport = false
    @State private var showVaultImport = false
    @State private var dismissedExportReminder = false

    private var shouldShowExportReminder: Bool {
        guard !dismissedExportReminder else { return false }
        guard projects.contains(where: { !($0.files ?? []).isEmpty }) else { return false }
        let lastExport = UserDefaults.standard.object(forKey: AppConfig.UserDefaultsKey.lastVaultExportDate) as? Date
        if let lastExport {
            return Date().timeIntervalSince(lastExport) > 30 * 24 * 60 * 60
        }
        UserDefaults.standard.set(Date(), forKey: AppConfig.UserDefaultsKey.lastVaultExportDate)
        return false
    }

    private var fileIDsByRecency: [UUID] {
        allFilesByRecency.map(\.id)
    }

    private var allFilesByRecency: [EnvFile] {
        projects
            .flatMap { $0.files ?? [] }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var conflictBinding: Binding<Bool> {
        Binding(
            get: {
                guard !isPresentingUserSheet else { return false }
                if case .conflict = syncCoordinator.state { return true }
                return false
            },
            set: { _ in }
        )
    }

    private var remoteDeletedBinding: Binding<Bool> {
        Binding(
            get: {
                guard !isPresentingUserSheet else { return false }
                if case .remoteDeleted = syncCoordinator.state { return true }
                return false
            },
            set: { _ in }
        )
    }

    private var isPresentingUserSheet: Bool {
        showImportSheet || showVaultExport || showVaultImport || showCreateProjectSheet || showCreateFileSheet != nil || fileToEdit != nil || fileToDelete != nil
    }

    private var selectedFileBinding: Binding<EnvFile?> {
        Binding(
            get: { selectedFile },
            set: { attemptSelectFile($0) }
        )
    }

    var body: some View {
        Group {
            if lockManager.isLocked {
                UnlockView {
                    lockManager.unlock()
                    viewModel.hideAllValues()
                }
            } else {
                mainContent
            }
        }
        .frame(
            minWidth: AppTheme.Sizing.windowMinWidth,
            minHeight: AppTheme.Sizing.windowMinHeight
        )
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            if shouldShowExportReminder {
                exportReminderBanner
            }
            mainNavigation
        }
    }

    private var mainNavigation: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailView
        }
        .searchable(text: $searchText, prompt: "Search keys...")
        .navigationTitle("Pocket Vault")
        .toolbar {
            mainToolbar
        }
        .overlay(alignment: .topLeading) {
            presentationHost
        }
    }

    private var presentationHost: some View {
        ZStack {
            alertHost
            sheetHost
            eventHost
        }
        .frame(width: 0, height: 0)
    }

    private var alertHost: some View {
        Color.clear
            .alert("Error", isPresented: $showErrorAlert, presenting: viewModel.errorMessage) { _ in
            Button("OK") { viewModel.errorMessage = nil }
        } message: { message in
            Text(message)
        }
        .alert("Export Error", isPresented: $showExportErrorAlert, presenting: exportError) { _ in
            Button("OK") { exportError = nil }
        } message: { message in
            Text(message)
        }
        .alert("Discard Raw Changes?", isPresented: $showDiscardRawSelectionAlert, presenting: pendingSelectedFile) { file in
            Button("Keep Editing", role: .cancel) { pendingSelectedFile = nil }
            Button("Discard Changes", role: .destructive) {
                rawEditorHasUnappliedChanges = false
                selectedFile = file
                pendingSelectedFile = nil
            }
        } message: { _ in
            Text("The raw editor has unapplied changes. Apply or revert them before switching files, or discard them now.")
        }
    }

    private var sheetHost: some View {
        Color.clear
        .onChange(of: viewModel.errorMessage) { _, newValue in
            if newValue != nil { showErrorAlert = true }
        }
        .onChange(of: exportError) { _, newValue in
            if newValue != nil { showExportErrorAlert = true }
        }
        .onChange(of: selectedFile) { _, _ in
            lockManager.recordActivity()
            syncSelectionState()
        }
        .onChange(of: searchText) { _, _ in
            lockManager.recordActivity()
        }
        .onChange(of: lastSelectedFileID) { _, _ in
            restoreSelectionIfNeeded(preferStoredSelection: true)
        }
        .onChange(of: fileIDsByRecency) { _, _ in
            restoreSelectionIfNeeded()
        }
        .sheet(isPresented: $showImportSheet) {
            ImportView(
                fileURL: droppedFileURL,
                preselectedProject: droppedTargetProject,
                preselectedFile: droppedTargetFile,
                createNewFile: droppedCreatesNewFile
            )
            .onDisappear { clearImportTarget() }
        }
        .sheet(isPresented: $showVaultExport) {
            VaultExportView()
        }
        .sheet(isPresented: $showVaultImport) {
            VaultImportView()
        }
        .sheet(isPresented: $showCreateProjectSheet) {
            CreateProjectSheet { file in
                selectedFile = file
            }
        }
        .sheet(item: $showCreateFileSheet) { project in
            CreateFileSheet(project: project) { file in
                selectedFile = file
            }
        }
        .sheet(item: $fileToEdit) { file in
            EditFileSheet(file: file)
        }
        .sheet(item: $fileToDelete) { file in
            ConfirmDeleteSheet(
                title: "Delete File",
                itemName: file.name,
                message: "This permanently deletes \"\(file.name)\" and all stored environment values in the file.",
                confirmButtonTitle: "Delete File"
            ) {
                deleteFile(file)
            }
        }
        .sheet(isPresented: conflictBinding) {
            if case .conflict(let local, let remote) = syncCoordinator.state {
                ConflictResolutionSheet(local: local, remote: remote) { useLocal in
                    await syncCoordinator.resolveConflict(useLocal: useLocal)
                }
            }
        }
        .sheet(isPresented: remoteDeletedBinding) {
            if case .remoteDeleted(_, let updatedAt, let deviceName) = syncCoordinator.state {
                RemoteDeletedSheet(
                    remoteUpdatedAt: updatedAt,
                    remoteUpdatedByDeviceName: deviceName,
                    localProjectCount: projects.count
                ) { keepLocal in
                    await syncCoordinator.resolveRemoteDeleted(keepLocal: keepLocal)
                }
            }
        }
    }

    private var eventHost: some View {
        Color.clear
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers, project: nil, file: nil, createNewFile: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pocketVaultNewProject)) { _ in
            showCreateProjectSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .pocketVaultNewFile)) { _ in
            if let project = selectedFile?.project ?? projects.first {
                showCreateFileSheet = project
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pocketVaultRenameFile)) { _ in
            if let selectedFile {
                fileToEdit = selectedFile
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pocketVaultDeleteFile)) { _ in
            if let selectedFile {
                fileToDelete = selectedFile
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pocketVaultImportEnvFile)) { _ in
            prepareImport(nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pocketVaultLock)) { _ in
            lockVault()
        }
        .onAppear {
            viewModel.lockManager = lockManager
            restoreSelectionIfNeeded()
        }
    }

    private var sidebarContent: some View {
        SidebarView(
            selectedFile: selectedFileBinding,
            expandedProjectIDs: $expandedProjectIDs,
            viewModel: viewModel,
            onImportFile: prepareImport
        )
        .navigationSplitViewColumnWidth(
            min: AppTheme.Sizing.sidebarMinWidth,
            ideal: AppTheme.Sizing.sidebarWidth,
            max: 300
        )
    }

    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            importMenu
            exportMenu
            Button {
                lockVault()
            } label: {
                Label("Lock", systemImage: "lock.fill")
            }
            .accessibilityLabel("Lock vault")
            .keyboardShortcut("l", modifiers: .command)
        }
    }

    private var importMenu: some View {
        Menu {
            Button("Import .env File...") { prepareImport(nil) }
                .keyboardShortcut("i", modifiers: .command)

            Divider()

            Button("Import Encrypted Backup...") {
                showVaultImport = true
            }
        } label: {
            Label("Import", systemImage: "square.and.arrow.down")
        }
        .accessibilityLabel("Import")
    }

    private var exportMenu: some View {
        Menu {
            if let file = selectedFile {
                Button("Export File...") {
                    exportFile(file)
                }
                .keyboardShortcut("e", modifiers: .command)
                if let project = file.project {
                    Button("Export Project Files...") {
                        exportProject(project)
                    }
                }
                Divider()
                Button(copyFeedback ? "Copied!" : "Copy File as KEY=VALUE") {
                    copyAll(file)
                }
                .disabled(copyFeedback)
            } else {
                Text("Select a file to export")
            }

            Divider()

            Button("Export Encrypted Backup...") {
                showVaultExport = true
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .accessibilityLabel("Export")
    }

    private var exportReminderBanner: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(AppTheme.warning)
            Text("You haven't exported an encrypted backup in over 30 days.")
                .font(AppTheme.Fonts.caption)
                .foregroundStyle(AppTheme.textSecondary)
            Spacer()
            Button("Export Now") { showVaultExport = true }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button {
                dismissedExportReminder = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppTheme.warning.opacity(0.1))
    }

    @ViewBuilder
    private var detailView: some View {
        if let file = selectedFile {
            DetailEditorView(
                file: file,
                viewModel: viewModel,
                searchText: searchText,
                rawEditorHasUnappliedChanges: $rawEditorHasUnappliedChanges,
                onRenameFile: { fileToEdit = file },
                onDeleteFile: {
                    fileToDelete = file
                }
            )
        } else if projects.isEmpty {
            VStack(spacing: AppTheme.Spacing.lg) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(AppTheme.accent)

                Text("Welcome to Pocket Vault")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text("Create your first project to start\nmanaging environment variables securely.")
                    .font(AppTheme.Fonts.body)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)

                Button("Create Project") {
                    showCreateProjectSheet = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyStateView(
                icon: "doc.text.fill",
                title: "No file selected",
                message: "Select a file from the sidebar\nto view its entries."
            )
        }
    }

    private func exportFile(_ file: EnvFile) {
        lockManager.recordActivity()
        let content = ExportService.exportFile(file)
        let panel = NSSavePanel()
        panel.title = "Export \(file.name)"
        panel.nameFieldStringValue = file.name
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            exportError = "Failed to export: \(error.localizedDescription)"
            showExportErrorAlert = true
        }
    }

    private func exportProject(_ project: Project) {
        lockManager.recordActivity()
        do {
            let files = try ExportService.exportProject(project)
            let panel = NSOpenPanel()
            panel.title = "Choose Export Location"
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.prompt = "Choose Folder"
            guard panel.runModal() == .OK, let parentDirectory = panel.url else { return }

            let exportDirectory = makeUniqueExportDirectory(for: project.name, in: parentDirectory)
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: false)

            for file in files {
                let fileURL = exportDirectory.appendingPathComponent(file.fileName)
                try file.content.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        } catch {
            exportError = "Failed to export: \(error.localizedDescription)"
            showExportErrorAlert = true
        }
    }

    private func makeUniqueExportDirectory(for projectName: String, in parentDirectory: URL) -> URL {
        let baseName = sanitizedExportDirectoryName(projectName)
        var candidate = parentDirectory.appendingPathComponent(baseName, isDirectory: true)
        var suffix = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parentDirectory.appendingPathComponent("\(baseName) \(suffix)", isDirectory: true)
            suffix += 1
        }

        return candidate
    }

    private func sanitizedExportDirectoryName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:")
        let cleanedName = name
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return cleanedName.isEmpty ? "Pocket Vault Export" : cleanedName
    }

    private func copyAll(_ file: EnvFile) {
        lockManager.recordActivity()
        let content = ExportService.copyAllEntries(file)
        ClipboardManager.shared.copyToClipboard(content)
        copyFeedback = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copyFeedback = false
        }
    }

    private func prepareImport(
        _ url: URL?,
        project: Project? = nil,
        file: EnvFile? = nil,
        createNewFile: Bool = true
    ) {
        droppedFileURL = url
        droppedTargetProject = project
        droppedTargetFile = file
        droppedCreatesNewFile = file == nil ? createNewFile : false
        showImportSheet = true
    }

    private func clearImportTarget() {
        droppedFileURL = nil
        droppedTargetProject = nil
        droppedTargetFile = nil
        droppedCreatesNewFile = true
    }

    private func handleDrop(
        _ providers: [NSItemProvider],
        project: Project?,
        file: EnvFile?,
        createNewFile: Bool
    ) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            Task { @MainActor in
                prepareImport(url, project: project, file: file, createNewFile: createNewFile)
            }
        }
        return true
    }

    private func deleteFile(_ file: EnvFile) {
        if selectedFile?.id == file.id {
            selectedFile = nil
        }
        do {
            try viewModel.deleteFile(file, context: modelContext)
        } catch {
            viewModel.errorMessage = "Failed to delete file: \(error.localizedDescription)"
        }
        fileToDelete = nil
    }

    private func lockVault() {
        viewModel.hideAllValues()
        lockManager.lock()
    }

    private func attemptSelectFile(_ file: EnvFile?) {
        guard rawEditorHasUnappliedChanges, selectedFile?.id != file?.id else {
            selectedFile = file
            return
        }

        pendingSelectedFile = file
        showDiscardRawSelectionAlert = true
    }

    private func syncSelectionState() {
        guard let selectedFile else {
            lastSelectedFileID = ""
            rawEditorHasUnappliedChanges = false
            return
        }

        lastSelectedFileID = selectedFile.id.uuidString
        if let projectID = selectedFile.project?.id {
            expandedProjectIDs.insert(projectID)
        }
    }

    private func restoreSelectionIfNeeded(preferStoredSelection: Bool = false) {
        guard !allFilesByRecency.isEmpty else {
            selectedFile = nil
            expandedProjectIDs.removeAll()
            lastSelectedFileID = ""
            rawEditorHasUnappliedChanges = false
            return
        }

        if preferStoredSelection,
           let restoredFile = allFilesByRecency.first(where: { $0.id.uuidString == lastSelectedFileID }) {
            restoreSelection(restoredFile)
            return
        }

        if let selectedFile,
           allFilesByRecency.contains(where: { $0.id == selectedFile.id }) {
            if let projectID = selectedFile.project?.id {
                expandedProjectIDs.insert(projectID)
            }
            return
        }

        if let restoredFile = allFilesByRecency.first(where: { $0.id.uuidString == lastSelectedFileID }) {
            restoreSelection(restoredFile)
            return
        }

        if let firstFile = allFilesByRecency.first {
            restoreSelection(firstFile)
        }
    }

    private func restoreSelection(_ file: EnvFile) {
        attemptSelectFile(file)
        if selectedFile?.id == file.id, let projectID = file.project?.id {
            expandedProjectIDs.insert(projectID)
        }
    }
}

private enum ViewMode: String, CaseIterable {
    case table = "Table"
    case raw = "Raw"

    var label: some View {
        switch self {
        case .table: Text("Table")
        case .raw: Text("Raw")
        }
    }
}

private struct DetailEditorView: View {
    @Bindable var file: EnvFile
    @Bindable var viewModel: EnvEditorViewModel
    @Environment(\.modelContext) private var modelContext
    let searchText: String
    @Binding var rawEditorHasUnappliedChanges: Bool
    let onRenameFile: () -> Void
    let onDeleteFile: () -> Void

    @State private var showAddSheet = false
    @State private var entryToEdit: EnvEntry?
    @State private var entryToDelete: EnvEntry?
    @State private var showDeleteEntryAlert = false
    @State private var viewMode: ViewMode = .table
    @State private var pendingViewMode: ViewMode?
    @State private var showDiscardRawModeAlert = false
    @State private var rawText = ""
    @State private var rawTextSnapshot = ""
    @State private var rawErrorMessage: String?

    private var sortedEntries: [EnvEntry] {
        let entries = (file.entries ?? []).sorted { $0.sortOrder < $1.sortOrder }
        if searchText.isEmpty { return entries }
        return entries.filter { $0.key.localizedCaseInsensitiveContains(searchText) }
    }

    private var duplicateKeys: Set<String> {
        viewModel.duplicateKeys(in: file)
    }

    private var hasRawChanges: Bool {
        rawText != rawTextSnapshot
    }

    private var viewModeBinding: Binding<ViewMode> {
        Binding(
            get: { viewMode },
            set: { attemptChangeViewMode($0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            switch viewMode {
            case .table:
                tableContent
            case .raw:
                rawEditorView
            }
            Divider()
            footerView
        }
        .sheet(isPresented: $showAddSheet) {
            AddEntrySheet(file: file, viewModel: viewModel)
        }
        .sheet(item: $entryToEdit) { entry in
            EditEntrySheet(entry: entry, viewModel: viewModel)
        }
        .alert("Delete Entry", isPresented: $showDeleteEntryAlert, presenting: entryToDelete) { entry in
            Button("Cancel", role: .cancel) { entryToDelete = nil }
            Button("Delete", role: .destructive) {
                viewModel.deleteEntry(entry, context: modelContext)
                entryToDelete = nil
            }
        } message: { entry in
            Text("Delete \"\(entry.key)\"? The stored value will be permanently removed.")
        }
        .alert("Discard Raw Changes?", isPresented: $showDiscardRawModeAlert, presenting: pendingViewMode) { mode in
            Button("Keep Editing", role: .cancel) { pendingViewMode = nil }
            Button("Discard Changes", role: .destructive) {
                rawText = rawTextSnapshot
                rawErrorMessage = nil
                rawEditorHasUnappliedChanges = false
                viewMode = mode
                pendingViewMode = nil
            }
        } message: { _ in
            Text("The raw editor has unapplied changes. Apply or revert them before switching views, or discard them now.")
        }
        .onChange(of: file) {
            viewModel.hideAllValues()
            if viewMode == .raw { loadRawText() }
        }
        .onChange(of: viewMode) {
            viewModel.lockManager?.recordActivity()
            if viewMode == .raw { loadRawText() }
        }
    }

    @ViewBuilder
    private var tableContent: some View {
        if (file.entries ?? []).isEmpty {
            EmptyStateView(
                icon: "key.fill",
                title: "No entries yet",
                message: "Add your first environment\nvariable to this file.",
                buttonTitle: "Add Entry",
                action: { showAddSheet = true }
            )
        } else if sortedEntries.isEmpty {
            VStack(spacing: AppTheme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24))
                    .foregroundStyle(AppTheme.textTertiary)
                Text("No matching entries")
                    .font(AppTheme.Fonts.body)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            entryList
        }
    }

    private var headerView: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.accent)

            Text(file.name)
                .font(AppTheme.Fonts.title)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)

            if let projectName = file.project?.name {
                Text(projectName)
                    .font(AppTheme.Fonts.caption)
                    .foregroundStyle(AppTheme.textTertiary)
            }

            Spacer()

            Button(action: onRenameFile) {
                Label("Rename File", systemImage: "pencil")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Rename file")

            Button(role: .destructive, action: onDeleteFile) {
                Label("Delete File", systemImage: "trash")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Delete file")

            Picker("View", selection: viewModeBinding) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    mode.label.tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 120)

            if viewMode == .table {
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Entry", systemImage: "plus")
                        .font(AppTheme.Fonts.button)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.md)
    }

    private var rawEditorView: some View {
        VStack(spacing: 0) {
            TextEditor(text: $rawText)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(AppTheme.Spacing.sm)
                .onChange(of: rawText) { _, _ in
                    viewModel.lockManager?.recordActivity()
                    rawEditorHasUnappliedChanges = hasRawChanges
                    rawErrorMessage = nil
                }

            if hasRawChanges || rawErrorMessage != nil {
                HStack {
                    Text(rawErrorMessage ?? "Unsaved changes")
                        .font(AppTheme.Fonts.caption)
                        .foregroundStyle(rawErrorMessage == nil ? AppTheme.warning : AppTheme.error)
                        .lineLimit(2)
                    Spacer()
                    Button("Revert") {
                        rawText = rawTextSnapshot
                        rawErrorMessage = nil
                        rawEditorHasUnappliedChanges = false
                    }
                        .buttonStyle(.bordered)
                    Button("Apply") { applyRawChanges() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!hasRawChanges)
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.sm)
            }
        }
    }

    private func loadRawText() {
        do {
            let text = try viewModel.rawText(for: file)
            rawText = text
            rawTextSnapshot = text
            rawErrorMessage = nil
            rawEditorHasUnappliedChanges = false
        } catch {
            viewModel.errorMessage = "Failed to load raw text: \(error.localizedDescription)"
        }
    }

    private func applyRawChanges() {
        let result = EnvParser.parse(rawText)
        if !result.errors.isEmpty {
            rawErrorMessage = result.errors.map { "Line \($0.lineNumber): \($0.message)" }.joined(separator: "\n")
            return
        }

        if viewModel.applyRawText(rawText, to: file, context: modelContext) {
            loadRawText()
        }
    }

    private func attemptChangeViewMode(_ mode: ViewMode) {
        guard viewMode != mode else { return }
        guard viewMode == .raw, hasRawChanges else {
            viewMode = mode
            return
        }

        pendingViewMode = mode
        showDiscardRawModeAlert = true
    }

    private var entryList: some View {
        List {
            ForEach(sortedEntries) { entry in
                EnvEntryRow(
                    entry: entry,
                    revealedValue: viewModel.revealedValue(for: entry),
                    onRevealToggle: { viewModel.toggleReveal(for: entry) },
                    onCopy: { viewModel.copyValue(for: entry) },
                    onCopyKey: { viewModel.copyKey(for: entry) },
                    onEdit: { entryToEdit = entry }
                )
                .listRowInsets(EdgeInsets(
                    top: 0,
                    leading: AppTheme.Spacing.sm,
                    bottom: 0,
                    trailing: AppTheme.Spacing.sm
                ))
                .listRowSeparator(.hidden)
                .overlay(alignment: .topTrailing) {
                    if !entry.isComment && duplicateKeys.contains(entry.key) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(AppTheme.warning)
                            .help("Duplicate key")
                            .padding(AppTheme.Spacing.xs)
                    }
                }
                .contextMenu {
                    if !entry.isComment {
                        Button("Copy Value") { viewModel.copyValue(for: entry) }
                        Button("Copy Key") { viewModel.copyKey(for: entry) }
                        Button("Copy as KEY=VALUE") { viewModel.copyKeyValue(for: entry) }
                        Button(viewModel.revealedValue(for: entry) != nil ? "Hide Value" : "Reveal Value") {
                            viewModel.toggleReveal(for: entry)
                        }
                        Divider()
                        Button("Edit") { entryToEdit = entry }
                        Divider()
                        Button("Delete", role: .destructive) {
                            entryToDelete = entry
                            showDeleteEntryAlert = true
                        }
                    }
                }
                .onTapGesture(count: 2) {
                    guard !entry.isComment else { return }
                    entryToEdit = entry
                }
            }
            .onMove { source, destination in
                viewModel.moveEntries(in: file, from: source, to: destination, context: modelContext)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var footerView: some View {
        HStack {
            Text("\((file.entries ?? []).count) \((file.entries ?? []).count == 1 ? "entry" : "entries")")
                .font(AppTheme.Fonts.caption)
                .foregroundStyle(AppTheme.textTertiary)

            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.sm)
    }
}
