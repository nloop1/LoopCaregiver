//
//  LifecycleStatusTests.swift
//  LoopCaregiverKitTests
//

@testable import LoopCaregiverKit
import XCTest

final class LifecycleStatusTests: XCTestCase {

    private static let germanCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "de_DE")
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return cal
    }()

    private static let testNow: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 4; c.day = 25  // Saturday
        c.hour = 18; c.minute = 38; c.second = 0
        return germanCalendar.date(from: c)!
    }()

    private func makeDisplay(
        start: Date,
        lifetime: TimeInterval = LifecycleConstants.podLifetime
    ) -> LifecycleDisplay? {
        return LifecycleStatus.computeDisplay(
            start: start,
            lifetime: lifetime,
            now: Self.testNow,
            calendar: Self.germanCalendar
        )
    }

    // MARK: - Severity & Relative Format

    func test_pod_23h_remaining_isWarning() {
        let start = Self.testNow.addingTimeInterval(-57 * 3600)
        let display = makeDisplay(start: start)!
        XCTAssertEqual(display.severity, .warning)
        XCTAssertEqual(display.relative, "23 h")
        XCTAssertFalse(display.isExpired)
    }

    func test_pod_5h_remaining_isUrgent() {
        let start = Self.testNow.addingTimeInterval(-75 * 3600)
        let display = makeDisplay(start: start)!
        XCTAssertEqual(display.severity, .urgent)
        XCTAssertEqual(display.relative, "5 h")
    }

    func test_pod_expired_1h_ago() {
        let start = Self.testNow.addingTimeInterval(-81 * 3600)
        let display = makeDisplay(start: start)!
        XCTAssertEqual(display.severity, .expired)
        XCTAssertTrue(display.isExpired)
        XCTAssertEqual(display.relative, "abgelaufen seit 1 h")
    }

    func test_pod_expired_1d4h_ago() {
        let start = Self.testNow.addingTimeInterval(-108 * 3600)
        let display = makeDisplay(start: start)!
        XCTAssertEqual(display.severity, .expired)
        XCTAssertEqual(display.relative, "abgelaufen seit 1 d 4 h")
    }

    func test_pod_2d9h_remaining_isOk() {
        let start = Self.testNow.addingTimeInterval(-23 * 3600)
        let display = makeDisplay(start: start)!
        XCTAssertEqual(display.severity, .ok)
        XCTAssertEqual(display.relative, "2 d 9 h")
    }

    func test_sensor_6d12h_remaining() {
        let start = Self.testNow.addingTimeInterval(-84 * 3600)
        let display = makeDisplay(start: start, lifetime: LifecycleConstants.sensorLifetime)!
        XCTAssertEqual(display.severity, .ok)
        XCTAssertEqual(display.relative, "6 d 12 h")
    }

    func test_sensor_7d_remaining_isJustDays() {
        let start = Self.testNow.addingTimeInterval(-72 * 3600)
        let display = makeDisplay(start: start, lifetime: LifecycleConstants.sensorLifetime)!
        XCTAssertEqual(display.severity, .ok)
        XCTAssertEqual(display.relative, "7 d")
    }

    // MARK: - Edge cases

    func test_futureDated_returnsNil() {
        let start = Self.testNow.addingTimeInterval(10 * 60)
        XCTAssertNil(makeDisplay(start: start))
    }

    func test_stale_loggingForgotten_returnsNil() {
        let start = Self.testNow.addingTimeInterval(-200 * 3600)
        XCTAssertNil(makeDisplay(start: start, lifetime: LifecycleConstants.podLifetime))
    }

    func test_emptyStatus_podDisplayIsNil() {
        let status = LifecycleStatus.empty
        XCTAssertNil(status.podDisplay(now: Self.testNow, calendar: Self.germanCalendar))
        XCTAssertNil(status.sensorDisplay(now: Self.testNow, calendar: Self.germanCalendar))
    }

    func test_status_picksUpCorrectFields() {
        let pod = Self.testNow.addingTimeInterval(-30 * 3600)
        let sensor = Self.testNow.addingTimeInterval(-50 * 3600)
        let status = LifecycleStatus(latestSensorStart: sensor, latestPodChange: pod)
        XCTAssertNotNil(status.podDisplay(now: Self.testNow, calendar: Self.germanCalendar))
        XCTAssertNotNil(status.sensorDisplay(now: Self.testNow, calendar: Self.germanCalendar))
    }

    // MARK: - Absolute Format Buckets

    private func expectedTimeString(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Self.germanCalendar
        f.locale = Self.germanCalendar.locale
        f.setLocalizedDateFormatFromTemplate("HHmm")
        return f.string(from: date)
    }

    private func expectedWeekday(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Self.germanCalendar
        f.locale = Self.germanCalendar.locale
        f.setLocalizedDateFormatFromTemplate("E")
        return f.string(from: date)
    }

    func test_absolute_today_isJustTime() {
        // Pod expires in ~3h (today)
        let start = Self.testNow.addingTimeInterval(-77 * 3600)
        let display = makeDisplay(start: start)!
        let expectedExpiry = start.addingTimeInterval(LifecycleConstants.podLifetime)
        XCTAssertEqual(display.absolute, expectedTimeString(for: expectedExpiry))
        XCTAssertFalse(display.absolute.contains("morgen"))
    }

    func test_absolute_tomorrow_hasMorgenPrefix() {
        // Pod 23h remaining → expires tomorrow (dayDiff=1)
        let start = Self.testNow.addingTimeInterval(-57 * 3600)
        let display = makeDisplay(start: start)!
        XCTAssertTrue(display.absolute.hasPrefix("morgen "), "got: \(display.absolute)")
    }

    func test_absolute_2to5days_hasWeekdayPrefix() {
        // expires in 3 days → dayDiff=3
        let start = Self.testNow.addingTimeInterval(-(80 - 3 * 24) * 3600)
        let display = makeDisplay(start: start)!
        let expectedExpiry = start.addingTimeInterval(LifecycleConstants.podLifetime)
        let weekday = expectedWeekday(for: expectedExpiry)
        XCTAssertTrue(display.absolute.hasPrefix("\(weekday) "), "got: \(display.absolute)")
    }

    func test_absolute_6plusDays_isDateFormat() {
        // Sensor 6d 12h remaining → dayDiff=7 (>=6)
        let start = Self.testNow.addingTimeInterval(-84 * 3600)
        let display = makeDisplay(start: start, lifetime: LifecycleConstants.sensorLifetime)!
        XCTAssertFalse(display.absolute.contains("morgen"))
        // German short date contains a dot or slash, no leading weekday letter
        XCTAssertTrue(
            display.absolute.contains(".") || display.absolute.contains("/"),
            "expected date-like format, got: \(display.absolute)"
        )
    }
}
