import Observation
import SwiftUI

/// Fake "now playing" activity for testing layouts. Toggled from the dev menu.
/// Replaced by the real Now Playing module in Phase 3.
@MainActor
@Observable
final class DemoActivity: LiveActivity {
    let id = "demo"
    let priority = ActivityPriority.normal
    private(set) var activatedAt: Date?

    var isEnabled: Bool { activatedAt != nil }

    func toggle() {
        withAnimation(.islandExpand) {
            activatedAt = isEnabled ? nil : .now
        }
    }

    func compactLeading() -> AnyView {
        AnyView(Image(systemName: "music.note").foregroundStyle(.pink))
    }

    func compactTrailing() -> AnyView {
        AnyView(WaveformView().frame(width: 22, height: 14))
    }

    func minimal() -> AnyView {
        AnyView(WaveformView())
    }

    func expanded() -> AnyView {
        AnyView(DemoExpandedView())
    }
}

private struct DemoExpandedView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [.pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 52, height: 52)
                    .overlay(Image(systemName: "music.note").font(.title2).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Demo Activity")
                        .font(.headline)
                    Text("Now Playing arrives in Phase 3")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                WaveformView()
                    .frame(width: 28, height: 18)
            }
            HStack(spacing: 36) {
                ForEach(["backward.fill", "play.fill", "forward.fill"], id: \.self) { symbol in
                    Image(systemName: symbol)
                        .font(.system(size: symbol == "play.fill" ? 26 : 20))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
