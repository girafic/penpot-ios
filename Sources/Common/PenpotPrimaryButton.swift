import SwiftUI

/// Penpot's filled primary CTA — accent fill, uppercase on-accent label, 8pt radius.
/// A thin wrapper over ``PenpotButtonStyle`` for the common "full-width action at the
/// bottom of a form" shape, adding a busy state and an optional leading icon.
struct PenpotPrimaryButton: View {
    let title: LocalizedStringKey
    /// Optional leading glyph (e.g. `.add` on "Save version").
    var icon: AppIcon? = nil
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isBusy {
                    // Inherits the on-accent tint the style applies to the label.
                    ProgressView()
                } else {
                    if let icon { icon.image(size: 16) }
                    Text(title)
                }
            }
        }
        .buttonStyle(.penpot(.primary, fullWidth: true))
        // Not `.disabled(isBusy)`: that would paint the button in the disabled gray
        // mid-submit. It stays accent-filled and just stops accepting taps.
        .allowsHitTesting(!isBusy)
    }
}
