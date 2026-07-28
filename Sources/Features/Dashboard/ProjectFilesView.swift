import SwiftUI

/// A single project's files as a grid of cards. Shared by the Projects drill-down, the Drafts
/// shortcut, and each pinned project. Create files, or long-press to rename / duplicate / publish
/// as a shared library / download (.penpot) / move / delete one.
struct ProjectFilesView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppSettings.self) private var settings
    let project: Project

    @State private var files: [FileListItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var showingCreate = false
    @State private var newName = ""
    @State private var fileToDelete: FileListItem?
    @State private var renameTarget: FileListItem?
    @State private var renameText = ""
    @State private var moveTarget: FileListItem?
    @State private var unpublishTarget: FileListItem?
    @State private var isExporting = false
    @State private var exportedDocument: ExportedDocument?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    /// Localizes "Drafts" via the String Catalog; user-named projects stay verbatim.
    private var title: String {
        project.isDefaultProject ? .appLocalized("Drafts") : project.name
    }

    var body: some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    FilesLayoutToggle()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newName = ""; showingCreate = true } label: { AppIcon.add.image }
                        .accessibilityLabel("New File")
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .alert("New File", isPresented: $showingCreate) {
                TextField("File name", text: $newName)
                Button("Cancel", role: .cancel) {}
                Button("Create") { Task { await createFile() } }
            } message: {
                Text("Enter a name for the new file.")
            }
            .alert("Rename File", isPresented: renameAlert, presenting: renameTarget) { file in
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") { Task { await rename(file) } }
            }
            .confirmationDialog("Delete File", isPresented: deleteDialog, presenting: fileToDelete) { file in
                Button("Delete", role: .destructive) { Task { await delete(file) } }
                Button("Cancel", role: .cancel) {}
            } message: { file in
                Text("“\(file.name)” will be moved to the trash.")
            }
            .alert("Unpublish Library", isPresented: unpublishDialog, presenting: unpublishTarget) { file in
                Button("Unpublish", role: .destructive) { Task { await unpublish(file) } }
                Button("Cancel", role: .cancel) {}
            } message: { file in
                Text("“\(file.name)” will stop being a shared library.")
            }
            .sheet(item: $moveTarget) { file in
                MoveSheet(
                    title: "Move to Project",
                    load: { try await projectTargets() },
                    onSelect: { target in try await move(file, toProjectID: target.id) })
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
        if isLoading && files.isEmpty {
            LoadingView(message: "Loading files…")
        } else if let errorMessage, files.isEmpty {
            ErrorStateView(message: errorMessage) { Task { await load() } }
        } else if files.isEmpty {
            EmptyStateView(title: "No files", icon: .document,
                           description: "This project has no files yet.")
        } else {
            ScrollView {
                switch settings.filesLayout {
                case .grid:
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(files) { file in
                            NavigationLink {
                                FileViewerView(file: file)
                            } label: {
                                FileCardView(file: file, baseURL: appState.client?.baseURL)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { fileMenu(file) }
                        }
                    }
                    .padding()
                case .list:
                    LazyVStack(spacing: 12) {
                        ForEach(files) { file in
                            NavigationLink {
                                FileViewerView(file: file)
                            } label: {
                                FileRowView(file: file, baseURL: appState.client?.baseURL)
                            }
                            .buttonStyle(.plain)
                            .contextMenu { fileMenu(file) }
                        }
                    }
                    .padding()
                }
            }
        }
    }

    @ViewBuilder
    private func fileMenu(_ file: FileListItem) -> some View {
        Button { startRename(file) } label: { AppIcon.edit.label("Rename") }
        Button { Task { await duplicate(file) } } label: { AppIcon.duplicate.label("Duplicate") }
        if file.isShared == true {
            Button(role: .destructive) { unpublishTarget = file } label: {
                AppIcon.unpublish.label("Unpublish Library")
            }
        } else {
            Button { Task { await publish(file) } } label: {
                AppIcon.library.label("Add as Shared Library")
            }
        }
        Button { Task { await download(file) } } label: {
            AppIcon.download.label("Download Penpot file (.penpot)")
        }
        Button { moveTarget = file } label: { AppIcon.folder.label("Move to Project") }
        Button(role: .destructive) { fileToDelete = file } label: {
            AppIcon.delete.destructiveLabel("Delete")
        }
    }

    private var deleteDialog: Binding<Bool> {
        Binding(get: { fileToDelete != nil }, set: { if !$0 { fileToDelete = nil } })
    }
    private var unpublishDialog: Binding<Bool> {
        Binding(get: { unpublishTarget != nil }, set: { if !$0 { unpublishTarget = nil } })
    }
    private var renameAlert: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
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
            files = try await client.projectFiles(projectID: project.id)
        } catch {
            if case PenpotError.unauthorized = error {
                appState.logout()
            } else {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        isLoading = false
    }

    private func createFile() async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard let client = appState.client, !name.isEmpty else { return }
        do {
            try await client.createFile(projectID: project.id, name: name)
            await load()
        } catch { handleActionError(error) }
    }

    private func rename(_ file: FileListItem) async {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard let client = appState.client, !name.isEmpty else { return }
        do {
            try await client.renameFile(id: file.id, name: name)
            await load()
        } catch { handleActionError(error) }
    }

    private func duplicate(_ file: FileListItem) async {
        guard let client = appState.client else { return }
        do {
            try await client.duplicateFile(id: file.id)
            await load()
        } catch { handleActionError(error) }
    }

    /// Publishes the file as a team shared library (`set-file-shared`, `isShared: true`). The
    /// file stays in this project; it now also appears under the team's Libraries.
    private func publish(_ file: FileListItem) async {
        guard let client = appState.client else { return }
        do {
            try await client.setFileShared(id: file.id, isShared: true)
            await load()
        } catch { handleActionError(error) }
    }

    /// Unpublishes a shared-library file (`set-file-shared`, `isShared: false`); its assets are
    /// absorbed into the files that depend on it.
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

    private func delete(_ file: FileListItem) async {
        guard let client = appState.client else { return }
        do {
            try await client.deleteFile(id: file.id)
            await load()
        } catch { handleActionError(error) }
    }

    /// Destinations for moving a file: other active projects in the same team.
    private func projectTargets() async throws -> [MoveTarget] {
        guard let client = appState.client, let teamID = project.teamId else { return [] }
        return try await client.projects(teamID: teamID)
            .filter { $0.deletedAt == nil && $0.id != project.id }
            .map { MoveTarget(id: $0.id, name: $0.isDefaultProject ? .appLocalized("Drafts") : $0.name) }
    }

    private func move(_ file: FileListItem, toProjectID projectID: String) async throws {
        guard let client = appState.client else { return }
        try await client.moveFiles(ids: [file.id], toProjectID: projectID)
        await load()
    }

    private func handleActionError(_ error: Error) {
        if case PenpotError.unauthorized = error {
            appState.logout()
        } else {
            actionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
