import Carbon.HIToolbox
import Foundation

@main
struct ShortcutVoiceSmoke {
  static func main() {
    let shortcuts = AppShortcut.allCases
    precondition(Set(shortcuts.map(\.hotKeyID)).count == shortcuts.count)
    precondition(Set(shortcuts.map(\.keyCode)).count == shortcuts.count)

    precondition(AppShortcut.closeReading.keyCode == UInt32(kVK_ANSI_T))
    precondition(AppShortcut.closeReading.mode == .closeReading)
    precondition(AppShortcut.replies.keyCode == UInt32(kVK_ANSI_L))
    precondition(AppShortcut.replies.mode == .replies)
    precondition(AppShortcut.howToSay.keyCode == UInt32(kVK_ANSI_H))
    precondition(AppShortcut.howToSay.mode == .howToSay)

    precondition(
      ShortcutPanelPolicy.transition(
        isVisible: true,
        activeMode: .howToSay,
        requestedMode: .howToSay
      ) == .hide
    )
    precondition(
      ShortcutPanelPolicy.transition(
        isVisible: true,
        activeMode: .closeReading,
        requestedMode: .replies
      ) == .switchMode
    )
    precondition(
      ShortcutPanelPolicy.transition(
        isVisible: false,
        activeMode: .replies,
        requestedMode: .replies
      ) == .show
    )

    // Target-language selection must never change speech recognition into
    // translation. With the Chinese UI, an empty or Latin-only input is
    // still captured and transcribed as Chinese.
    precondition(
      SpeechLocaleResolver.localeID(
        interfaceLanguage: .simplifiedChinese,
        existingText: ""
      ) == "zh-CN"
    )
    precondition(
      SpeechLocaleResolver.localeID(
        interfaceLanguage: .simplifiedChinese,
        existingText: "draft"
      ) == "zh-CN"
    )
    precondition(
      SpeechLocaleResolver.localeID(
        interfaceLanguage: .english,
        existingText: "请帮我写得自然一些"
      ) == "zh-CN"
    )
    precondition(
      SpeechLocaleResolver.localeID(
        interfaceLanguage: .english,
        existingText: ""
      ) == "en-US"
    )

    print("SHORTCUT_VOICE_SMOKE_OK")
  }
}
