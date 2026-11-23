import SwiftUI

extension View {
    /// Keeps the navigation bar (title, the glass back and toolbar buttons) and the status bar
    /// following a live light/dark switch on a page **without a scroll view of its own**.
    ///
    /// On iOS 26 a navigation stack only passes a trait change on to its bar chrome when the
    /// visible page has a scroll view. Without one, the system switching to dark mode turns the
    /// page dark but leaves the bar, its glass buttons and the status bar light — dark text on
    /// black — until the page is pushed again. An empty, disabled scroll view behind the page
    /// is enough to keep them in sync; it takes no touches and no accessibility focus.
    ///
    /// Use it only where the page (or one state of it, such as loading or empty) has no scroll
    /// view: iOS 26 also takes the page's scroll view for the bar's scroll-edge effect, and a
    /// second one must not compete with the real one.
    func navigationChromeFollowsAppearance() -> some View {
        background {
            ScrollView {}
                .scrollDisabled(true)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
