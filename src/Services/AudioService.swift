import AppKit
import CoreAudio

/// 读取 / 设置系统默认输出音量（用于 HUD 与岛内滑杆）
final class AudioService {
    static let shared = AudioService()

    private var deviceID: AudioDeviceID {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return device
    }

    func volume() -> Double {
        let device = deviceID
        guard device != 0 else { return 0 }

        for element in [kAudioObjectPropertyElementMain, 1, 2] as [UInt32] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: element
            )
            guard AudioObjectHasProperty(device, &address) else { continue }
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
            if status == noErr, value > 0 {
                return Double(value)
            }
        }
        return 0
    }

    func setVolume(_ value: Double) {
        let device = deviceID
        guard device != 0 else { return }
        let clamped = Float32(min(max(value, 0), 1))

        for element in [kAudioObjectPropertyElementMain, 1, 2] as [UInt32] {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: element
            )
            guard AudioObjectHasProperty(device, &address) else { continue }
            var v = clamped
            let size = UInt32(MemoryLayout<Float32>.size)
            AudioObjectSetPropertyData(device, &address, 0, nil, size, &v)
        }
    }
}
