import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Project.name) private var projects: [Project]

    @State private var parseResult: ParseResult?
    @State private var selectedProject: Project?
    @State private var selectedFile: EnvFile?
    @State private var createNewFile = true
    @State private var newFileName = ""
    @State private var conflictResolution: ImportConflictResolution = .skip
    @State private var importResult: ImportResult?
    @State private var errorMessage: String?
    @State private var selectedEntries: Set<UUID> = []

    let initialFileURL: URL?

    init(fileURL: URL? = nil) {
        self.initialFileURL = fileURL
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            if let result = parseResult {
                importConfigView(result)
            } else {
                filePickerPrompt
            }
            Divider()
            footerView
        }
        .frame(width: 560, height: 520)
        .task {
            if let url = initialFileURL {
                loadFile(at: url)
            }
        }
    }

    private var headerView: some View {
        HStack {
            Text("Import .env File")
                .font(.headline)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    private var filePickerPrompt: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.textTertiary)
            Text("Choose a .env file to import")
                .font(.body)
                .foregroundStyle(AppTheme.textSecondary)
            Button("Choose File...") {
                pickFile()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func importConfigView(_ result: ParseResult) -> some View {
        VStack(spacing: 0) {
            targetSelector
            Divider()
            ImportPreviewView(
                entries: result.entries,
                errors: result.errors,
                selectedEntries: $selectedEntries
            )
        }
    }

    private var targetSelector: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Import into:")
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)

            HStack(spacing: AppTheme.Spacing.md) {
                Picker("Project", selection: $selectedProject) {
                    Text("Select project...").tag(nil as Project?)
                    ForEach(projects) { project in
                        Text(project.name).tag(project as Project?)
                    }
                }
                .frame(maxWidth: 200)

                if let project = selectedProject {
                    Toggle("New file", isOn: $createNewFile)

                    if createNewFile {
                        TextField("File name", text: $newFileName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 160)
                    } else {
                        Picker("File", selection: $selectedFile) {
                            Text("Select file...").tag(nil as EnvFile?)
                            ForEach((project.files ?? []).sorted(by: { $0.name < $1.name })) { file in
                                Text(file.name).tag(file as EnvFile?)
                            }
                        }
                        .frame(maxWidth: 160)
                    }
                }
            }

            if !createNewFile && selectedFile != nil {
                Picker("Conflicts:", selection: $conflictResolution) {
                    Text("Skip existing").tag(ImportConflictResolution.skip)
                    Text("Overwrite").tag(ImportConflictResolution.overwrite)
                    Text("Rename").tag(ImportConflictResolution.rename)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
            }
        }
        .padding()
    }

    private var footerView: some View {
        HStack {
            if let result = importResult {
                Text("Imported \(result.imported), skipped \(result.skipped)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            } else if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(AppTheme.error)
            }

            Spacer()

            if importResult != nil {
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            } else if parseResult != nil {
                Button("Choose Different File...") {
                    pickFile()
                }

                Button("Import") {
                    performImport()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canImport)
            }
        }
        .padding()
    }

    private var canImport: Bool {
        guard selectedProject != nil else { return false }
        guard parseResult != nil else { return false }
        if createNewFile {
            return !newFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return selectedFile != nil
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose .env File"
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFile(at: url)
    }

    private func loadFile(at url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let result = EnvParser.parse(content)
            parseResult = result
            selectedEntries = Set(result.entries.map(\.id))
            if newFileName.isEmpty {
                newFileName = url.lastPathComponent
            }
        } catch {
            errorMessage = "Failed to read file: \(error.localizedDescription)"
        }
    }

    private func performImport() {
        guard let project = selectedProject, let parsed = parseResult else { return }

        let targetFile: EnvFile
        if createNewFile {
            let file = EnvFile(name: newFileName.trimmingCharacters(in: .whitespacesAndNewlines))
            file.project = project
            modelContext.insert(file)
            targetFile = file
        } else {
            guard let file = selectedFile else { return }
            targetFile = file
        }

        let entriesToImport = parsed.entries.filter { selectedEntries.contains($0.id) }

        do {
            let result = try ImportService.importEntries(
                entriesToImport,
                into: targetFile,
                conflictResolution: conflictResolution,
                context: modelContext
            )
            importResult = result
            errorMessage = result.errors.isEmpty ? nil : result.errors.first
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}

struct ImportPreviewView: View {
    let entries: [ParsedEntry]
    let errors: [ParseError]
    @Binding var selectedEntries: Set<UUID>

    var body: some View {
        List {
            if !errors.isEmpty {
                Section("Warnings") {
                    ForEach(errors) { error in
                        HStack(spacing: AppTheme.Spacing.sm) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(AppTheme.warning)
                                .font(.caption)
                            Text("Line \(error.lineNumber): \(error.message)")
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                }
            }

            Section("Entries (\(entries.filter { !$0.isComment }.count))") {
                ForEach(entries.filter { !$0.isComment }) { entry in
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Toggle("", isOn: Binding(
                            get: { selectedEntries.contains(entry.id) },
                            set: { selected in
                                if selected {
                                    selectedEntries.insert(entry.id)
                                } else {
                                    selectedEntries.remove(entry.id)
                                }
                            }
                        ))
                        .labelsHidden()

                        Text(entry.key)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(1)

                        Text("=")
                            .foregroundStyle(AppTheme.textTertiary)

                        Text(maskedValue(entry.value))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)

                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func maskedValue(_ value: String) -> String {
        if value.isEmpty { return "(empty)" }
        let prefix = String(value.prefix(3))
        return prefix + String(repeating: "\u{2022}", count: min(value.count - 3, 12).clamped(to: 0...12))
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
