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
            Form {
                Section {
                    Picker("Format", selection: $format) {
                        ForEach(BoardExportFormat.allCases) { format in
                            Text(verbatim: format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                    if format.supportsScale {
                        Picker("Scale", selection: $scale) {
                            ForEach([1, 2, 3], id: \.self) { factor in
                                Text(verbatim: "\(factor)x").tag(factor)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                } footer: {
                    // e.g. "1920 × 1080 px" — numbers only, deliberately not localized.
                    if format.supportsScale {
                        Text(verbatim: pixelSummary)
                    }
                }
            }
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
