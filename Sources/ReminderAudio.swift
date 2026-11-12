// SPDX-License-Identifier: GPL-3.0-only
import AppKit
import CoreAudio

protocol ReminderSoundPlaying: AnyObject {
    @discardableResult func play(_ choice: SoundChoice, volume: Float) -> Bool
    func stop()
}

final class ReminderAudio: ReminderSoundPlaying {
    private var current: NSSound?
    private var fallback: NSSound?
    private var selected: SoundChoice?

    var isPlaying: Bool { current?.isPlaying == true || fallback?.isPlaying == true }

    @discardableResult func play(_ choice: SoundChoice, volume: Float) -> Bool {
        guard choice != .silent else { stop(); return false }
        if selected != choice {
            stop()
            selected = choice
            // Named sounds are cached; preview and reminders need independent playback objects.
            current = choice == .chime ? nil : NSSound(named: NSSound.Name(choice.rawValue))?.copy() as? NSSound
            if let url = Bundle.main.url(forResource: "reminder", withExtension: "wav") {
                fallback = NSSound(contentsOf: url, byReference: false)
            }
        }
        current?.volume = min(1, max(0, volume))
        if current?.play() == true { return true }
        fallback?.volume = min(1, max(0, volume))
        if fallback?.play() == true { return true }
        fputs("提示音播放失败，窗口提醒继续显示。\n", stderr)
        return false
    }

    func stop() { current?.stop(); fallback?.stop() }
}

enum SystemAudioStatus {
    static func warning() -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var muted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(device, &address),
           AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr, muted != 0 {
            return "Mac 系统已静音，提示音不会出声；请在系统控制中心取消静音。"
        }
        var volumes: [Float32] = []
        for channel: UInt32 in [0, 1, 2] {
            address.mSelector = kAudioDevicePropertyVolumeScalar
            address.mElement = channel
            var volume: Float32 = 0
            size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectHasProperty(device, &address),
               AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr {
                if channel == 0 { return volume <= 0 ? "Mac 系统音量为 0，提示音不会出声；请在系统控制中心调高音量。" : nil }
                volumes.append(volume)
            }
        }
        return volumes.count == 2 && volumes.allSatisfy { $0 <= 0 } ? "Mac 系统音量为 0，请在系统控制中心调高音量。" : nil
    }
}
