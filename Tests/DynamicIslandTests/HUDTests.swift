import Foundation
import Testing
@testable import DynamicIsland

struct HUDTests {
    @Test(arguments: [
        (Float(0), false, "speaker.slash.fill"),
        (0.8, true, "speaker.slash.fill"),
        (0.2, false, "speaker.wave.1.fill"),
        (0.5, false, "speaker.wave.2.fill"),
        (1.0, false, "speaker.wave.3.fill"),
    ])
    func volumeSymbol(level: Float, muted: Bool, expected: String) {
        #expect(HUD.symbol(kind: .volume, level: level, muted: muted) == expected)
    }

    @Test func volumeChangeDetection() {
        let base = VolumeMonitor.Reading(volume: 0.5, muted: false)
        #expect(!VolumeMonitor.isVisibleChange(from: nil, to: base))
        #expect(!VolumeMonitor.isVisibleChange(from: base, to: base))
        #expect(VolumeMonitor.isVisibleChange(from: base, to: .init(volume: 0.5625, muted: false)))
        #expect(VolumeMonitor.isVisibleChange(from: base, to: .init(volume: 0.5, muted: true)))
    }
}

struct BrightnessChangeFilterTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 0)

    @Test func keyPressAfterQuietPeriodCounts() {
        var filter = BrightnessChangeFilter()
        filter.record(0.5, at: t0)
        // Ramp of a key press, long after the last reading.
        let rampStart = filter.record(0.51, at: t0 + 60)
        let rampEnd = filter.record(0.54, at: t0 + 60.1)
        #expect(!rampStart)
        #expect(rampEnd)
    }

    @Test func autoBrightnessDriftIsIgnored() {
        var filter = BrightnessChangeFilter()
        var level: Float = 0.5
        filter.record(level, at: t0)
        for step in 1...40 {
            level += 0.005
            let flagged = filter.record(level, at: t0 + Double(step) * 0.5)
            #expect(!flagged)
        }
    }

    @Test func firstReadingIsNotAChange() {
        var filter = BrightnessChangeFilter()
        let flagged = filter.record(0.7, at: t0)
        #expect(!flagged)
    }
}
