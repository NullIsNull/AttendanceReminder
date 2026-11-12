// SPDX-License-Identifier: GPL-3.0-only
import AppKit

protocol ReminderSoundPlaying: AnyObject {
    func play(_ choice: SoundChoice, volume: Float)
    func stop()
}

final class ReminderAudio: ReminderSoundPlaying {
    private var current: NSSound?
    private var fallback: NSSound?
    private var selected: SoundChoice?

    func play(_ choice: SoundChoice, volume: Float) {
        guard choice != .silent else { stop(); return }
        if selected != choice {
            stop()
            selected = choice
            current = choice == .chime ? nil : NSSound(named: NSSound.Name(choice.rawValue))
            if let url = Bundle.main.url(forResource: "reminder", withExtension: "wav") {
                fallback = NSSound(contentsOf: url, byReference: false)
            }
        }
        current?.volume = min(1, max(0, volume))
        if current?.play() != true {
            fallback?.volume = min(1, max(0, volume))
            if fallback?.play() != true { fputs("提示音播放失败，窗口提醒继续显示。\n", stderr) }
        }
    }

    func stop() { current?.stop(); fallback?.stop() }
}
