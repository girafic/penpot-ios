import SwiftUI

/// All of a team's regular projects (excluding Drafts). Create, open, pin, rename, duplicate,
/// move to another team, or delete a project.
struct ProjectsListView: View {
    @Environment(AppState.self) private var appState
    let team: Team
    /// Called after projects change so the parent dashboard refreshes its counts / Pinned section.
    var onProjectsChanged: () async -> Void

    @State private var projects: [Project] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var pinning: Set<String> = []
    @State private var showingCreate = false
    @State private var newName = ""
    @State private var projectToDelete: Project?
    @State private var renameTarget: Project?
    @State private var renameText = ""
    @State private var moveTarget: Project?

    private var regularProjects: [Project] {
        projects.filter { $0.deletedAt == nil && !$0.isDefaultProject }
    }

    var body: some View {
        content
            .navigationTitle("Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { newName = ""; showingCreate = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New Project")
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .alert("New Project", isPresented: $showingCreate) {
                TextField("Project name", text: $newName)
                Button("Cancel", role: .cancel) {}
                Button("Create") { Task { await createProject() } }
            } message: {
                Text("Enter a name for the new project.")
            }
            .alert("Rename Project", isPresented: renameAlert, presenting: renameTarget) { project in
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") { Task { await rename(project) } }
            }
            .confirmationDialog("Delete Project", isPresented: deleteDialog, presenting: projectToDelete) { project in
                Button("Delete", role: .destructive) { Task { await delete(project) } }
                Button("Cancel", role: .cancel) {}
            } message: { project in
                Text("“\(project.name)” will be moved to the trash.")
            }
            .sheet(item: $moveTarget) { project in
                MoveSheet(
                    title: "Move to Team",
                    load: { try await teamTargets() },
                    onSelect: { target in try await move(project, toTeamID: target.id) })
            }
            .alert("Something went wrong", isPresented: actionErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actionError ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && projects.isEmpty {
            LoadingView(message: "Loading projects…")
        } else if let errorMessage, projects.isEmpty {
            ErrorStateView(message: errorMessage) { Task { await load() } }
        } else if regularProjects.isEmpty {
            EmptyStateView(title: "No projects", systemImage: "folder",
                           description: "This team has no projects yet.")
        } else {
            List {
                ForEach(regularProjects) { project in
                    NavigationLink {
                        ProjectFilesView(project: project)
                    } label: {
                        Label(project.name, systemImage: "folder")
                    }
                    .badge(project.fileCount)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { projectToDelete = project } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        pinButton(for: project)
                    }
                    .contextMenu { projectMenu(project) }
                }
            }
        }
    }

    @ViewBuilder
    private func projectMenu(_ project: Project) -> some View {
        Button { startRename(project) } label: { Label("Rename", systemImage: "pencil") }
        Button { Task { await duplicate(project) } } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
        Button { moveTarget = project } label: { Label("Move to Team", systemImage: "folder") }
        pinButton(for: project)
        Button(role: .destructive) { projectToDelete = project } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func pinButton(for project: Project) -> some View {
        Button {
            Task { await togglePin(project) }
        } label: {
            Label(project.isPinnedFlag ? "Unpin" : "Pin",
                  systemImage: project.isPinnedFlag ? "pin.slash" : "pin")
        }
        .tint(.orange)
        .disabled(pinning.contains(project.id))
    }

    private var deleteDialog: Binding<Bool> {
        Binding(get: { projectToDelete != nil }, set: { if !$0 { projectToDelete = nil } })
    }
    private var renameAlert: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }
    private var actionErrorAlert: Binding<Bool> {
        Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
    }

    private func startRename(_ project: Project) {
        renameText = project.name
        renameTarget = project
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        errorMessage = nil
        do {
            projects = try await client.projects(teamID: team.id)
        } catch {
            if case PenpotError.unauthorized = error {
                appState.logout()
            } else {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        isLoading = false
    }

    private func createProject() async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard let client = appState.client, !name.isEmpty else { return }
        do {
            try await client.createProject(teamID: team.id, name: name)
            await refresh()
        } catch { handleActionError(error) }
    }

    private func rename(_ project: Project) async {
        let name = renameText.trimmingCharacters(in: .whitespaces)
        guard let client = appState.client, !name.isEmpty else { return }
        do {
            try await client.renameProject(id: project.id, name: name)
            await refresh()
        } catch { handleActionError(error) }
    }

    private func duplicate(_ project: Project) async {
        guard let client = appState.client else { return }
        do {
            try await client.duplicateProject(id: project.id)
            await refresh()
        } catch { handleActionError(error) }
    }

    private func delete(_ project: Project) async {
        guard let client = appState.client else { return }
        do {
            try await client.deleteProject(id: project.id)
            await refresh()
        } catch { handleActionError(error) }
    }

    private func togglePin(_ project: Project) async {
        guard let client = appState.client, !pinning.contains(project.id) else { return }
        pinning.insert(project.id)
        defer { pinning.remove(project.id) }
        do {
            try await client.setProjectPinned(teamID: team.id, projectID: project.id,
                                               isPinned: !project.isPinnedFlag)
            await refresh()
        } catch { handleActionError(error) }
    }

    /// Destinations for moving a project: every other team the user belongs to.
    private func teamTargets() async throws -> [MoveTarget] {
        guard let client = appState.client else { return [] }
        return try await client.teams()
            .filter { $0.id != team.id }
            .map { MoveTarget(id: $0.id, name: $0.displayName) }
    }

    private func move(_ project: Project, toTeamID teamID: String) async throws {
        guard let client = appState.client else { return }
        try await client.moveProject(id: project.id, toTeamID: teamID)
        await refresh()
    }

    private func refresh() async {
        await load()
        await onProjectsChanged()
    }

    private func handleActionError(_ error: Error) {
        if case PenpotError.unauthorized = error {
            appState.logout()
        } else {
            actionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
