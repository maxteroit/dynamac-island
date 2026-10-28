import SwiftUI

enum HUDKind: String, Sendable {
    case volume
    case brightness
}

/// Icon + level bar shown as a transient event, replacing the system bezel visually.
enum HUD {
    static let duration: Duration = .milliseconds(1500)

    @MainActor
    static func event(kind: HUDKind, level: Float, muted: Bool = false) -> TransientEvent {
        let shownLevel = muted ? 0 : level
        return TransientEvent(
            id: "hud-\(kind.rawValue)",
            leading: AnyView(
                Image(systemName: symbol(kind: kind, level: level, muted: muted))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 22)
            ),
            trailing: AnyView(LevelBar(level: Double(shownLevel)).frame(width: 40, height: 6)),
            duration: duration
        )
    }

    static func symbol(kind: HUDKind, level: Float, muted: Bool) -> String {
        switch kind {
        case .volume:
            if muted || level <= 0 { return "speaker.slash.fill" }
            if level < 0.34 { return "speaker.wave.1.fill" }
            if level < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness:
            return level < 0.5 ? "sun.min.fill" : "sun.max.fill"
        }
    }
}

struct LevelBar: View {
    let level: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule()
                    .fill(.white)
                    .frame(width: proxy.size.width * min(max(level, 0), 1))
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: level)
    }
}
