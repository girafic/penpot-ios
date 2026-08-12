import SwiftUI

/// A team's shared libraries (`get-team-shared-files`) as file cards. Tapping one opens it;
/// long-press for rename / duplicate / download (.penpot) / unpublish.
struct LibrariesView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    let team: Team

    @State private var libraries: [FileListItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var renameTarget: FileListItem?
    @State private var renameText = ""
    @State private var unpublishTarget: FileListItem?
    @State private var actionError: String?
    @State private var isExporting = false
    @State private var exportedDocument: ExportedDocument?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        content
            .navigationTitle("Libraries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    FilesLayoutToggle()
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .alert("Rename File", isPresented: renameAlert, presenting: renameTarget) { file in
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") { Task { await rename(file) } }
            }
            .alert("Unpublish Library", isPresented: unpublishDialog, presenting: unpublishTarget) { file in
                Button("Unpublish", role: .destructive) { Task { await unpublish(file) } }
                Button("Cancel", role: .cancel) {}
            } message: { file in
                Text("“\(file.name)” will stop being a shared library.")
            }
            .alert("Something went wrong", isPresented: actionErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actionError ?? "")
            }
            .fileExportPresentation(isExporting: $isExporting, document: $exportedDocument)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && libraries.isEmpty {
            LoadingView(message: "Loading libraries…")
        } else if let errorMessage, libraries.isEmpty {
            ErrorStateView(message: errorMessage) { Task { await load() } }
        } else if libraries.isEmpty {
            EmptyStateView(title: "No shared libraries", icon: .library,
                           description: "Shared libraries for this team will appear here.")
        } else {
            ScrollView {
                switch settings.filesLayout {
                case .grid:
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(libraries) { file in
                            NavigationLink {
                                FileViewerView(file: file)
                            } label: {
                                FileCardView(file: file, baseURL: appState.client?.baseURL)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { libraryMenu(file) }
                        }
                    }
                    .padding()
                case .list:
                    LazyVStack(spacing: 12) {
                        ForEach(libraries) { file in
                            NavigationLink {
                                FileViewerView(file: file)
                            } label: {
                                FileRowView(file: file, baseURL: appState.client?.baseURL)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { libraryMenu(file) }
                            .penpotSwipeActions(id: file.id) {
                                PenpotSwipeAction("Unpublish Library", icon: .unpublish, isDestructive: true) {
                                    unpublishTarget = file
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
        }
    }

    @ViewBuilder
    private func libraryMenu(_ file: FileListItem) -> some View {
        Button { startRename(file) } label: { AppIcon.edit.label("Rename") }
        Button { Task { await duplicate(file) } } label: { AppIcon.duplicate.label("Duplicate") }
        Button { Task { await download(file) } } label: {
            AppIcon.download.label("Download Penpot file (.penpot)")
        }
        Button(role: .destructive) { unpublishTarget = file } label: {
            AppIcon.unpublish.label("Unpublish Library")
        }
    }

    private var renameAlert: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }
    private var unpublishDialog: Binding<Bool> {
        Binding(get: { unpublishTarget != nil }, set: { if !$0 { unpublishTarget = nil } })
    }
    private var actionErrorAlert: Binding<Bool> {
        Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
    }

    private func startRename(_ file: FileListItem) {
        renameText = file.name
        renameTarget = file
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        errorMessage = nil
        do {
            libraries = try await client.sharedLibraries(teamID: team.id)
        } catch {
            if case PenpotError.unauthorized = error {
                appState.logout()
            } else {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        isLoading = false
    }

    private func rename(_ file: FileListItem) async {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard let client = appState.client, !name.isEmpty else { return }
        do {
            try await client.renameFile(id: file.id, name: name)
            await load()
        } catch { handleActionError(error) }
    }

    /// Duplicating a shared library makes a plain (non-shared) copy in the library's project,
    /// so it won't reappear in this list — matching Penpot's web behavior.
    private func duplicate(_ file: FileListItem) async {
        guard let client = appState.client else { return }
        do {
            try await client.duplicateFile(id: file.id)
            await load()
        } catch { handleActionError(error) }
    }

    private func unpublish(_ file: FileListItem) async {
        guard let client = appState.client else { return }
        do {
            try await client.setFileShared(id: file.id, isShared: false)
            await load()
        } catch { handleActionError(error) }
    }

    private func download(_ file: FileListItem) async {
        guard let client = appState.client else { return }
        isExporting = true
        defer { isExporting = false }
        do {
            let data = try await client.exportBinfile(fileID: file.id)
            exportedDocument = try ExportedDocument.penpot(data: data, name: file.name)
        } catch { handleActionError(error) }
    }

    private func handleActionError(_ error: Error) {
        if case PenpotError.unauthorized = error {
            appState.logout()
        } else {
            actionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
