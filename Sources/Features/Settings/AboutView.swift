import SwiftUI

/// App version/build, external links, and local data controls.
struct AboutView: View {
    @Environment(AppState.self) private var appState

    @State private var cacheCleared = false

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        List {
            Section("Application") {
                LabeledContent("Version", value: version)
                LabeledContent("Build", value: build)
            }

            Section("Penpot") {
                Link(destination: URL(string: "https://penpot.app")!) {
                    Label("penpot.app", systemImage: "safari")
                }
                Link(destination: URL(string: "https://help.penpot.app")!) {
                    Label("Help & Documentation", systemImage: "questionmark.circle")
                }
                if let server = appState.client?.baseURL {
                    LabeledContent("Connected server") {
                        Text(server.host ?? server.absoluteString)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button {
                    RemoteImageLoader.shared.clearCache()
                    URLCache.shared.removeAllCachedResponses()
                    cacheCleared = true
                } label: {
                    Label("Clear image cache", systemImage: "trash")
                }
            } footer: {
                if cacheCleared {
                    Text("Cache cleared.")
                } else {
                    Text("Removes downloaded thumbnails and avatars from this device. They re-download when needed.")
                }
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
