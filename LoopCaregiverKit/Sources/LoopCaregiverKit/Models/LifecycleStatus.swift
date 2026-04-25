//
//  LifecycleStatus.swift
//  LoopCaregiverKit
//

import Foundation

public struct LifecycleStatus: Equatable {
    public let latestSensorStart: Date?
    public let latestPodChange: Date?

    public init(latestSensorStart: Date? = nil, latestPodChange: Date? = nil) {
        self.latestSensorStart = latestSensorStart
        self.latestPodChange = latestPodChange
    }

    public static let empty = LifecycleStatus()
}

public enum LifecycleSeverity: Equatable {
    case ok       // remaining > 24h
    case warning  // 6h <= remaining <= 24h
    case urgent   // 0 < remaining < 6h
    case expired  // remaining <= 0
}

public struct LifecycleDisplay: Equatable {
    public let absolute: String
    public let relative: String
    public let severity: LifecycleSeverity
    public let isExpired: Bool

    public init(absolute: String, relative: String, severity: LifecycleSeverity, isExpired: Bool) {
        self.absolute = absolute
        self.relative = relative
        self.severity = severity
        self.isExpired = isExpired
    }
}

public extension LifecycleStatus {
    func podDisplay(now: Date = Date(), calendar: Calendar = .current) -> LifecycleDisplay? {
        guard let start = latestPodChange else { return nil }
        return Self.computeDisplay(
            start: start,
            lifetime: LifecycleConstants.podLifetime,
            now: now,
            calendar: calendar
        )
    }

    func sensorDisplay(now: Date = Date(), calendar: Calendar = .current) -> LifecycleDisplay? {
        guard let start = latestSensorStart else { return nil }
        return Self.computeDisplay(
            start: start,
            lifetime: LifecycleConstants.sensorLifetime,
            now: now,
            calendar: calendar
        )
    }

    static func computeDisplay(
        start: Date,
        lifetime: TimeInterval,
        now: Date,
        calendar: Calendar
    ) -> LifecycleDisplay? {
        guard start <= now else { return nil }

        let age = now.timeIntervalSince(start)
        if age > lifetime + LifecycleConstants.staleLogTolerance {
            return nil
        }

        let expiry = start.addingTimeInterval(lifetime)
        let remaining = expiry.timeIntervalSince(now)

        let severity: LifecycleSeverity
        if remaining <= 0 {
            severity = .expired
        } else if remaining < LifecycleConstants.urgentThreshold {
            severity = .urgent
        } else if remaining <= LifecycleConstants.warningThreshold {
            severity = .warning
        } else {
            severity = .ok
        }

        return LifecycleDisplay(
            absolute: formatAbsolute(expiry: expiry, now: now, calendar: calendar),
            relative: formatRelative(remaining: remaining),
            severity: severity,
            isExpired: remaining <= 0
        )
    }

    static func formatRelative(remaining: TimeInterval) -> String {
        if remaining <= 0 {
            return "abgelaufen seit \(formatPositiveInterval(abs(remaining)))"
        }
        return formatPositiveInterval(remaining)
    }

    private static func formatPositiveInterval(_ interval: TimeInterval) -> String {
        let oneDay: TimeInterval = 86400
        let oneWeek: TimeInterval = 7 * oneDay

        if interval < oneDay {
            let hours = Int((interval / 3600).rounded())
            return "\(hours) h"
        } else if interval < oneWeek {
            let totalHours = Int(interval / 3600)
            let days = totalHours / 24
            let hours = totalHours % 24
            return "\(days) d \(hours) h"
        } else {
            let days = Int((interval / oneDay).rounded())
            return "\(days) d"
        }
    }

    static func formatAbsolute(expiry: Date, now: Date, calendar: Calendar) -> String {
        let nowDayStart = calendar.startOfDay(for: now)
        let expiryDayStart = calendar.startOfDay(for: expiry)
        let dayDiff = calendar.dateComponents([.day], from: nowDayStart, to: expiryDayStart).day ?? 0

        let locale = calendar.locale ?? Locale.current

        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.locale = locale
        timeFormatter.setLocalizedDateFormatFromTemplate("HHmm")
        let timeString = timeFormatter.string(from: expiry)

        switch dayDiff {
        case 0:
            return timeString
        case 1:
            return "morgen \(timeString)"
        case 2...5:
            let weekdayFormatter = DateFormatter()
            weekdayFormatter.calendar = calendar
            weekdayFormatter.locale = locale
            weekdayFormatter.setLocalizedDateFormatFromTemplate("E")
            let weekday = weekdayFormatter.string(from: expiry)
            return "\(weekday) \(timeString)"
        default:
            let dateFormatter = DateFormatter()
            dateFormatter.calendar = calendar
            dateFormatter.locale = locale
            dateFormatter.setLocalizedDateFormatFromTemplate("dMHHmm")
            return dateFormatter.string(from: expiry)
        }
    }
}
