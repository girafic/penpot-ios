import SwiftUI
import UIKit

/// Manages a file's public share links: create a link with the web dialog's options (who
/// may comment / inspect), copy or system-share existing ones, and revoke them. V1 always
/// shares all pages, matching the web dialog's default.
struct ShareLinksSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let fileID: String
    /// Page ids from the caller's already-loaded file, used when the bundle's own page
    /// list can't be read (`create-share-link` requires a non-empty page set).
    var fallbackPageIDs: [String] = []

    @State private var phase: Phase = .loading
    @State private var links: [PenpotShareLink] = []
    @State private var pageIDs: [String] = []
    @State private var whoComment = "team"
    @State private var whoInspect = "team"
    @State private var isCreating = false
    @State private var actionError: String?
    @State private var copiedLinkID: String?
    @State private var sharedURL: IdentifiableURL?
    @State private var linkToDelete: PenpotShareLink?

    private enum Phase {
        case loading
        case ready
        case failed(String)
    }

    private struct IdentifiableURL: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Share links")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { dismiss() }
                    }
                }
                .alert("Delete link", isPresented: deleteAlert, presenting: linkToDelete) { link in
                    Button("Delete", role: .destructive) { Task { await delete(link) } }
                    Button("Cancel", role: .cancel) {}
                } message: { _ in
                    Text("The link will stop working for everyone.")
                }
                .alert("Something went wrong", isPresented: actionErrorAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(actionError ?? "")
                }
                .sheet(item: $sharedURL) { shared in
                    ShareSheet(items: [shared.url])
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
        case .ready:
            List {
                Section {
                    Picker("Can comment", selection: $whoComment) {
                        Text("Only team members").tag("team")
                        Text("All users").tag("all")
                    }
                    Picker("Can inspect code", selection: $whoInspect) {
                        Text("Only team members").tag("team")
                        Text("All users").tag("all")
                    }
                    Button {
                        Task { await create() }
                    } label: {
                        if isCreating {
                            ProgressView()
                        } else {
                            Text("Get link")
                        }
                    }
                    .disabled(isCreating || pageIDs.isEmpty)
                } footer: {
                    Text("Anyone with the link can view this file.")
                }

                Section("Share links") {
                    if links.isEmpty {
                        Text("No share links yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(links) { link in
                            linkRow(link)
                        }
                    }
                }
            }
        }
    }

    private func linkRow(_ link: PenpotShareLink) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(audienceSummary(of: link))
                .font(.workSans(.subheadline))
            HStack(spacing: 20) {
                Button { copy(link) } label: {
                    AppIcon.copy.label(copiedLinkID == link.id ? "Link copied" : "Copy link", size: 14)
                }
                Button { share(link) } label: {
                    AppIcon.share.label("Share", size: 14)
                }
            }
            .buttonStyle(.borderless)
            .font(.workSans(.caption))
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { linkToDelete = link } label: {
                AppIcon.delete.label("Delete")
            }
        }
    }

    /// e.g. "Can comment: All users · Can inspect code: Only team members".
    private func audienceSummary(of link: PenpotShareLink) -> String {
        func audience(_ who: Bool) -> String {
            who ? .appLocalized("All users") : .appLocalized("Only team members")
        }
        return "\(String.appLocalized("Can comment")): \(audience(link.allowsExternalComments))"
            + " · \(String.appLocalized("Can inspect code")): \(audience(link.allowsExternalInspect))"
    }

    private func url(for link: PenpotShareLink) -> URL? {
        appState.client?.shareURL(fileID: fileID,
                                  pageID: link.pages?.first ?? pageIDs.first,
                                  shareID: link.id)
    }

    private var deleteAlert: Binding<Bool> {
        Binding(get: { linkToDelete != nil }, set: { if !$0 { linkToDelete = nil } })
    }

    private var actionErrorAlert: Binding<Bool> {
        Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
    }

    // MARK: Actions

    private func load() async {
        guard let client = appState.client else { return }
        phase = .loading
        do {
            let bundle = try await client.viewOnlyBundle(fileID: fileID)
            links = bundle.shareLinks ?? []
            pageIDs = bundle.pageIDs.isEmpty ? fallbackPageIDs : bundle.pageIDs
            phase = .ready
        } catch {
            if case PenpotError.unauthorized = error {
                appState.logout()
                return
            }
            phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    private func create() async {
        guard let client = appState.client, !pageIDs.isEmpty else { return }
        isCreating = true
        defer { isCreating = false }
        do {
            let link = try await client.createShareLink(fileID: fileID,
                                                        whoComment: whoComment,
                                                        whoInspect: whoInspect,
                                                        pageIDs: pageIDs)
            links.append(link)
        } catch { handleActionError(error) }
    }

    private func copy(_ link: PenpotShareLink) {
        guard let url = url(for: link) else { return }
        UIPasteboard.general.url = url
        copiedLinkID = link.id
        Task {
            try? await Task.sleep(for: .seconds(2))
            if copiedLinkID == link.id { copiedLinkID = nil }
        }
    }

    private func share(_ link: PenpotShareLink) {
        guard let url = url(for: link) else { return }
        sharedURL = IdentifiableURL(url: url)
    }

    /// Optimistic removal with revert — the row disappears immediately, and reappears
    /// (plus an error alert) if the server rejects the delete.
    private func delete(_ link: PenpotShareLink) async {
        guard let client = appState.client else { return }
        let index = links.firstIndex { $0.id == link.id }
        if let index { links.remove(at: index) }
        do {
            try await client.deleteShareLink(id: link.id)
        } catch {
            if let index { links.insert(link, at: min(index, links.count)) }
            handleActionError(error)
        }
    }

    private func handleActionError(_ error: Error) {
        if case PenpotError.unauthorized = error {
            appState.logout()
        } else {
            actionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
