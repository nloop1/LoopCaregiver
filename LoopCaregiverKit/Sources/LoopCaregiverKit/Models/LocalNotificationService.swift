import Combine
import Foundation
import UserNotifications

public protocol LocalNotificationServiceProtocol: AnyObject {
    func requestAuthorizationIfNeeded() async -> Bool
    func scheduleBolusTimeoutNotification(commandId: String, amountInUnits: Double, ageSeconds: TimeInterval) async
}

/// Conforms to `ObservableObject` so SwiftUI views can inject it via `@EnvironmentObject`.
/// The service does not actually publish any state — the conformance is purely for DI.
public final class LocalNotificationService: LocalNotificationServiceProtocol, ObservableObject {

    private let center: UNUserNotificationCenterAdapter

    public init(center: UNUserNotificationCenterAdapter = UNUserNotificationCenter.current()) {
        self.center = center
    }

    public func requestAuthorizationIfNeeded() async -> Bool {
        let status = await center.authorizationStatus
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default:
            return false
        }
    }

    public func scheduleBolusTimeoutNotification(commandId: String, amountInUnits: Double, ageSeconds: TimeInterval) async {
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Bolus not confirmed", comment: "Local notification title for stale bolus")
        content.body = String(
            format: NSLocalizedString(
                "Bolus of %.1f U has not been confirmed after %.0f s. Check Loop on the recipient device.",
                comment: "Local notification body for stale bolus"
            ),
            amountInUnits, ageSeconds
        )
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "bolus-timeout-\(commandId)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}
