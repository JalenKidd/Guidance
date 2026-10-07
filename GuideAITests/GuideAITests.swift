import XCTest
@testable import GuideAI

final class ParentalPolicyTests: XCTestCase {
    func testDefaults() {
        let policy = ParentalPolicy.default
        XCTAssertEqual(policy.mode, .learning)
        XCTAssertTrue(policy.blockExternalAI)
        XCTAssertEqual(policy.dailyLimitMinutes, 45)
        XCTAssertTrue(policy.requireAttemptFirst)
        XCTAssertFalse(policy.allowFullAssignmentGeneration)
    }
}

final class DailyUsageTests: XCTestCase {
    func testRolloverNewDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let yesterday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))!
        var usage = DailyUsage(calendarDay: DailyUsage.dayKey(for: yesterday, calendar: calendar), secondsUsed: 100, requestCount: 2)
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6))!
        XCTAssertFalse(usage.isSameDay(as: today, calendar: calendar))
        usage = .fresh(for: today, calendar: calendar)
        XCTAssertEqual(usage.secondsUsed, 0)
    }

    func testLimitReached() {
        let usage = DailyUsage(calendarDay: "2026-10-06", secondsUsed: 2700, requestCount: 1)
        XCTAssertTrue(usage.isLimitReached(limitSeconds: 2700))
        XCTAssertFalse(usage.isLimitReached(limitSeconds: 2701))
    }
}

final class AIModeTests: XCTestCase {
    func testDisplayNames() {
        XCTAssertEqual(AIMode.learning.displayName, "Learning Mode")
        XCTAssertEqual(AIMode.restricted.shortName, "Restricted")
    }
}
