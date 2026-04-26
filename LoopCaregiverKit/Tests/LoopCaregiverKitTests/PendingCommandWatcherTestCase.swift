import XCTest
@testable import LoopCaregiverKit

final class PendingCommandWatcherTestCase: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_730_000_000)
    private var notifications: MockLocalNotificationService!

    override func setUp() {
        super.setUp()
        notifications = MockLocalNotificationService()
    }

    private func makeWatcher(bolus: TimeInterval = 90, carbs: TimeInterval = 300) -> PendingCommandWatcher {
        return PendingCommandWatcher(
            notificationService: notifications,
            bolusStaleThreshold: bolus,
            carbsOverrideStaleThreshold: carbs,
            nowDateSource: { self.now }
        )
    }

    private func makePending(id: String, action: Action, ageSeconds: TimeInterval) -> RemoteCommand {
        let createdDate = now.addingTimeInterval(-ageSeconds)
        return RemoteCommand(id: id, action: action,
                              status: RemoteCommandStatus(state: .pending, message: ""),
                              createdDate: createdDate)
    }

    private func makeNonPending(id: String, action: Action, ageSeconds: TimeInterval, state: RemoteCommandStatus.RemoteComandState) -> RemoteCommand {
        let createdDate = now.addingTimeInterval(-ageSeconds)
        return RemoteCommand(id: id, action: action,
                              status: RemoteCommandStatus(state: state, message: ""),
                              createdDate: createdDate)
    }

    private func makeBolus(units: Double = 1.0) -> Action {
        return .bolusEntry(BolusAction(amountInUnits: units))
    }

    private func makeCarbs(grams: Double = 30) -> Action {
        // CarbAction init: (amountInGrams:absorptionTime:foodType:startDate:)
        return .carbsEntry(CarbAction(amountInGrams: grams, absorptionTime: 3 * 3600, foodType: nil, startDate: now))
    }

    func testEvaluate_BolusUnder90s_NotStale() async throws {
        let watcher = makeWatcher()
        watcher.evaluate(commands: [makePending(id: "b1", action: makeBolus(units: 1.0), ageSeconds: 60)])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(watcher.staleCommandIds.isEmpty)
        XCTAssertEqual(notifications.scheduledBolusCount, 0)
    }

    func testEvaluate_BolusOver90s_IsStaleAndNotifies() async throws {
        let watcher = makeWatcher()
        watcher.evaluate(commands: [makePending(id: "b1", action: makeBolus(units: 2.0), ageSeconds: 95)])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(watcher.staleCommandIds.contains("b1"))
        XCTAssertEqual(notifications.scheduledBolusCount, 1)
        XCTAssertEqual(notifications.lastScheduled?.commandId, "b1")
        XCTAssertEqual(notifications.lastScheduled?.amount, 2.0)
    }

    func testEvaluate_BolusOver90s_TwoEvaluations_FiresOnlyOnce() async throws {
        let watcher = makeWatcher()
        let bolus = makePending(id: "b1", action: makeBolus(units: 2.0), ageSeconds: 95)
        watcher.evaluate(commands: [bolus])
        try await Task.sleep(nanoseconds: 100_000_000)
        watcher.evaluate(commands: [bolus])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(notifications.scheduledBolusCount, 1)
    }

    func testEvaluate_BolusReachesSuccess_ClearedFromStale() async throws {
        let watcher = makeWatcher()
        watcher.evaluate(commands: [makePending(id: "b1", action: makeBolus(units: 2.0), ageSeconds: 95)])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(watcher.staleCommandIds.contains("b1"))

        let succeeded = makeNonPending(id: "b1", action: makeBolus(units: 2.0), ageSeconds: 96, state: .success)
        watcher.evaluate(commands: [succeeded])
        XCTAssertFalse(watcher.staleCommandIds.contains("b1"))
    }

    func testEvaluate_CarbsUnder5min_NotStale() {
        let watcher = makeWatcher()
        watcher.evaluate(commands: [makePending(id: "c1", action: makeCarbs(), ageSeconds: 240)])
        XCTAssertFalse(watcher.staleCommandIds.contains("c1"))
        XCTAssertEqual(notifications.scheduledBolusCount, 0)
    }

    func testEvaluate_CarbsOver5min_IsStaleNoNotification() {
        let watcher = makeWatcher()
        watcher.evaluate(commands: [makePending(id: "c1", action: makeCarbs(), ageSeconds: 305)])
        XCTAssertTrue(watcher.staleCommandIds.contains("c1"))
        XCTAssertEqual(notifications.scheduledBolusCount, 0)
    }

    func testEvaluate_MultipleCommands_TrackedIndependently() async throws {
        let watcher = makeWatcher()
        let staleBolus = makePending(id: "b1", action: makeBolus(units: 1.0), ageSeconds: 95)
        let freshBolus = makePending(id: "b2", action: makeBolus(units: 1.0), ageSeconds: 30)
        watcher.evaluate(commands: [staleBolus, freshBolus])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(watcher.staleCommandIds.contains("b1"))
        XCTAssertFalse(watcher.staleCommandIds.contains("b2"))
        XCTAssertEqual(notifications.scheduledBolusCount, 1)
    }

    func testEvaluate_BolusRemovedFromList_NotificationTrackingResets() async throws {
        let watcher = makeWatcher()
        watcher.evaluate(commands: [makePending(id: "b1", action: makeBolus(units: 2.0), ageSeconds: 95)])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(notifications.scheduledBolusCount, 1)

        // Same command-id appears again (e.g., user deleted + re-sent same id — pathological but defensive)
        watcher.evaluate(commands: [])  // command no longer present
        watcher.evaluate(commands: [makePending(id: "b1", action: makeBolus(units: 2.0), ageSeconds: 95)])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(notifications.scheduledBolusCount, 2,
                        "after the command leaves and re-appears, notification fires again")
    }
}

final class MockLocalNotificationService: LocalNotificationServiceProtocol {
    private(set) var scheduledBolusCount = 0
    private(set) var lastScheduled: (commandId: String, amount: Double, age: TimeInterval)?

    func requestAuthorizationIfNeeded() async -> Bool { return true }

    func scheduleBolusTimeoutNotification(commandId: String, amountInUnits: Double, ageSeconds: TimeInterval) async {
        scheduledBolusCount += 1
        lastScheduled = (commandId, amountInUnits, ageSeconds)
    }
}
