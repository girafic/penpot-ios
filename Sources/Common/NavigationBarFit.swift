import SwiftUI
import UIKit

/// Whether a navigation bar's title keeps its room beside the bar's buttons. iOS 26 lets a
/// title that doesn't fit run under the buttons: on an iPhone 13 mini, "Done", the page's
/// name and the page canvas' three icons overlapped. Where it doesn't fit, the screens move
/// their icons into the ⋮ menu and "Done" becomes an X (``DoneButton``).
///
/// The widths are iOS 26's glass buttons, measured on an iPhone 13 mini: a text button is
/// its label and 14 on each side, a lone icon button 44, icons sharing one glass 51.5
/// apart. The bar keeps 16 from the screen's edges, the title 8 from the buttons.
enum NavigationBarFit {
    enum Leading {
        case none
        /// The back button: Penpot's arrow, no text.
        case back
        /// A text button, such as "Done".
        case text(String)
    }

    static func titleFits(_ title: String, chevron: Bool = false, leading: Leading,
                          trailingIcons: Int, width: CGFloat) -> Bool {
        let room = width - 2 * 16 - leadingWidth(leading) - trailingWidth(trailingIcons)
            - (leadingWidth(leading) > 0 ? 8 : 0) - (trailingIcons > 0 ? 8 : 0)
        return titleWidth(title, chevron: chevron) <= room
    }

    /// The title in the bar's Work Sans, as large as Dynamic Type makes ``PageSwitcher``'s,
    /// with its chevron when it switches pages.
    static func titleWidth(_ title: String, chevron: Bool) -> CGFloat {
        let font = UIFontMetrics(forTextStyle: .headline)
            .scaledFont(for: WorkSans.uiFont(for: .semibold, size: 17))
        let text = (title as NSString).size(withAttributes: [.font: font]).width
        return ceil(text) + (chevron ? 4 + 12 : 0)
    }

    private static func leadingWidth(_ leading: Leading) -> CGFloat {
        switch leading {
        case .none: 0
        case .back: 44
        case .text(let label):
            ceil((label as NSString).size(withAttributes: [.font: WorkSans.uiFont(for: .regular, size: 17)]).width) + 28
        }
    }

    private static func trailingWidth(_ icons: Int) -> CGFloat {
        icons > 0 ? 44 + CGFloat(icons - 1) * 51.5 : 0
    }
}

/// A full-screen page's "Done", or an X where the bar is short of room
/// (``NavigationBarFit``).
struct DoneButton: View {
    var compact = false
    let action: () -> Void

    var body: some View {
        if compact {
            Button(action: action) { AppIcon.closeFilled.image }
                .accessibilityLabel("Done")
        } else {
            Button("Done", action: action)
        }
    }
}

extension View {
    /// Keeps `width` at the view's width: on a screen's root, the bar's.
    func trackingWidth(_ width: Binding<CGFloat?>) -> some View {
        onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width.wrappedValue = $0 }
    }
}
