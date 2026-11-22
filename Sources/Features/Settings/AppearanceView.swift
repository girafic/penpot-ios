import SwiftUI
import UIKit

/// Appearance + app language.
///
/// Theme is device-local and applied instantly via `.preferredColorScheme` on the app root.
/// App language is applied live via a `Bundle` override + the root's `.environment(\.locale,…)`,
/// which re-resolves every `Text` in place — no relaunch, and the current screen is kept.
/// The separate Penpot *account* language lives in Profile.
struct AppearanceView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var settings = settings
        ScrollView {
            VStack(spacing: 16) {
                // The segmented picker brings its own surface — it is not card content.
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader(Text("Theme"))
                    PenpotSegmentedPicker(selection: $settings.theme,
                                          segments: PenpotTheme.allCases.map { ($0, Text($0.label)) })
                    sectionFooter(Text("Choose how the app looks on this device. “System” follows your iPhone’s appearance setting."))
                }

                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader(Text("Language"))
                    PenpotCard {
                        PenpotCardRow(showsChevron: false) {
                            Text("App Language")
                        } trailing: {
                            PenpotMenuPicker(
                                title: "App Language",
                                selection: appLanguageBinding,
                                options: [("", Text("System"))]
                                    + PenpotLanguage.appLocalizedLanguages.map {
                                        ($0.iosCode, Text($0.nativeName))
                                    })
                        }
                    }
                    Button("Change in System Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .buttonStyle(.penpot(.ghost, size: .compact, fullWidth: true))
                    sectionFooter(Text("Sets this app’s language, applied instantly. To change the Penpot website and email language, use Profile › Account language."))
                }

                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader(Text("Canvas"))
                    PenpotCard {
                        // Laid out directly rather than in a PenpotCardRow: a Toggle needs the
                        // full row width to push its switch to the trailing edge.
                        Toggle("WebGL rendering", isOn: $settings.webGLRendering)
                            .toggleStyle(.penpot)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    }
                    sectionFooter(Text("Uses Penpot’s new render engine (Beta) for the canvas view. It can improve performance but may be unstable on iOS — if the canvas fails while zooming, turn this off."))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .penpotPageBackground()
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A former `Section` header, now a label sitting above its card. Takes a `Text` so the
    /// literals stay where the string catalog can extract them.
    private func sectionHeader(_ title: Text) -> some View {
        title
            .font(.workSans(.caption, weight: .semibold))
            .textCase(.uppercase)
            .kerning(0.5)
            .foregroundStyle(Color.penpotIconGray)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A former `Section` footer, now explanatory text under its card.
    private func sectionFooter(_ text: Text) -> some View {
        text
            .font(.workSans(.caption))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Sets the app language, which applies live (see ``AppSettings/appLanguage``). Bound to a
    /// plain `String` because `Picker` can't tag with an optional; "" means “System”.
    private var appLanguageBinding: Binding<String> {
        Binding(
            get: { settings.appLanguage ?? "" },
            set: { newValue in
                let code: String? = newValue.isEmpty ? nil : newValue
                guard code != settings.appLanguage else { return }
                settings.appLanguage = code
            }
        )
    }
}
