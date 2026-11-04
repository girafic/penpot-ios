import SwiftUI

/// Penpot's "Download files" dialog: what the `.penpot` export does with the file's linked
/// libraries (`export-binfile`'s `type`). Same options, order and default as Penpot's web
/// (`ui/exports/files.cljs`), and like there it is only shown when the file links any.
struct FileDownloadSheet: View {
    typealias ExportType = PenpotClient.BinfileExportType

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let onExport: (ExportType) -> Void

    @State private var selection: ExportType = .includeLibraries
    @State private var offersLinkLater = false

    private var options: [ExportType] {
        ExportType.allCases.filter { $0 != .linkLater || offersLinkLater }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("What do you want to do with linked libraries?")
                        .font(.workSans(.body))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PenpotCard {
                        ForEach(Array(options.enumerated()), id: \.element) { index, option in
                            Button { selection = option } label: { row(option) }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(selection == option ? .isSelected : [])
                            if index < options.count - 1 {
                                PenpotCardDivider()
                            }
                        }
                    }
                    PenpotPrimaryButton(title: "Continue") {
                        onExport(selection)
                        dismiss()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .penpotPageBackground()
            .navigationTitle("Download files")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            offersLinkLater = await appState.client?.fetchAuthConfig().exportLinkLaterEnabled ?? false
        }
    }

    private func row(_ option: ExportType) -> some View {
        PenpotCardRow(showsChevron: false) {
            HStack(alignment: .top, spacing: 12) {
                radio(isOn: selection == option)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title(of: option))
                        .font(.workSans(.body, weight: .medium))
                    Text(message(of: option))
                        .font(.workSans(.footnote))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Penpot's radio: an outlined circle carrying an accent dot when selected.
    private func radio(isOn: Bool) -> some View {
        Circle()
            .strokeBorder(isOn ? Color.penpotAccent : Color.penpotForegroundSecondary, lineWidth: 1.5)
            .frame(width: 18, height: 18)
            .overlay {
                if isOn {
                    Circle().fill(Color.penpotAccent).frame(width: 8, height: 8)
                }
            }
    }

    // Penpot's own texts (`files-export-modal.options.*`).
    private func title(of option: ExportType) -> LocalizedStringKey {
        switch option {
        case .includeLibraries: "Export file + libraries"
        case .mergeLibraries: "Embed library assets in the file"
        case .detachLibraries: "Treat assets as basic objects"
        case .linkLater: "Link matching libraries on import"
        }
    }

    private func message(of option: ExportType) -> LocalizedStringKey {
        switch option {
        case .includeLibraries: "Files with linked libraries will be included in the export, maintaining their linkage."
        case .mergeLibraries: "Your file will be exported with library asset merged into the local library."
        case .detachLibraries: "Linked library assets won’t be included in the file."
        case .linkLater: "When imported, you’ll be able to link existing libraries with matching names."
        }
    }
}
