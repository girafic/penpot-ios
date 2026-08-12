import SwiftUI
import UniformTypeIdentifiers

/// A team's uploaded fonts (`get-font-variants`), grouped by family. Upload ttf/otf/
/// woff/woff2 files (metadata parsed client-side — the server never opens the font),
/// rename or download a family, swipe or long-press a variant to delete it.
struct FontsView: View {
    @Environment(AppState.self) private var appState
    let team: Team

    @State private var variants: [FontVariant] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var pendingDelete: FontDeletion?
    @State private var showImporter = false
    @State private var uploads: [FontUploadItem] = []
    @State private var renameTarget: FamilyRename?
    @State private var renameText = ""
    @State private var isExporting = false
    @State private var exportedDocument: ExportedDocument?

    private struct FamilyRename: Identifiable {
        let fontID: String
        let originalName: String
        var id: String { fontID }
    }

    private struct FontUploadItem: Identifiable {
        let id = UUID()
        let filename: String
        let metadata: FontFileMetadata?
        var progress: Double = 0
        var status: Status = .waiting

        enum Status {
            case waiting, uploading, done, skipped
            case failed(String)
        }
    }

    /// Upload/rename/delete need edit rights; unknown permissions default to visible
    /// (the server enforces regardless — violations surface as 404 object-not-found).
    private var canEdit: Bool { team.permissions?.canEdit != false }

