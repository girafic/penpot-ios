import XCTest
@testable import PenpotiOS

final class PenpotDateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// The server stamped a fresh comment a few milliseconds ahead of the device clock,
    /// and it read "in 0 seconds".
    func testSlightlyFutureDateCountsAsJustPast() {
        let components = PenpotDate.penpotComponents(to: now.addingTimeInterval(0.004), now: now)
        XCTAssertEqual(components.second, -1)

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.locale = Locale(identifier: "en_US")
        XCTAssertEqual(formatter.localizedString(from: components), "1 second ago")
    }

    /// A file in Recently Deleted goes for good days ahead: that stays in the future.
    func testFarFutureDateStaysFuture() {
        let components = PenpotDate.penpotComponents(to: now.addingTimeInterval(7 * 86_400), now: now)
        XCTAssertEqual(components.day, 7)
    }

    /// Penpot's ladder skips weeks: 26 days, not 3 weeks.
    func testPastDaysSkipWeeks() {
        let components = PenpotDate.penpotComponents(to: now.addingTimeInterval(-26 * 86_400), now: now)
        XCTAssertEqual(components.day, -26)
        XCTAssertNil(components.weekOfMonth)
    }
}
