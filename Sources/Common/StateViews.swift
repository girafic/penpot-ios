import SwiftUI

struct LoadingView: View {
    var message: LocalizedStringKey = "Loading…"

    var body: some View {
        VStack(spacing: 16) {
            // Penpot's animated pencil — the same loader the web app shows.
            PencilLoaderView()
                .frame(width: 100)
            Text(message)
                .font(.workSans(.callout))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Size for the large glyph shown in `ContentUnavailableView`-style empty/error states.
private let emptyStateIconSize: CGFloat = 48

struct ErrorStateView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            AppIcon.warning.label("Something went wrong", size: emptyStateIconSize)
        } description: {
            Text(message)
        } actions: {
            if let retry {
                Button("Try Again", action: retry)
                    .buttonStyle(.penpot(.primary, size: .compact))
            }
        }
    }
}

struct EmptyStateView<Actions: View>: View {
    let title: LocalizedStringKey
    let icon: AppIcon
    let description: LocalizedStringKey?
    private let actions: Actions

    init(title: LocalizedStringKey, icon: AppIcon,
         description: LocalizedStringKey? = nil,
         @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.icon = icon
        self.description = description
        self.actions = actions()
    }

    var body: some View {
        ContentUnavailableView {
            icon.label(title, size: emptyStateIconSize)
        } description: {
            if let description { Text(description) }
        } actions: {
            actions
        }
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(title: LocalizedStringKey, icon: AppIcon, description: LocalizedStringKey? = nil) {
        self.init(title: title, icon: icon, description: description) { EmptyView() }
    }
}
