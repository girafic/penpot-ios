import SwiftUI

/// A team's trash, mirroring the web dashboard's "Recently deleted" page: soft-deleted
/// files grouped by project, restorable until their scheduled permanent deletion.
/// Restoring a file also restores its project server-side.
struct DeletedFilesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.locale) private var locale
    let team: Team
    var onChanged: () async -> Void = {}

    @State private var files: [DeletedFile] = []
    @State private var projects: [Project] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var fileToDelete: DeletedFile?

    private struct TrashGroup: Identifiable {
        let id: String
        let project: Project?
        let files: [DeletedFile]
    }

    /// Trashed files grouped by project in the server's most-recently-modified order.
    /// Deleted projects without recoverable files are omitted — the API offers no way
    /// to restore them, so listing them would only dangle.
    private var groups: [TrashGroup] {
        var order: [String] = []
        var byProject: [String: [DeletedFile]] = [:]
        for file in files {
            let key = file.projectId ?? ""
            if byProject[key] == nil { order.append(key) }
            byProject[key, default: []].append(file)
        }
        return order.map { id in
            TrashGroup(id: id, project: projects.first { $0.id == id }, files: byProject[id] ?? [])
        }
    }

    var body: some View {
        content
            .navigationTitle("Recently Deleted")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .refreshable { await load() }
            .confirmationDialog("Delete Forever", isPresented: deleteDialog, presenting: fileToDelete) { file in
                Button("Delete Forever", role: .destructive) { Task { await deleteForever(file) } }
                Button("Cancel", role: .cancel) {}
            } message: { file in
                Text("“\(file.name)” will be permanently deleted. This cannot be undone.")
            }
            .alert("Something went wrong", isPresented: actionErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actionError ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && groups.isEmpty {
            LoadingView(message: "Loading deleted files…")
        } else if let errorMessage, groups.isEmpty {
            ErrorStateView(message: errorMessage) { Task { await load() } }
        } else if groups.isEmpty {
            EmptyStateView(title: "No deleted items", icon: .delete,
                           description: "Deleted files can be restored here for a limited time.")
        } else {
            List {
                ForEach(groups) { group in
                    Section(header: header(for: group.project)) {
                        ForEach(group.files) { file in
                            row(file)
                        }
                    }
                }
            }
        }
    }

    private func header(for project: Project?) -> Text {
        guard let project else { return Text("Project") }
        return project.isDefaultProject ? Text("Drafts") : Text(verbatim: project.name)
    }

    private func row(_ file: DeletedFile) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(file.name)
            Text("Will be permanently deleted \(PenpotDate.relative(from: file.willBeDeletedAt, locale: locale))")
                .font(.workSans(.caption))
                .foregroundStyle(.secondary)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { fileToDelete = file } label: {
                AppIcon.delete.label("Delete Forever")
            }
            .tint(.red)
            Button { Task { await restore(file) } } label: {
                AppIcon.restore.label("Restore")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button { Task { await restore(file) } } label: {
                AppIcon.restore.label("Restore")
            }
            Button(role: .destructive) { fileToDelete = file } label: {
                AppIcon.delete.label("Delete Forever")
            }
        }
    }

    private var deleteDialog: Binding<Bool> {
        Binding(get: { fileToDelete != nil }, set: { if !$0 { fileToDelete = nil } })
    }
    private var actionErrorAlert: Binding<Bool> {
        Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        errorMessage = nil
        do {
            async let deleted = client.deletedFiles(teamID: team.id)
            async let all = client.projects(teamID: team.id)
            files = try await deleted
            projects = try await all
        } catch {
            if case PenpotError.unauthorized = error {
                appState.logout()
                return
            }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    private func restore(_ file: DeletedFile) async {
        guard let client = appState.client else { return }
        do {
            try await client.restoreDeletedFiles(teamID: team.id, ids: [file.id])
            await load()
            await onChanged()
        } catch { handleActionError(error) }
    }

    private func deleteForever(_ file: DeletedFile) async {
        guard let client = appState.client else { return }
        do {
            try await client.permanentlyDeleteFiles(teamID: team.id, ids: [file.id])
            await load()
            await onChanged()
        } catch { handleActionError(error) }
    }

    private func handleActionError(_ error: Error) {
        if case PenpotError.unauthorized = error {
            appState.logout()
            return
        }
        actionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
