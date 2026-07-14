import SwiftUI
import UIKit

/// Appearance + app language.
///
/// Theme is device-local and applied instantly via `.preferredColorScheme` on the app root.
/// App language is applied by writing `AppleLanguages`, which needs a relaunch to take effect
/// (SwiftUI resolves `LocalizedStringKey` against the bundle, not the environment locale).
/// The separate Penpot *account* language lives in Profile.
struct AppearanceView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                Picker("Theme", selection: $settings.theme) {
                    ForEach(PenpotTheme.allCases) { theme in
                        Label(theme.label, systemImage: theme.symbol).tag(theme)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Theme")
            } footer: {
                Text("Choose how Penpot looks on this device. “System” follows your iPhone’s appearance setting.")
            }

            Section {
                Picker("App Language", selection: appLanguageBinding) {
                    Text("System").tag("")
                    ForEach(PenpotLanguage.appLocalizedLanguages) { language in
                        Text(language.nativeName).tag(language.iosCode)
                    }
                }
                Button("Change in System Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            } header: {
                Text("Language")
            } footer: {
                Text("Sets this app’s language, applied instantly. To change the Penpot website and email language, use Profile › Account language.")
            }

            Section {
                Toggle("WebGL rendering", isOn: $settings.webGLRendering)
            } header: {
                Text("Canvas")
            } footer: {
                Text("Uses Penpot’s new render engine (Beta) for the canvas view. It can improve performance but may be unstable on iOS — if the canvas fails while zooming, turn this off.")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
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
