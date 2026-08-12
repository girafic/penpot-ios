import SwiftUI

/// A template preview card: thumbnail box + name, matching ``FileCardView``'s geometry so
/// the templates grid reads the same as the file grids elsewhere in the dashboard.
private struct TemplateCardView: View {
    let template: BuiltinTemplate
    let baseURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The box is sized *first* and the image goes in an `.overlay`, which is
            // constrained to the box's frame. An aspect-`.fill` image reports a very large
            // intrinsic width, so putting it in a ZStack instead would stretch the card
            // past its grid cell — height alone doesn't bound it.
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary)
                .frame(maxWidth: .infinity)
                .frame(height: 110)
                .overlay {
                    if let baseURL {
                        // `.fit`, not `.fill`: the previews are ~2.3:1 banners whose artwork
                        // names the template, and filling this box crops that branding off.
                        // Templates without a published preview (e.g. `welcome`) 404 and
                        // fall back to `RemoteImage`'s placeholder glyph.
                        RemoteImage(url: template.thumbnailURL(baseURL: baseURL), contentMode: .fit)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))

            Text(verbatim: template.name)
                .font(.workSans(.subheadline))
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)
        }
    }
}

/// Penpot's built-in starter templates (`get-builtin-templates`).
///
/// The command returns only an id and a name — no thumbnails, descriptions or preview URLs —
/// so this is a plain list rather than the file-card grid used elsewhere. Tapping a template
/// picks a destination project and imports it with `clone-template`, which is the only thing
/// a template id can be used for.
struct TemplatesView: View {
    @Environment(AppState.self) private var appState
    let team: Team

    @State private var templates: [BuiltinTemplate] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// Non-nil while the destination picker is open for that template.
    @State private var pendingTemplate: BuiltinTemplate?
    /// Name of the template that was just imported, for the confirmation alert.
    @State private var importedName: String?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        content
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .refreshable { await load() }
            .sheet(item: $pendingTemplate) { template in
                MoveSheet(title: "Add to project", failureTitle: "Couldn’t add template") {
                    try await projectTargets()
                } onSelect: { target in
                    try await clone(template, into: target)
                }
            }
            .alert("Template added", isPresented: importedAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(verbatim: String(format: .appLocalized("“%@” was imported. Open the project to view it."),
                                      importedName ?? ""))
            }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && templates.isEmpty {
            LoadingView(message: "Loading templates…")
        } else if let errorMessage, templates.isEmpty {
            ErrorStateView(message: errorMessage) { Task { await load() } }
        } else if templates.isEmpty {
            EmptyStateView(title: "No templates", icon: .template,
                           description: "This server offers no built-in templates.")
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(templates) { template in
                        Button {
                            pendingTemplate = template
                        } label: {
                            TemplateCardView(template: template, baseURL: appState.client?.baseURL)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
    }

    private var importedAlert: Binding<Bool> {
        Binding(get: { importedName != nil }, set: { if !$0 { importedName = nil } })
    }

    /// Projects of this team that a template can be imported into (Drafts included).
    private func projectTargets() async throws -> [MoveTarget] {
        guard let client = appState.client else { return [] }
        return try await client.projects(teamID: team.id)
            .filter { $0.deletedAt == nil }
            .map { MoveTarget(id: $0.id, name: $0.name) }
    }

    private func clone(_ template: BuiltinTemplate, into target: MoveTarget) async throws {
        guard let client = appState.client else { return }
        try await client.cloneTemplate(templateID: template.id, projectID: target.id)
        importedName = template.name
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        errorMessage = nil
        do {
            templates = try await client.builtinTemplates()
        } catch {
            if case PenpotError.unauthorized = error {
                appState.logout()
            } else {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        isLoading = false
    }
}
