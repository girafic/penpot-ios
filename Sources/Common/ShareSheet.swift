import SwiftUI
import UIKit

/// Wraps `UIActivityViewController` so a local file — e.g. an exported `.penpot` archive — can
/// be shared or saved via the system share sheet.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A file written to a temporary URL, ready to hand to ``ShareSheet``. `Identifiable` so it can
/// drive `.sheet(item:)`.
struct ExportedDocument: Identifiable {
    let id = UUID()
    let url: URL

    /// Writes exported bytes to a temp file. `filename` should already include its
    /// extension (the exporter returns e.g. "Board 1@2x.png"); illegal path characters
    /// are sanitized the same way as the `.penpot` flow.
    static func file(data: Data, filename: String, fallbackName: String = "file") throws -> ExportedDocument {
        let illegal = CharacterSet(charactersIn: "/\\:")
        let cleaned = filename.components(separatedBy: illegal).joined(separator: "-")
        let safe = cleaned.trimmingCharacters(in: .whitespaces).isEmpty ? fallbackName : cleaned
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safe)
        try data.write(to: url, options: .atomic)
        return ExportedDocument(url: url)
    }

    /// Writes exported bytes to a temporary `.penpot` file named after the source file.
    static func penpot(data: Data, name: String) throws -> ExportedDocument {
        let safe = name.trimmingCharacters(in: .whitespaces).isEmpty ? "file" : name
        let base = safe.lowercased().hasSuffix(".penpot") ? safe : "\(safe).penpot"
        return try file(data: data, filename: base)
    }
}

/// Presents the share sheet for an exported file, plus a blocking "preparing" overlay while an
/// export is in flight. Shared by the file and library grids so the `.penpot` download flow
/// lives in one place.
private struct FileExportPresentation: ViewModifier {
    @Binding var isExporting: Bool
    @Binding var document: ExportedDocument?

    func body(content: Content) -> some View {
        content
            .sheet(item: $document) { doc in ShareSheet(items: [doc.url]) }
            .overlay {
                if isExporting {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        PencilLoadingBadge(message: Text("Preparing download…"))
                    }
                }
            }
    }
}

extension View {
    /// Wires up the `.penpot` export share sheet and progress overlay. Drive `isExporting` and
    /// `document` from an async download handler.
    func fileExportPresentation(isExporting: Binding<Bool>, document: Binding<ExportedDocument?>) -> some View {
        modifier(FileExportPresentation(isExporting: isExporting, document: document))
    }
}
