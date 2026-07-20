import SwiftUI

/// A team's uploaded fonts (`get-font-variants`), grouped by family. Swipe or long-press a
/// variant to delete it, or delete the whole family.
struct FontsView: View {
    @Environment(AppState.self) private var appState
    let team: Team

    @State private var variants: [FontVariant] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var pendingDelete: FontDeletion?

    private enum FontDeletion: Identifiable {
        case variant(FontVariant)
        case family(fontID: String, name: String)
        var id: String {
            switch self {
            case .variant(let v): "v-\(v.id)"
            case .family(let id, _): "f-\(id)"
            }
        }
    }

    private struct FontFamilyGroup: Identifiable {
        let id: String
        let variants: [FontVariant]
    }

    private var families: [FontFamilyGroup] {
        Dictionary(grouping: variants, by: \.fontFamily)
            .map { family, vars in
                FontFamilyGroup(id: family, variants: vars.sorted {
                    ($0.fontWeight ?? 400, $0.fontStyle ?? "") < ($1.fontWeight ?? 400, $1.fontStyle ?? "")
                })
            }
            .sorted { $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending }
    }

    var body: some View {
        content
            .navigationTitle("Fonts")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .refreshable { await load() }
            .confirmationDialog(deleteTitle, isPresented: deleteDialog, presenting: pendingDelete) { deletion in
                Button("Delete", role: .destructive) { Task { await perform(deletion) } }
                Button("Cancel", role: .cancel) {}
            } message: { deletion in
                Text(deleteMessage(deletion))
            }
            .alert("Something went wrong", isPresented: actionErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(actionError ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && variants.isEmpty {
            LoadingView(message: "Loading fonts…")
        } else if let errorMessage, variants.isEmpty {
            ErrorStateView(message: errorMessage) { Task { await load() } }
        } else if variants.isEmpty {
            EmptyStateView(title: "No fonts", icon: .text,
                           description: "Fonts uploaded to this team will appear here.")
        } else {
            List {
                ForEach(families) { group in
                    Section(group.id) {
                        ForEach(group.variants) { variant in
                            Text(variantLabel(variant))
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { pendingDelete = .variant(variant) } label: {
                                        AppIcon.delete.label("Delete")
                                    }
                                }
                                .contextMenu {
                                    Button(role: .destructive) { pendingDelete = .variant(variant) } label: {
                                        AppIcon.delete.label("Delete Variant")
                                    }
                                    if let fontID = variant.fontId {
                                        Button(role: .destructive) {
                                            pendingDelete = .family(fontID: fontID, name: group.id)
                                        } label: {
                                            AppIcon.delete.label("Delete Font Family")
                                        }
                                    }
                                }
                        }
                    }
                }
            }
        }
    }

    private var deleteTitle: String {
        switch pendingDelete {
        case .family: .appLocalized("Delete Font Family")
        default: .appLocalized("Delete Variant")
        }
    }

    private func deleteMessage(_ deletion: FontDeletion) -> String {
        switch deletion {
        case .variant(let v):
            return String(format: .appLocalized("“%@” will be removed."), variantLabel(v))
        case .family(_, let name):
            return String(format: .appLocalized("“%@” and all its variants will be removed."), name)
        }
    }

    private func variantLabel(_ variant: FontVariant) -> String {
        if let name = variant.variantName, !name.isEmpty { return name }
        let weight = weightName(variant.fontWeight)
        return variant.fontStyle == "italic" ? "\(weight) Italic" : weight
    }

    private func weightName(_ weight: Int?) -> String {
        switch weight {
        case 100: "Thin"
        case 200: "Extra Light"
        case 300: "Light"
        case 400: "Regular"
        case 500: "Medium"
        case 600: "Semibold"
        case 700: "Bold"
        case 800: "Extra Bold"
        case 900: "Black"
        case let .some(other): "\(other)"
        case .none: "Regular"
        }
    }

    private var deleteDialog: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }
    private var actionErrorAlert: Binding<Bool> {
        Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
    }

    private func load() async {
        guard let client = appState.client else { return }
        isLoading = true
        errorMessage = nil
        do {
            variants = try await client.fontVariants(teamID: team.id)
        } catch {
            if case PenpotError.unauthorized = error {
                appState.logout()
            } else {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
        isLoading = false
    }

    private func perform(_ deletion: FontDeletion) async {
        guard let client = appState.client else { return }
        do {
            switch deletion {
            case .variant(let variant):
                try await client.deleteFontVariant(teamID: team.id, id: variant.id)
            case .family(let fontID, _):
                try await client.deleteFont(teamID: team.id, fontID: fontID)
            }
            await load()
        } catch {
            if case PenpotError.unauthorized = error {
                appState.logout()
            } else {
                actionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
