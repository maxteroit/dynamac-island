import SwiftUI

struct BatteryLabel: View {
    let level: Int
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Text("\(level)%")
                .monospacedDigit()
                .foregroundStyle(color)
            BatteryGlyph(level: level, color: color)
        }
    }
}

/// Battery outline with a fill proportional to `level`.
struct BatteryGlyph: View {
    let level: Int
    let color: Color
    var width: CGFloat = 22
    var height: CGFloat = 11

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(color.opacity(0.5), lineWidth: 1)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(color)
                    .frame(width: max(1, (width - 4) * CGFloat(min(max(level, 0), 100)) / 100))
                    .padding(2)
            }
            .frame(width: width, height: height)
            RoundedRectangle(cornerRadius: 1)
                .fill(color.opacity(0.5))
                .frame(width: 1.5, height: height * 0.4)
        }
    }
}
