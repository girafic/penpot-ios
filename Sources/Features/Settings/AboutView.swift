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
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader(Text("Application"))
                    PenpotCard {
                        PenpotCardRow(showsChevron: false) {
                            Text("Version")
                        } trailing: {
                            Text(version)
                        }
                        PenpotCardDivider()
                        PenpotCardRow(showsChevron: false) {
                            Text("Build")
                        } trailing: {
                            Text(build)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader(Text("Penpot"))
                    PenpotCard {
                        Link(destination: URL(string: "https://penpot.app")!) {
                            PenpotCardRow(showsChevron: false) {
                                AppIcon.externalLink.label("penpot.app")
                            }
                        }
                        .buttonStyle(.plain)
                        PenpotCardDivider()
                        Link(destination: URL(string: "https://help.penpot.app")!) {
                            PenpotCardRow(showsChevron: false) {
                                AppIcon.help.label("Help & Documentation")
                            }
                        }
                        .buttonStyle(.plain)
                        if let server = appState.client?.baseURL {
                            PenpotCardDivider()
                            PenpotCardRow(showsChevron: false) {
                                Text("Connected server")
                            } trailing: {
                                Text(server.host ?? server.absoluteString)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    PenpotCard {
                        Button {
                            RemoteImageLoader.shared.clearCache()
                            URLCache.shared.removeAllCachedResponses()
                            cacheCleared = true
                        } label: {
                            PenpotCardRow(showsChevron: false) {
                                AppIcon.delete.label("Clear image cache")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    Group {
                        if cacheCleared {
                            Text("Cache cleared.")
                        } else {
                            Text("Removes downloaded thumbnails and avatars from this device. They re-download when needed.")
                        }
                    }
                    .font(.workSans(.caption))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .penpotPageBackground()
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A former `Section` header, now a label sitting above its card.
    private func sectionHeader(_ title: Text) -> some View {
        title
            .font(.workSans(.caption, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.5)
            .foregroundStyle(Color.penpotIconGray)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
