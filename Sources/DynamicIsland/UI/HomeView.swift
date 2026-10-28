import SwiftUI

/// Expanded content when no activity is running: clock, battery, quick timers.
struct HomeView: View {
    let timer: TimerActivity
    let battery: BatteryMonitor

    static let timerPresets = [1, 5, 15, 25]

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                TimelineView(.everyMinute) { context in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.date, format: .dateTime.hour().minute())
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                if let status = battery.status, status.hasBattery {
                    HStack(spacing: 6) {
                        BatteryGlyph(level: status.level, color: status.isCharging ? .green : .white)
                        Text("\(status.level)%")
                        if status.isCharging {
                            Image(systemName: "bolt.fill").foregroundStyle(.green)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Label("Timer", systemImage: "timer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(Self.timerPresets, id: \.self) { minutes in
                        Button {
                            timer.start(minutes: Double(minutes))
                        } label: {
                            Text("\(minutes)m")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.orange)
                                .frame(width: 42, height: 32)
                                .background(Capsule().fill(.orange.opacity(0.18)))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }
}
