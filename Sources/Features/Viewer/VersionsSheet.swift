import SwiftUI

/// A file's version history, mirroring the web workspace's History tab: named user
/// versions render individually (author avatar, label, lock badge), system autosaves are
/// bundled per calendar day; save / rename / pin / restore / delete. Degrades to an
/// "unsupported" state on servers older than Penpot 2.4.
struct VersionsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let fileID: String
    let teamID: String?
    /// Called after a successful restore so the caller reloads the file.
    var onRestored: () -> Void = {}

    @State private var phase: Phase = .loading
    @State private var snapshots: [FileSnapshot] = []
    @State private var membersByID: [String: TeamMember] = [:]
    /// UX gate only — the server enforces edit rights itself (as 404 `object-not-found`).
    /// Defaults to true so an unresolvable membership doesn't hide the actions.
    @State private var canEdit = true
    @State private var isSaving = false
    @State private var pendingConfirmation: PendingConfirmation?
    @State private var renameTarget: FileSnapshot?
    @State private var renameText = ""
    @State private var retryRestoreTarget: FileSnapshot?
    @State private var actionError: String?

    private enum Phase {
        case loading
        case ready
        case failed(String)
        /// The server predates the snapshot commands (< Penpot 2.4).
        case unsupported
    }

    private enum PendingConfirmation {
        case restore(FileSnapshot)
        case delete(FileSnapshot)
    }

    var body: some View {
        NavigationStack {
            content
                .penpotPageBackground()
                .navigationTitle("Versions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                    }
                }
                .alert(confirmationTitle, isPresented: confirmationAlert, presenting: pendingConfirmation) { confirmation in
                    confirmationButton(for: confirmation)
                    Button("Cancel", role: .cancel) {}
                } message: { confirmation in
                    confirmationMessage(for: confirmation)
                }
                .alert("Rename version", isPresented: renameAlert, presenting: renameTarget) { snapshot in
                    TextField("Name", text: $renameText)
                    Button("Cancel", role: .cancel) {}
                    Button("Save") { Task { await rename(snapshot) } }
                }
                .alert("File busy", isPresented: retryAlert, presenting: retryRestoreTarget) { snapshot in
                    Button("Retry") { Task { await restore(snapshot) } }
                    Button("Cancel", role: .cancel) {}
                } message: { _ in
                    Text("The file was modified while restoring. Try again.")
                }
                .alert("Something went wrong", isPresented: actionErrorAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(actionError ?? "")
                }
        }
        .presentationDetents([.medium, .large])
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            LoadingView(message: "Loading…")
        case .failed(let message):
            ErrorStateView(message: message) { Task { await load() } }
        case .unsupported:
            EmptyStateView(title: "Version history unavailable", icon: .history,
                           description: "This Penpot server doesn't support version history (requires Penpot 2.4 or later).")
        case .ready:
            list
        }
    }

    private var groups: [SnapshotGroup] { SnapshotGroup.build(from: snapshots) }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if canEdit {
                    VStack(alignment: .leading, spacing: 8) {
                        PenpotPrimaryButton(title: "Save version", icon: .add, isBusy: isSaving) {
                            Task { await saveVersion() }
                        }
                        Text("Saves the current state of the file as a named version.")
                            .font(.workSans(.caption))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                PenpotCard {
                    if groups.isEmpty {
                        PenpotCardRow(showsChevron: false) {
                            Text("No versions have been saved for this file.")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                            switch group {
                            case .version(let snapshot):
                                versionRow(snapshot)
                            case .autosaves(let day, let items):
                                autosaveGroup(day: day, items: items)
                            }
                            if index < groups.count - 1 {
                                PenpotCardDivider()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .refreshable { await refetch() }
    }

    // MARK: Rows

    private func displayName(_ snapshot: FileSnapshot) -> String {
        if let label = snapshot.label, !label.isEmpty { return label }
        return PenpotDate.relative(from: snapshot.createdAt, locale: locale)
    }

    private func isLockedByOther(_ snapshot: FileSnapshot) -> Bool {
        guard let lockedBy = snapshot.lockedBy else { return false }
        return lockedBy != appState.profile?.id
    }

    private func versionRow(_ snapshot: FileSnapshot) -> some View {
        let author = membersByID[snapshot.profileId ?? ""]
        return PenpotCardRow(showsChevron: false) {
            HStack(spacing: 12) {
                PenpotAvatar(photoID: author?.photoId, baseURL: appState.client?.baseURL,
                             initials: author?.displayName, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName(snapshot))
                        .font(.workSans(.subheadline))
                        .lineLimit(1)
                    Text(PenpotDate.relative(from: snapshot.createdAt, locale: locale))
                        .font(.workSans(.caption))
                        .foregroundStyle(.secondary)
                }
            }
        } trailing: {
            if snapshot.lockedBy != nil {
                AppIcon.lock.image(size: 14)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Locked version")
            }
        }
        .contextMenu {
            if canEdit {
                Button { pendingConfirmation = .restore(snapshot) } label: {
                    AppIcon.restore.label("Restore")
                }
                Button { startRename(snapshot) } label: {
                    AppIcon.edit.label("Rename version")
                }
                if !isLockedByOther(snapshot) {
                    Button(role: .destructive) { pendingConfirmation = .delete(snapshot) } label: {
                        AppIcon.delete.destructiveLabel("Delete")
                    }
                }
            }
        }
        .penpotSwipeActions(id: snapshot.id) {
            if canEdit {
                PenpotSwipeAction("Restore", icon: .restore) {
                    pendingConfirmation = .restore(snapshot)
                }
                // Same gate as the menu: a version locked by someone else can't be deleted.
                if !isLockedByOther(snapshot) {
                    PenpotSwipeAction("Delete", icon: .delete, isDestructive: true) {
                        pendingConfirmation = .delete(snapshot)
                    }
                }
            }
        }
    }

    /// Kept as a DisclosureGroup — it just lives inside the card now instead of a List row,
    /// so it brings the row insets a List used to supply.
    private func autosaveGroup(day: Date, items: [FileSnapshot]) -> some View {
        DisclosureGroup {
            ForEach(items) { snapshot in
                autosaveRow(snapshot)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text("Autosaved versions")
                    .font(.workSans(.subheadline))
                Text(day.formatted(.dateTime.year().month().day().locale(locale)))
                    .font(.workSans(.caption))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func autosaveRow(_ snapshot: FileSnapshot) -> some View {
        // Time of day — the group label already carries the date.
        Text(snapshot.sortKey.formatted(.dateTime.hour().minute().locale(locale)))
            .font(.workSans(.subheadline))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .contextMenu {
                if canEdit {
                    Button { pendingConfirmation = .restore(snapshot) } label: {
                        AppIcon.restore.label("Restore")
                    }
                    Button { Task { await pin(snapshot) } } label: {
                        AppIcon.pin.label("Pin as version")
                    }
                }
            }
    }

    // MARK: Alerts (house rule: one enum-driven confirmation alert, no confirmationDialogs)

    private var confirmationTitle: Text {
        switch pendingConfirmation {
        case .restore: Text("Restore this version?")
        case .delete: Text("Delete version")
        case nil: Text(verbatim: "")
        }
    }

    @ViewBuilder
    private func confirmationButton(for confirmation: PendingConfirmation) -> some View {
        switch confirmation {
        case .restore(let snapshot):
            Button("Restore", role: .destructive) { Task { await restore(snapshot) } }
        case .delete(let snapshot):
            Button("Delete", role: .destructive) { Task { await delete(snapshot) } }
        }
    }

    private func confirmationMessage(for confirmation: PendingConfirmation) -> Text {
        switch confirmation {
        case .restore:
            Text("The file's current content will be replaced by this version. Penpot saves an automatic backup of the current state first, so you can restore it from this list.")
        case .delete(let snapshot):
            Text("The version “\(displayName(snapshot))” will be deleted.")
        }
    }

    private var confirmationAlert: Binding<Bool> {
        Binding(get: { pendingConfirmation != nil }, set: { if !$0 { pendingConfirmation = nil } })
    }
    private var renameAlert: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }
    private var retryAlert: Binding<Bool> {
        Binding(get: { retryRestoreTarget != nil }, set: { if !$0 { retryRestoreTarget = nil } })
    }
    private var actionErrorAlert: Binding<Bool> {
        Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
    }

    // MARK: Actions

    private func isSelf(_ member: TeamMember) -> Bool {
        if let myID = appState.profile?.id,
           member.id == myID || member.profileId == myID { return true }
        guard let email = SessionStore.email?.lowercased() else { return false }
        return member.email?.lowercased() == email
    }

    private func load() async {
        guard let client = appState.client else { return }
        phase = .loading
        do {
            snapshots = try await client.fileSnapshots(fileID: fileID)
            if let teamID, membersByID.isEmpty {
                // Author avatars + the edit gate; a failure only loses those niceties.
                let members = (try? await client.teamMembers(teamID: teamID)) ?? []
                membersByID = Dictionary(members.map { ($0.profileId ?? $0.id, $0) },
                                         uniquingKeysWith: { first, _ in first })
                if let me = members.first(where: isSelf) {
                    canEdit = me.role != .viewer
                }
            }
            phase = .ready
        } catch let error as PenpotError where error.isUnknownCommand {
            phase = .unsupported
        } catch {
            if case PenpotError.unauthorized = error {
                appState.logout()
                return
            }
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// Mutation responses are version-dependent and never trusted — the list is refetched
    /// after every action instead.
    private func refetch() async {
        guard let client = appState.client else { return }
        if let fresh = try? await client.fileSnapshots(fileID: fileID) {
            snapshots = fresh
        }
    }

    private func saveVersion() async {
        guard let client = appState.client else { return }
        isSaving = true
        defer { isSaving = false }
        let label = Date.now.formatted(.dateTime.year().month().day().hour().minute().locale(locale))
        do {
            let ref = try await client.createFileSnapshot(fileID: fileID, label: label)
            await refetch()
            // Web parity: a freshly saved version immediately enters rename mode.
            if let id = ref.id, let created = snapshots.first(where: { $0.id == id }) {
                startRename(created)
            }
        } catch { handleActionError(error) }
    }

    private func startRename(_ snapshot: FileSnapshot) {
        renameText = snapshot.label ?? ""
        renameTarget = snapshot
    }

    private func rename(_ snapshot: FileSnapshot) async {
        guard let client = appState.client else { return }
        let label = renameText.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return }
        do {
            try await client.updateFileSnapshot(id: snapshot.id, label: label)
            await refetch()
        } catch { handleActionError(error) }
    }

    /// Converts an autosave into a permanent named version — the server flips
    /// `created-by` and clears the expiry on update.
    private func pin(_ snapshot: FileSnapshot) async {
        guard let client = appState.client else { return }
        let label = snapshot.sortKey.formatted(.dateTime.year().month().day().hour().minute().locale(locale))
        do {
            try await client.updateFileSnapshot(id: snapshot.id, label: label)
            await refetch()
        } catch { handleActionError(error) }
    }

    private func restore(_ snapshot: FileSnapshot) async {
        guard let client = appState.client else { return }
        do {
            try await client.restoreFileSnapshot(fileID: fileID, id: snapshot.id)
            // Keep the sheet open: the pre-restore safety backup shows up as a fresh
            // autosave in the refetched list, which is the visible receipt.
            await refetch()
            onRestored()
        } catch let error as PenpotError
            where error.serverErrorCode == "file-modified" || error.serverErrorCode == "file-locked" {
            retryRestoreTarget = snapshot
        } catch { handleActionError(error) }
    }

    private func delete(_ snapshot: FileSnapshot) async {
        guard let client = appState.client else { return }
        do {
            try await client.deleteFileSnapshot(id: snapshot.id)
            await refetch()
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
