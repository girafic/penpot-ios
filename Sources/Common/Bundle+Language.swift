import Foundation
import ObjectiveC

private var languageBundleKey: UInt8 = 0

/// A `Bundle` subclass that redirects localized-string lookups to a chosen `.lproj`.
/// Installed on `Bundle.main` so `Text("key")` / `NSLocalizedString` resolve against the
/// user's in-app language without an app relaunch.
private final class LanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let override = objc_getAssociatedObject(self, &languageBundleKey) as? Bundle {
            return override.localizedString(forKey: key, value: value, table: tableName)
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    private static var didInstallLanguageBundle = false

    /// Overrides the language used for all `LocalizedStringKey` lookups app-wide. Pass an
    /// iOS/BCP-47 code (e.g. `de`, `pt-BR`) or `nil` to follow the system language.
    ///
    /// Must run on the main thread (called from `AppSettings`, which is main-actor UI state).
    static func setAppLanguage(_ language: String?) {
        if !didInstallLanguageBundle {
            object_setClass(Bundle.main, LanguageBundle.self)
            didInstallLanguageBundle = true
        }
        let override: Bundle?
        if let language, let path = Bundle.main.path(forResource: language, ofType: "lproj") {
            override = Bundle(path: path)
        } else {
            override = nil   // unknown/absent → fall back to the base (system) language
        }
        objc_setAssociatedObject(Bundle.main, &languageBundleKey, override, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
