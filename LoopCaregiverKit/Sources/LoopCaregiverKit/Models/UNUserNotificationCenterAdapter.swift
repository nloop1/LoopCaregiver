import Foundation
import UserNotifications

/// Test seam for UNUserNotificationCenter. Production uses `UNUserNotificationCenter.current()`.
public protocol UNUserNotificationCenterAdapter: AnyObject {
    var authorizationStatus: UNAuthorizationStatus { get async }
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
}

extension UNUserNotificationCenter: UNUserNotificationCenterAdapter {
    public var authorizationStatus: UNAuthorizationStatus {
        get async {
            await withCheckedContinuation { continuation in
                self.getNotificationSettings { settings in
                    continuation.resume(returning: settings.authorizationStatus)
                }
            }
        }
    }
}
