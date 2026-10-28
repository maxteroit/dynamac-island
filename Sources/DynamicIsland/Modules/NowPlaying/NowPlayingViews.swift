import SwiftUI

struct ArtworkView: View {
    let activity: NowPlayingActivity
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let artwork = activity.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.12)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Waveform while playing, pause glyph while paused.
struct PlaybackIndicator: View {
    let activity: NowPlayingActivity

    var body: some View {
        if activity.info?.isPlaying == true {
            WaveformView(color: activity.accentColor)
        } else {
            Image(systemName: "pause.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct NowPlayingExpandedView: View {
    let activity: NowPlayingActivity

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ArtworkView(activity: activity, size: 56, cornerRadius: 12)
                    .overlay(alignment: .bottomTrailing) {
                        if let icon = activity.appIcon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 20, height: 20)
                                .offset(x: 6, y: 6)
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.info?.title ?? "Not Playing")
                        .font(.headline)
                        .lineLimit(1)
                    Text(activity.info?.artist ?? activity.info?.album ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                PlaybackIndicator(activity: activity)
                    .frame(width: 26, height: 18)
            }
            ProgressScrubber(activity: activity)
            HStack(spacing: 40) {
                controlButton("backward.fill") { activity.previousTrack() }
                controlButton(activity.info?.isPlaying == true ? "pause.fill" : "play.fill", size: 26) {
                    activity.togglePlayPause()
                }
                controlButton("forward.fill") { activity.nextTrack() }
            }
        }
    }

    private func controlButton(_ symbol: String, size: CGFloat = 18, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Progress bar with elapsed and remaining time; drag to seek.
struct ProgressScrubber: View {
    let activity: NowPlayingActivity
    @State private var dragFraction: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let duration = activity.info?.duration ?? 0
            let elapsed = dragFraction.map { $0 * duration } ?? activity.elapsed(at: context.date)
            let fraction = duration > 0 ? min(max(elapsed / duration, 0), 1) : 0

            HStack(spacing: 8) {
                Text(TimerActivity.format(elapsed))
                    .frame(width: 40, alignment: .trailing)
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.2))
                        Capsule()
                            .fill(activity.accentColor)
                            .frame(width: proxy.size.width * fraction)
                    }
                    .frame(height: dragFraction == nil ? 5 : 8)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard duration > 0 else { return }
                                dragFraction = min(max(value.location.x / proxy.size.width, 0), 1)
                            }
                            .onEnded { _ in
                                if let dragFraction, duration > 0 {
                                    activity.seek(to: dragFraction * duration)
                                }
                                dragFraction = nil
                            }
                    )
                    .animation(.easeOut(duration: 0.15), value: dragFraction == nil)
                }
                .frame(height: 14)
                Text("-" + TimerActivity.format(max(0, duration - elapsed)))
                    .frame(width: 44, alignment: .leading)
            }
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }
}
