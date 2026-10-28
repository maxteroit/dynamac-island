import SwiftUI

struct CircleButton: View {
    let symbol: String
    var tint: Color = .white
    var size: CGFloat = 36
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
                .background(Circle().fill(.white.opacity(0.14)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Animated bars. Only runs while visible.
struct WaveformView: View {
    var color: Color = .pink
    private let barCount = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<barCount, id: \.self) { index in
                        let phase = time * 6 + Double(index) * 1.3
                        let level = 0.3 + 0.7 * abs(sin(phase) * cos(phase * 0.37))
                        Capsule()
                            .fill(color)
                            .frame(height: proxy.size.height * level)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}
