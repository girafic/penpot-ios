import SwiftUI

/// Options for exporting a single board: format (PNG/SVG/PDF) and — for PNG — a pixel
/// density. Options-only by design: Export dismisses and hands the choice back, and the
/// caller runs the download through the shared export overlay + share sheet (no sheet
/// presented from inside a sheet).
struct ExportBoardSheet: View {
    @Environment(\.dismiss) private var dismiss
    let board: Board
    let onExport: (BoardExportFormat, Int) -> Void

    @State private var format: BoardExportFormat = .png
    @State private var scale = 1

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        PenpotSegmentedPicker(
                            selection: $format,
                            segments: BoardExportFormat.allCases.map { ($0, Text(verbatim: $0.displayName)) })
                        if format.supportsScale {
                            PenpotSegmentedPicker(
                                selection: $scale,
                                segments: [1, 2, 3].map { ($0, Text(verbatim: "\($0)x")) })
                        }
                        // e.g. "1920 × 1080 px" — numbers only, deliberately not localized.
                        if format.supportsScale {
                            Text(verbatim: pixelSummary)
                                .font(.workSans(.caption))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .penpotPageBackground()
            .navigationTitle("Export board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        dismiss()
                        onExport(format, scale)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var pixelSummary: String {
        let width = Int(board.selrect.width) * scale
        let height = Int(board.selrect.height) * scale
        return "\(width) × \(height) px"
    }
}
