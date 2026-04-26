import Foundation
import Combine

public final class PendingCommandWatcher: ObservableObject {

    public static let defaultBolusStaleThreshold: TimeInterval = 90
    public static let defaultCarbsOverrideStaleThreshold: TimeInterval = 300

    @Published public private(set) var staleCommandIds: Set<String> = []

    private let notificationService: LocalNotificationServiceProtocol
    private let bolusStaleThreshold: TimeInterval
    private let carbsOverrideStaleThreshold: TimeInterval
    private let nowDateSource: () -> Date

    /// Tracks command-ids we've already fired a notification for, to ensure once-per-command.
    private var notifiedCommandIds: Set<String> = []

    public init(notificationService: LocalNotificationServiceProtocol,
                bolusStaleThreshold: TimeInterval = PendingCommandWatcher.defaultBolusStaleThreshold,
                carbsOverrideStaleThreshold: TimeInterval = PendingCommandWatcher.defaultCarbsOverrideStaleThreshold,
                nowDateSource: @escaping () -> Date = { Date() }) {
        self.notificationService = notificationService
        self.bolusStaleThreshold = bolusStaleThreshold
        self.carbsOverrideStaleThreshold = carbsOverrideStaleThreshold
        self.nowDateSource = nowDateSource
    }

    /// Idempotent. Call after each refresh of recentCommands.
    /// Computes which pending commands are "stale" (older than the type-specific threshold)
    /// and fires a one-shot bolus-timeout notification for newly-stale boluses.
    public func evaluate(commands: [RemoteCommand]) {
        let now = nowDateSource()
        var newStale: Set<String> = []
        var bolusToNotify: [(id: String, amount: Double, age: TimeInterval)] = []
        var pendingIds: Set<String> = []

        for command in commands {
            guard case .pending = command.status.state else { continue }
            pendingIds.insert(command.id)
            let age = now.timeIntervalSince(command.createdDate)
            switch command.action {
            case let .bolusEntry(bolus):
                if age >= bolusStaleThreshold {
                    newStale.insert(command.id)
                    if !notifiedCommandIds.contains(command.id) {
                        bolusToNotify.append((command.id, bolus.amountInUnits, age))
                        notifiedCommandIds.insert(command.id)
                    }
                }
            case .carbsEntry, .temporaryScheduleOverride, .cancelTemporaryOverride, .autobolus, .closedLoop:
                if age >= carbsOverrideStaleThreshold {
                    newStale.insert(command.id)
                }
            }
        }

        // Drop notification-tracking for commands that are no longer pending (or no longer present).
        notifiedCommandIds.formIntersection(pendingIds)

        if newStale != staleCommandIds {
            staleCommandIds = newStale
        }

        for entry in bolusToNotify {
            Task { [weak notificationService] in
                await notificationService?.scheduleBolusTimeoutNotification(
                    commandId: entry.id,
                    amountInUnits: entry.amount,
                    ageSeconds: entry.age
                )
            }
        }
    }
}
