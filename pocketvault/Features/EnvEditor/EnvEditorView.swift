import SwiftUI
import SwiftData

struct EnvEditorView: View {
    @Bindable var file: EnvFile
    @Bindable var viewModel: EnvEditorViewModel
    @Environment(\.modelContext) private var modelContext
    let onBack: () -> Void

    @State private var showAddSheet = false
    @State private var entryToEdit: EnvEntry?
    @State private var entryToDelete: EnvEntry?
    @State private var showDeleteEntryAlert = false

    private var sortedEntries: [EnvEntry] {
        (file.entries ?? []).sorted { $0.sortOrder < $1.sortOrder }
    }

    private var duplicateKeys: Set<String> {
        viewModel.duplicateKeys(in: file)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            if sortedEntries.isEmpty {
                EmptyStateView(
                    icon: "key.fill",
                    title: "No entries yet",
                    message: "Add your first environment\nvariable to this file.",
                    buttonTitle: "Add Entry",
                    action: { showAddSheet = true }
                )
            } else {
                entryList
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
    }

    private var headerView: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Button {
                viewModel.hideAllValues()
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(.plain)
            .help("Back to files")

            Text(file.name)
                .font(AppTheme.Fonts.title)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.popoverPadding)
        .padding(.vertical, AppTheme.Spacing.sm)
    }

    private var entryList: some View {
        List {
            ForEach(sortedEntries) { entry in
                EnvEntryRow(
                    entry: entry,
                    revealedValue: viewModel.revealedValue(for: entry),
                    onRevealToggle: { viewModel.toggleReveal(for: entry) },
                    onCopy: { viewModel.copyValue(for: entry) },
                    onCopyKey: { viewModel.copyKey(for: entry) }
                )
                .listRowInsets(EdgeInsets(
                    top: 0,
                    leading: AppTheme.Spacing.xs,
                    bottom: 0,
                    trailing: AppTheme.Spacing.xs
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
            Button {
                showAddSheet = true
            } label: {
                Label("Add Entry", systemImage: "plus")
                    .font(AppTheme.Fonts.button)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.accent)

            Spacer()
        }
        .padding(AppTheme.Spacing.popoverPadding)
    }
}