    /// The picker accepts the container formats Penpot stores.
    private static let fontContentTypes: [UTType] = [
        UTType("public.truetype-ttf-font"), UTType("public.opentype-font"),
        UTType(filenameExtension: "ttf"), UTType(filenameExtension: "otf"),
        UTType(filenameExtension: "woff"), UTType(filenameExtension: "woff2"),
    ].compactMap { $0 }

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
            .penpotPageBackground()
            .navigationTitle("Fonts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if canEdit {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showImporter = true } label: { AppIcon.add.image }
                            .accessibilityLabel("Upload fonts")
                    }
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: Self.fontContentTypes,
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    handlePickedFonts(urls)
                }
            }
            .confirmationDialog(deleteTitle, isPresented: deleteDialog, presenting: pendingDelete) { deletion in
                Button("Delete", role: .destructive) { Task { await perform(deletion) } }
                Button("Cancel", role: .cancel) {}
            } message: { deletion in
                Text(deleteMessage(deletion))
            }
            .alert("Rename Font Family", isPresented: renameAlert, presenting: renameTarget) { target in
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") { Task { await rename(target) } }
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
        if isLoading && variants.isEmpty {
            LoadingView(message: "Loading fonts…")
        } else if let errorMessage, variants.isEmpty {
            ErrorStateView(message: errorMessage) { Task { await load() } }
        } else if variants.isEmpty && uploads.isEmpty {
            EmptyStateView(title: "No fonts", icon: .text,
                           description: team.isDefault == true
                               ? "Fonts you upload will appear here."
                               : "Fonts uploaded to this team will appear here.")
        } else {
            // Hand-built cards rather than a List (see PenpotCard). Deleting a variant
            // lives in the context menu; swiping is restored by penpotSwipeActions.
            ScrollView {
                LazyVStack(spacing: 16) {
                    uploadsSection
                    ForEach(families) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            sectionHeader(Text(verbatim: group.id))
                            PenpotCard {
                                ForEach(Array(group.variants.enumerated()), id: \.element.id) { index, variant in
                                    PenpotCardRow(showsChevron: false) {
                                        Text(variantLabel(variant))
                                    }
                                    .contextMenu {
                                        if canEdit, let fontID = variant.fontId {
                                            Button { startRename(fontID: fontID, name: group.id) } label: {
                                                AppIcon.edit.label("Rename Font Family")
                                            }
                                        }
                                        if let fontID = variant.fontId {
                                            Button { Task { await download(fontID: fontID) } } label: {
                                                AppIcon.download.label("Download Font Family")
                                            }
                                        }
                                        if canEdit {
                                            Button(role: .destructive) { pendingDelete = .variant(variant) } label: {
                                                AppIcon.delete.destructiveLabel("Delete Variant")
                                            }
                                            if let fontID = variant.fontId {
                                                Button(role: .destructive) {
                                                    pendingDelete = .family(fontID: fontID, name: group.id)
                                                } label: {
                                                    AppIcon.delete.destructiveLabel("Delete Font Family")
                                                }
                                            }
                                        }
                                    }
                                    .penpotSwipeActions(id: variant.id) {
                                        if canEdit {
                                            PenpotSwipeAction("Delete Variant", icon: .delete,
                                                              isDestructive: true) {
                                                pendingDelete = .variant(variant)
                                            }
                                        }
                                    }
                                    if index < group.variants.count - 1 {
                                        PenpotCardDivider()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder
    private var uploadsSection: some View {
        if !uploads.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader(Text("Uploading"))
                PenpotCard {
                    ForEach(uploads) { item in
                        PenpotCardRow(showsChevron: false) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.filename)
                                    .font(.workSans(.subheadline))
                                    .lineLimit(1)
                                if let metadata = item.metadata {
                                    Text(verbatim: metadata.summary)
                                        .font(.workSans(.caption))
                                        .foregroundStyle(.secondary)
                                }
                                switch item.status {
                                case .waiting:
                                    EmptyView()
                                case .uploading:
                                    ProgressView(value: item.progress)
                                case .done:
                                    AppIcon.tick.image(size: 14).foregroundStyle(.secondary)
                                case .skipped:
                                    Text("Already installed — skipped.")
                                        .font(.workSans(.caption))
                                        .foregroundStyle(.secondary)
                                case .failed(let message):
                                    Text(message)
                                        .font(.workSans(.caption))
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                        PenpotCardDivider()
                    }
                    Button {
                        uploads.removeAll()
                    } label: {
                        PenpotCardRow(showsChevron: false) {
                            Text("Clear")
                                .font(.workSans(.caption))
                                .foregroundStyle(Color.penpotAccent)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// A section title above a card, in Penpot's uppercase label style.
    private func sectionHeader(_ title: Text) -> some View {
        title
            .font(.workSans(.caption, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.5)
            .foregroundStyle(Color.penpotIconGray)
            .frame(maxWidth: .infinity, alignment: .leading)
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
    private var renameAlert: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    // MARK: Upload

    private func handlePickedFonts(_ urls: [URL]) {
        var items: [FontUploadItem] = []
        var payloads: [UUID: (metadata: FontFileMetadata, data: Data)] = [:]
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let filename = url.lastPathComponent
            guard let data = try? Data(contentsOf: url),
                  let metadata = FontFileMetadata.parse(data: data, filename: filename) else {
                items.append(FontUploadItem(filename: filename, metadata: nil,
                                            status: .failed(.appLocalized("Not a supported font file."))))
                continue
            }
            let item = FontUploadItem(filename: filename, metadata: metadata)
            items.append(item)
            payloads[item.id] = (metadata, data)
        }
        uploads = items
        Task { await runUploads(payloads) }
    }

    /// Sequential uploads (conservative vs the web's 2-in-flight; stays clear of the
    /// 5-sessions-per-profile quota). Family grouping is a CLIENT convention: reuse an
    /// existing family's fontId, and remember ids minted within this batch so "Inter
    /// Regular + Inter Bold" picked together land in one family.
    private func runUploads(_ payloads: [UUID: (metadata: FontFileMetadata, data: Data)]) async {
        guard let client = appState.client else { return }
        var familyIDs: [String: String] = [:]
        for variant in variants {
            if let fontID = variant.fontId {
                familyIDs[variant.fontFamily.lowercased()] = fontID
            }
        }
        for index in uploads.indices {
            guard let payload = payloads[uploads[index].id] else { continue }
            let metadata = payload.metadata
            // No server-side uniqueness — a re-upload would silently duplicate the row.
            if variants.contains(where: {
                $0.fontFamily.caseInsensitiveCompare(metadata.family) == .orderedSame
                    && $0.fontWeight == metadata.weight
                    && ($0.fontStyle ?? "normal") == metadata.style
            }) {
                uploads[index].status = .skipped
                continue
            }
            let familyKey = metadata.family.lowercased()
            let fontID = familyIDs[familyKey] ?? UUID().uuidString.lowercased()
            familyIDs[familyKey] = fontID
            uploads[index].status = .uploading
            let itemID = uploads[index].id
            do {
                try await client.uploadFontVariant(
                    teamID: team.id, fontID: fontID, metadata: metadata, data: payload.data,
                    onProgress: { progress in
                        Task { @MainActor in
                            if let current = uploads.firstIndex(where: { $0.id == itemID }) {
                                uploads[current].progress = progress
                            }
                        }
                    })
                uploads[index].status = .done
            } catch {
                if case PenpotError.unauthorized = error {
                    appState.logout()
                    return
                }
                uploads[index].status = .failed(uploadErrorMessage(error, filename: uploads[index].filename))
            }
        }
        await load()
        // Successes now show in the regular list; keep failures/skips visible.
        uploads.removeAll { if case .done = $0.status { return true } else { return false } }
    }

    private func uploadErrorMessage(_ error: Error, filename: String) -> String {
        if case PenpotError.fontTooLarge = error {
            return String(format: .appLocalized("“%@” is larger than 30 MB."), filename)
        }
        if let penpotError = error as? PenpotError {
            if penpotError.isUnknownCommand {
                return .appLocalized("Uploading fonts requires Penpot 2.17 or newer.")
            }
            switch penpotError.serverErrorCode {
            case "font-max-file-size-reached":
                return String(format: .appLocalized("“%@” is larger than 30 MB."), filename)
            case "media-type-not-allowed":
                return String(format: .appLocalized("“%@” is not a supported font format."), filename)
            case "invalid-font-upload", "unexpected-data", "invalid-woff-file", "invalid-woff2-file":
                return String(format: .appLocalized("“%@” couldn't be processed by the server."), filename)
            case "missing-chunks":
                return .appLocalized("The upload was interrupted — please try again.")
            case "max-quote-reached":
                return .appLocalized("The team's font limit has been reached.")
            case "object-not-found":
                return .appLocalized("You don't have permission to upload fonts to this team.")
            default:
                break
            }
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: Rename / download

    private func startRename(fontID: String, name: String) {
        renameText = name
        renameTarget = FamilyRename(fontID: fontID, originalName: name)
    }

    private func rename(_ target: FamilyRename) async {
        guard let client = appState.client else { return }
        let name = FontFileMetadata.sanitizedFamily(renameText)
        guard !name.isEmpty, name != target.originalName else { return }
        do {
            try await client.updateFont(teamID: team.id, fontID: target.fontID, name: name)
            await load()
        } catch {
            if case PenpotError.unauthorized = error {
                appState.logout()
            } else {
                actionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func download(fontID: String) async {
        guard let client = appState.client else { return }
        isExporting = true
        defer { isExporting = false }
        do {
            let (data, name) = try await client.downloadFontFamilyArchive(fontID: fontID)
            exportedDocument = try ExportedDocument.file(data: data, filename: name,
                                                         fallbackName: "fonts.zip")
        } catch {
            if case PenpotError.unauthorized = error {
                appState.logout()
            } else {
                actionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
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
