import Foundation

enum PenpotDate {
    private static let parser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallbackParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        return parser.date(from: string) ?? fallbackParser.date(from: string)
    }

    /// Orders unparseable/missing timestamps last.
    static func sortKey(_ string: String?) -> Date {
        date(from: string) ?? .distantPast
    }

    /// A relative description matching Penpot's web UI, e.g. "26 days ago" / "vor 26 Tagen".
    ///
    /// Pass the view's `@Environment(\.locale)` so the text follows the in-app language
    /// picker — `RelativeDateTimeFormatter` defaults to the *system* language otherwise.
    ///
    /// We pick the component ourselves rather than let `RelativeDateTimeFormatter` choose,
    /// for two reasons:
    /// 1. Its automatic selection uses a *weeks* unit, so a 26-day-old comment reads
    ///    "3 weeks ago" — but Penpot's web canvas shows "26 days ago". Our ladder skips
    ///    weeks (days → months) to stay consistent with what the WebView renders.
    /// 2. `.full` avoids the CLDR *narrow* relative form that `.abbreviated` falls back to
    ///    in some locales (e.g. Russian "-3 нед." with a literal minus instead of "назад").
    static func relative(from string: String?, locale: Locale = .autoupdatingCurrent) -> String {
        guard let date = date(from: string) else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = locale
        return formatter.localizedString(from: penpotComponents(to: date))
    }

    /// How far the server's clock may run ahead of the device's. A comment posted a moment
    /// ago came back stamped a few milliseconds in the future and read "in 0 seconds".
    static let clockSkew: TimeInterval = 60

    /// Signed `DateComponents` (negative = past) on Penpot's unit ladder:
    /// seconds → minutes → hours → days → months → years, deliberately skipping weeks.
    /// A date less than ``clockSkew`` ahead counts as past; further ahead it is a real
    /// future date (when a deleted file goes for good).
    static func penpotComponents(to date: Date, now: Date = Date()) -> DateComponents {
        let interval = date.timeIntervalSince(now)   // negative for past dates
        let sign = interval < clockSkew ? -1 : 1
        let magnitude = abs(interval)
        let minute = 60.0, hour = 3600.0, day = 86_400.0, month = day * 30, year = day * 365
        func rounded(_ value: Double) -> Int { sign * max(1, Int(value.rounded())) }
        switch magnitude {
        case ..<minute: return DateComponents(second: rounded(magnitude))
        case ..<hour:   return DateComponents(minute: rounded(magnitude / minute))
        case ..<day:    return DateComponents(hour:   rounded(magnitude / hour))
        case ..<month:  return DateComponents(day:    rounded(magnitude / day))
        case ..<year:   return DateComponents(month:  rounded(magnitude / month))
        default:        return DateComponents(year:   rounded(magnitude / year))
        }
    }
}
