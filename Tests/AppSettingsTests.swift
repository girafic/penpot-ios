import XCTest
import SwiftUI
@testable import PenpotiOS

final class AppSettingsTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "test.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    func testThemeMapsToColorScheme() {
        let settings = AppSettings(defaults: makeDefaults())
        settings.theme = .system
        XCTAssertNil(settings.colorScheme)
        settings.theme = .light
        XCTAssertEqual(settings.colorScheme, .light)
        settings.theme = .dark
        XCTAssertEqual(settings.colorScheme, .dark)
    }

    // Theme/language must survive a relaunch (new instance over the same store).
    func testPreferencesPersistAcrossInstances() {
        let defaults = makeDefaults()
        let first = AppSettings(defaults: defaults)
        first.theme = .dark
        first.appLanguage = "de"
        first.accountLanguage = "pt_br"

        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.theme, .dark)
        XCTAssertEqual(second.appLanguage, "de")
        XCTAssertEqual(second.accountLanguage, "pt_br")
    }

    func testDefaultThemeIsSystem() {
        let settings = AppSettings(defaults: makeDefaults())
        XCTAssertEqual(settings.theme, .system)
        XCTAssertNil(settings.appLanguage)
        XCTAssertNil(settings.accountLanguage)
    }

    // Raw values must equal Penpot's own theme strings so they're interchangeable with the API.
    func testThemeRawValuesMatchPenpot() {
        XCTAssertEqual(PenpotTheme.system.rawValue, "system")
        XCTAssertEqual(PenpotTheme.light.rawValue, "light")
        XCTAssertEqual(PenpotTheme.dark.rawValue, "dark")
    }
}
