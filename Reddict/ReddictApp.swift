import AppKit
import Carbon.HIToolbox
import SwiftUI

@main
struct ReddictApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    Settings {
      EmptyView()
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem?
  private var panelController: FloatingPanelController?
  private var servicesProvider: SelectionServicesProvider?
  private var globalHotKeys: [AppShortcut: GlobalHotKey] = [:]

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)

    let panelController = FloatingPanelController()
    let servicesProvider = SelectionServicesProvider(panelController: panelController)
    self.panelController = panelController
    self.servicesProvider = servicesProvider
    NSApp.servicesProvider = servicesProvider
    for shortcut in AppShortcut.allCases {
      let hotKey = GlobalHotKey(
        id: shortcut.hotKeyID,
        keyCode: shortcut.keyCode,
        modifiers: UInt32(cmdKey | optionKey | controlKey)
      ) { [weak self] in
        self?.togglePanel(for: shortcut.mode)
      }
      globalHotKeys[shortcut] = hotKey
      if !hotKey.isRegistered {
        NSLog("Reddict could not register the \(shortcut.displayShortcut) global shortcut.")
      }
    }

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if let button = statusItem.button {
      button.image = NSImage(
        systemSymbolName: "text.bubble.fill",
        accessibilityDescription: "Reddict"
      )
      button.image?.isTemplate = true
      button.toolTip = "Reddict · 读懂字面之外"
    }

    self.statusItem = statusItem
    rebuildStatusMenu()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(interfaceLanguageDidChange),
      name: .reddictInterfaceLanguageDidChange,
      object: nil
    )
  }

  @objc private func interfaceLanguageDidChange() {
    rebuildStatusMenu()
  }

  private func rebuildStatusMenu() {
    guard let statusItem else { return }
    let language = LearnerPreferencesStore.shared.load().interfaceLanguage
    statusItem.button?.toolTip = language.text(
      "Reddict · 读懂字面之外",
      "Reddict · Beyond the literal"
    )

    let menu = NSMenu()
    for shortcut in AppShortcut.allCases {
      menu.addItem(
        withTitle: shortcut.menuTitle(for: language),
        action: selector(for: shortcut),
        keyEquivalent: ""
      )
    }
    menu.addItem(
      withTitle: language.text("精读当前剪贴板", "Analyze Current Clipboard"),
      action: #selector(translateClipboard),
      keyEquivalent: ""
    )
    menu.addItem(
      withTitle: language.text(
        "语言、显示与 API 设置…",
        "Language, Display & API Settings…"
      ),
      action: #selector(showAPISettings),
      keyEquivalent: ","
    )
    menu.addItem(.separator())
    let failedShortcuts = AppShortcut.allCases.filter {
      globalHotKeys[$0]?.isRegistered != true
    }
    let shortcutHint =
      failedShortcuts.isEmpty
      ? language.text(
        "再次按同一快捷键关闭；按其他快捷键切换功能",
        "Press the same shortcut to close; another shortcut switches mode"
      )
      : language.text(
        "快捷键被占用：\(failedShortcuts.map(\.displayShortcut).joined(separator: "、"))",
        "Shortcuts unavailable: \(failedShortcuts.map(\.displayShortcut).joined(separator: ", "))"
      )
    let hotKeyHint = NSMenuItem(title: shortcutHint, action: nil, keyEquivalent: "")
    hotKeyHint.isEnabled = false
    menu.addItem(hotKeyHint)
    let hint = NSMenuItem(
      title: language.text(
        "或：选中文字 → 右键 → 服务 → Reddict",
        "Or: select text → right-click → Services → Reddict"
      ),
      action: nil,
      keyEquivalent: ""
    )
    hint.isEnabled = false
    menu.addItem(hint)
    menu.addItem(.separator())
    menu.addItem(
      withTitle: language.text("退出 Reddict", "Quit Reddict"),
      action: #selector(quit),
      keyEquivalent: "q"
    )
    for item in menu.items {
      item.target = self
    }
    statusItem.menu = menu
  }

  @objc private func translateClipboard() {
    let pasteboard = NSPasteboard.general
    let text = pasteboard.string(forType: .string)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    panelController?.show(
      text: text ?? "",
      mode: .closeReading
    )
  }

  private func selector(for shortcut: AppShortcut) -> Selector {
    switch shortcut {
    case .closeReading: #selector(toggleCloseReadingPanel)
    case .replies: #selector(toggleRepliesPanel)
    case .howToSay: #selector(toggleHowToSayPanel)
    }
  }

  @objc private func toggleCloseReadingPanel() {
    togglePanel(for: .closeReading)
  }

  @objc private func toggleRepliesPanel() {
    togglePanel(for: .replies)
  }

  @objc private func toggleHowToSayPanel() {
    togglePanel(for: .howToSay)
  }

  private func togglePanel(for mode: AnalysisMode) {
    let pasteboard = NSPasteboard.general
    let text = pasteboard.string(forType: .string) ?? ""
    panelController?.toggleShortcut(
      text: text,
      changeCount: pasteboard.changeCount,
      mode: mode
    )
  }

  @objc private func showAPISettings() {
    panelController?.showSettings()
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }
}
