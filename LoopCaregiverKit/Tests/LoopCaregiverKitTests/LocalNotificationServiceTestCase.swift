import XCTest
import UserNotifications
@testable import LoopCaregiverKit

final class LocalNotificationServiceTestCase: XCTestCase {

    func testRequestAuthorizationIfNeeded_NotDetermined_RequestsAuthorization() async {
        let center = MockNotificationCenter()
        center.nextAuthStatus = .notDetermined
        center.nextRequestAuthorizationResult = true
        let service = LocalNotificationService(center: center)

        let granted = await service.requestAuthorizationIfNeeded()

        XCTAssertTrue(granted)
        XCTAssertEqual(center.requestAuthorizationCallCount, 1)
        XCTAssertEqual(center.lastRequestedOptions, [.alert, .sound])
    }

    func testRequestAuthorizationIfNeeded_AlreadyAuthorized_ReturnsTrueWithoutPrompt() async {
        let center = MockNotificationCenter()
        center.nextAuthStatus = .authorized
        let service = LocalNotificationService(center: center)

        let granted = await service.requestAuthorizationIfNeeded()

        XCTAssertTrue(granted)
        XCTAssertEqual(center.requestAuthorizationCallCount, 0)
    }

    func testRequestAuthorizationIfNeeded_Denied_ReturnsFalse() async {
        let center = MockNotificationCenter()
        center.nextAuthStatus = .denied
        let service = LocalNotificationService(center: center)

        let granted = await service.requestAuthorizationIfNeeded()

        XCTAssertFalse(granted)
        XCTAssertEqual(center.requestAuthorizationCallCount, 0)
    }

    func testRequestAuthorizationIfNeeded_NotDeterminedAndUserDenies_ReturnsFalse() async {
        let center = MockNotificationCenter()
        center.nextAuthStatus = .notDetermined
        center.nextRequestAuthorizationResult = false
        let service = LocalNotificationService(center: center)

        let granted = await service.requestAuthorizationIfNeeded()

        XCTAssertFalse(granted)
        XCTAssertEqual(center.requestAuthorizationCallCount, 1)
    }

    func testScheduleBolusTimeoutNotification_AddsRequestWithExpectedShape() async {
        let center = MockNotificationCenter()
        let service = LocalNotificationService(center: center)

        await service.scheduleBolusTimeoutNotification(commandId: "abc", amountInUnits: 2.5, ageSeconds: 95)

        XCTAssertEqual(center.addedRequests.count, 1)
        let req = center.addedRequests[0]
        XCTAssertEqual(req.identifier, "bolus-timeout-abc")
        XCTAssertTrue(req.content.title.contains("Bolus"))
        XCTAssertTrue(req.content.body.contains("2.5"))
        XCTAssertNil(req.trigger, "immediate notification should have nil trigger")
    }

    func testScheduleBolusTimeoutNotification_DifferentCommandIds_DistinctIdentifiers() async {
        let center = MockNotificationCenter()
        let service = LocalNotificationService(center: center)

        await service.scheduleBolusTimeoutNotification(commandId: "id-1", amountInUnits: 1.0, ageSeconds: 90)
        await service.scheduleBolusTimeoutNotification(commandId: "id-2", amountInUnits: 1.0, ageSeconds: 90)

        XCTAssertEqual(center.addedRequests.count, 2)
        XCTAssertEqual(center.addedRequests[0].identifier, "bolus-timeout-id-1")
        XCTAssertEqual(center.addedRequests[1].identifier, "bolus-timeout-id-2")
    }
}

final class MockNotificationCenter: UNUserNotificationCenterAdapter {
    var nextAuthStatus: UNAuthorizationStatus = .notDetermined
    var nextRequestAuthorizationResult: Bool = true
    var requestAuthorizationCallCount = 0
    var lastRequestedOptions: UNAuthorizationOptions?
    var addedRequests: [UNNotificationRequest] = []

    var authorizationStatus: UNAuthorizationStatus {
        get async { nextAuthStatus }
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        requestAuthorizationCallCount += 1
        lastRequestedOptions = options
        return nextRequestAuthorizationResult
    }

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }
}
