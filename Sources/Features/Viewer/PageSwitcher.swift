import SwiftUI

/// The current page's name as the bar's title and, when the file has more than one page, a
/// menu of all of them (Penpot's viewer sitemap). The page canvas and the prototype player
/// both use it in their `.principal` slot.
struct PageSwitcher: View {
    let pages: [CanvasPage]
    @Binding var selection: String
    /// Shown while the selected page isn't in `pages`.
    var fallbackTitle = ""

    private var current: String {
        pages.first { $0.id == selection }?.name ?? fallbackTitle
    }

    var body: some View {
        if pages.count > 1 {
            Menu {
                PenpotMenuChoices(selection: $selection,
                                  options: pages.map { (value: $0.id, label: Text($0.name)) })
            } label: {
                HStack(spacing: 4) {
                    Text(current).font(.workSans(.headline)).lineLimit(1)
                    AppIcon.chevronDown.image(size: 12)
                }
                .foregroundStyle(.primary)
            }
            .accessibilityLabel("Switch page, current \(current)")
        } else {
            Text(current).font(.workSans(.headline)).lineLimit(1)
        }
    }
}
