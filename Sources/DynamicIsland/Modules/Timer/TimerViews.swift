import SwiftUI

/// Live countdown while running, frozen value while paused.
struct TimerText: View {
    let timer: TimerActivity

    var body: some View {
        Group {
            if let endDate = timer.endDate, endDate > .now {
                // Text updates itself; no per-second state changes needed.
                Text(timerInterval: Date.now...endDate, countsDown: true)
            } else {
                Text(TimerActivity.format(timer.remaining()))
            }
        }
        .monospacedDigit()
    }
}

struct TimerRing: View {
    let timer: TimerActivity
    var lineWidth: CGFloat = 3

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let progress = timer.progress(at: context.date)
            ZStack {
                Circle()
                    .stroke(.orange.opacity(0.25), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.orange, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
            }
        }
    }
}

struct TimerExpandedView: View {
    let timer: TimerActivity

    var body: some View {
        HStack(spacing: 18) {
            TimerRing(timer: timer, lineWidth: 6)
                .frame(width: 64, height: 64)
                .overlay(Image(systemName: "timer").font(.title2).foregroundStyle(.orange))
            VStack(alignment: .leading, spacing: 2) {
                Text(timer.isPaused ? "Paused" : "Timer")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TimerText(timer: timer)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.orange)
            }
            Spacer()
            HStack(spacing: 10) {
                CircleButton(symbol: "plus") { timer.addMinute() }
                CircleButton(symbol: timer.isPaused ? "play.fill" : "pause.fill", tint: .orange) {
                    timer.isPaused ? timer.resume() : timer.pause()
                }
                CircleButton(symbol: "xmark", tint: .red) { timer.stop() }
            }
        }
        .frame(maxHeight: .infinity)
    }
}
