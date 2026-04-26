//
//  LifecycleStatusView.swift
//  LoopCaregiver
//

import LoopCaregiverKit
import SwiftUI

public struct LifecycleStatusView: View {
    let status: LifecycleStatus

    public init(status: LifecycleStatus) {
        self.status = status
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let pod = status.podDisplay() {
                LifecycleRowView(
                    icon: "drop.fill",
                    label: "Pod",
                    display: pod
                )
            }
            if let sensor = status.sensorDisplay() {
                LifecycleRowView(
                    icon: "dot.radiowaves.left.and.right",
                    label: "Sensor",
                    display: sensor
                )
            }
        }
        .font(.footnote)
    }
}

private struct LifecycleRowView: View {
    let icon: String
    let label: String
    let display: LifecycleDisplay

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .frame(width: 14)
            Text(label)
                .frame(width: 50, alignment: .leading)
            if display.isExpired {
                Text(display.relative)
            } else {
                (Text("bis ") + Text(display.absolute).bold())
                Text("(\(display.relative))")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(color(for: display.severity))
    }

    private func color(for severity: LifecycleSeverity) -> Color {
        switch severity {
        case .ok: return .primary
        case .warning: return .orange
        case .urgent, .expired: return .red
        }
    }
}

#Preview("Pod normal, Sensor warning") {
    LifecycleStatusView(status: LifecycleStatus(
        latestSensorStart: Date().addingTimeInterval(-238 * 3600),
        latestPodChange: Date().addingTimeInterval(-57 * 3600)
    ))
    .padding()
}

#Preview("Pod urgent, Sensor expired") {
    LifecycleStatusView(status: LifecycleStatus(
        latestSensorStart: Date().addingTimeInterval(-242 * 3600),
        latestPodChange: Date().addingTimeInterval(-77 * 3600)
    ))
    .padding()
}

#Preview("Empty") {
    LifecycleStatusView(status: .empty)
        .padding()
}
