import AudioToolbox
import CoreAudio
import OSLog

/// Shows a volume HUD whenever the default output device's volume or mute changes.
/// Observe-only: the system bezel still appears too.
@MainActor
final class VolumeMonitor {
    struct Reading: Equatable {
        var volume: Float
        var muted: Bool
    }

    private let logger = Logger(subsystem: "com.adittyasubagja.dynamicisland", category: "HUD")
    private weak var manager: ActivityManager?
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var last: Reading?
    private var deviceListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    init(manager: ActivityManager) {
        self.manager = manager
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.attachToDefaultDevice() }
        }
        attachToDefaultDevice()
    }

    /// Re-targets listeners after the output changes (AirPods, HDMI). The new
    /// device's level becomes the baseline without showing a HUD.
    private func attachToDefaultDevice() {
        for (address, block) in deviceListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, .main, block)
        }
        deviceListeners.removeAll()

        deviceID = Self.defaultOutputDevice()
        last = Self.read(deviceID)
        guard deviceID != kAudioObjectUnknown else { return }

        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            var address = Self.address(selector, scope: kAudioDevicePropertyScopeOutput)
            guard AudioObjectHasProperty(deviceID, &address) else { continue }
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.levelChanged() }
            }
            if AudioObjectAddPropertyListenerBlock(deviceID, &address, .main, block) == noErr {
                deviceListeners.append((address, block))
            }
        }
        if deviceListeners.isEmpty {
            logger.info("Output device \(self.deviceID) has no software volume")
        }
    }

    private func levelChanged() {
        guard let reading = Self.read(deviceID) else { return }
        defer { last = reading }
        guard Self.isVisibleChange(from: last, to: reading) else { return }
        manager?.present(HUD.event(kind: .volume, level: reading.volume, muted: reading.muted))
    }

    nonisolated static func isVisibleChange(from old: Reading?, to new: Reading) -> Bool {
        guard let old else { return false }
        return old.muted != new.muted || abs(old.volume - new.volume) > 0.001
    }

    // MARK: - CoreAudio

    private nonisolated static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private nonisolated static func defaultOutputDevice() -> AudioObjectID {
        var address = address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }

    private nonisolated static func read(_ device: AudioObjectID) -> Reading? {
        guard device != kAudioObjectUnknown else { return nil }
        var volumeAddress = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectHasProperty(device, &volumeAddress),
              AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &volume) == noErr
        else { return nil }

        var muteAddress = address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        var muted = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(device, &muteAddress) {
            AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &muted)
        }
        return Reading(volume: volume, muted: muted != 0)
    }
}
