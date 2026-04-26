//
//  LifecycleConstants.swift
//  LoopCaregiverKit
//

import Foundation

public enum LifecycleConstants {
    /// Omnipod Dash (and Eros) nominal lifetime: 72h scheduled + 8h grace.
    public static let podLifetime: TimeInterval = 80 * 3600

    /// Dexcom G7 nominal lifetime: 10 days. Grace (12h) is intentionally not
    /// included so the display reflects when the change *should* happen, not
    /// when it absolutely must.
    public static let sensorLifetime: TimeInterval = 240 * 3600

    public static let warningThreshold: TimeInterval = 24 * 3600
    public static let urgentThreshold: TimeInterval = 6 * 3600

    /// If a lifecycle event is older than `lifetime + staleLogTolerance`, the
    /// log entry is treated as stale (forgotten) and not shown.
    public static let staleLogTolerance: TimeInterval = 48 * 3600
}
