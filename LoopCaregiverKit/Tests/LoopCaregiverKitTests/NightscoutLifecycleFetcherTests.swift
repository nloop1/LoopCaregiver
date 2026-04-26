//
//  NightscoutLifecycleFetcherTests.swift
//  LoopCaregiverKitTests
//

@testable import LoopCaregiverKit
import XCTest

final class NightscoutLifecycleFetcherTests: XCTestCase {

    func test_parseLifecycle_picksLatestSensorStart() {
        let entries: [[String: Any]] = [
            ["eventType": "Sensor Start", "created_at": "2026-04-22T04:38:31.000Z"],
            ["eventType": "Sensor Change", "created_at": "2026-04-15T08:12:00.000Z"],
            ["eventType": "Bolus", "created_at": "2026-04-25T10:00:00.000Z"]
        ]

        let status = NightscoutLifecycleFetcher.parseLifecycle(entries: entries)

        XCTAssertEqual(
            status.latestSensorStart,
            ISO8601DateFormatter.withFractional.date(from: "2026-04-22T04:38:31.000Z")
        )
        XCTAssertNil(status.latestPodChange)
    }

    func test_parseLifecycle_picksLatestSiteOrPodChange() {
        let entries: [[String: Any]] = [
            ["eventType": "Site Change", "created_at": "2026-04-23T07:25:37.000Z"],
            ["eventType": "Pod Change", "created_at": "2026-04-20T18:00:00.000Z"],
            ["eventType": "Pump Site Change", "created_at": "2026-04-10T09:15:00.000Z"]
        ]

        let status = NightscoutLifecycleFetcher.parseLifecycle(entries: entries)

        XCTAssertEqual(
            status.latestPodChange,
            ISO8601DateFormatter.withFractional.date(from: "2026-04-23T07:25:37.000Z")
        )
    }

    func test_parseLifecycle_handlesMissingMillis() {
        let entries: [[String: Any]] = [
            ["eventType": "Sensor Start", "created_at": "2026-04-22T04:38:31Z"]
        ]
        let status = NightscoutLifecycleFetcher.parseLifecycle(entries: entries)
        XCTAssertNotNil(status.latestSensorStart)
    }

    func test_parseLifecycle_fallsBackToTimestampField() {
        let entries: [[String: Any]] = [
            ["eventType": "Site Change", "timestamp": "2026-04-23T07:25:00.000Z"]
        ]
        let status = NightscoutLifecycleFetcher.parseLifecycle(entries: entries)
        XCTAssertNotNil(status.latestPodChange)
    }

    func test_parseLifecycle_skipsUnknownEventTypes() {
        let entries: [[String: Any]] = [
            ["eventType": "Note", "created_at": "2026-04-24T12:00:00.000Z"],
            ["eventType": "Carb Correction", "created_at": "2026-04-24T13:00:00.000Z"]
        ]
        let status = NightscoutLifecycleFetcher.parseLifecycle(entries: entries)
        XCTAssertNil(status.latestSensorStart)
        XCTAssertNil(status.latestPodChange)
    }

    func test_parseLifecycle_emptyArray() {
        let status = NightscoutLifecycleFetcher.parseLifecycle(entries: [])
        XCTAssertNil(status.latestSensorStart)
        XCTAssertNil(status.latestPodChange)
    }
}

private extension ISO8601DateFormatter {
    static let withFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
