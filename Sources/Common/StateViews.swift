import SwiftUI

struct LoadingView: View {
    var message: LocalizedStringKey = "Loading…"

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorStateView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label("Something went wrong", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            if let retry {
                Button("Try Again", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct EmptyStateView<Actions: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    let description: LocalizedStringKey?
    private let actions: Actions

    init(title: LocalizedStringKey, systemImage: String,
         description: LocalizedStringKey? = nil,
         @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.actions = actions()
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let description { Text(description) }
        } actions: {
            actions
        }
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(title: LocalizedStringKey, systemImage: String, description: LocalizedStringKey? = nil) {
        self.init(title: title, systemImage: systemImage, description: description) { EmptyView() }
    }
}
