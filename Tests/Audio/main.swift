// SPDX-License-Identifier: GPL-3.0-only
import AppKit

func require(_ condition: Bool, _ message: String) {
    guard condition else { fputs("FAIL \(message)\n", stderr); exit(1) }
    print("PASS \(message)")
}

let reminder = ReminderAudio()
let preview = ReminderAudio()
require(reminder.play(.submarine, volume: 0) && reminder.isPlaying, "提醒音频进入播放状态")
require(preview.play(.submarine, volume: 0) && preview.isPlaying, "同音效试听独立播放")
preview.stop()
require(reminder.isPlaying && !preview.isPlaying, "停止试听不停止正式提示音")
reminder.stop()
require(!reminder.isPlaying, "停止提醒结束播放")
for choice in SoundChoice.allCases where choice != .silent {
    require(reminder.play(choice, volume: 0) && reminder.isPlaying, "\(choice.rawValue) 播放成功")
    reminder.stop()
}
require(!reminder.play(.silent, volume: 0) && !reminder.isPlaying, "静音选项不播放")
print("11 audio checks passed; playback volume was 0; speaker output was not measured.")
