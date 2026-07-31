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
    private var globalHotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let panelController = FloatingPanelController()
        let servicesProvider = SelectionServicesProvider(panelController: panelController)
        self.panelController = panelController
        self.servicesProvider = servicesProvider
        NSApp.servicesProvider = servicesProvider
        globalHotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_L),
            modifiers: UInt32(cmdKey | optionKey | controlKey)
        ) { [weak self] in
            self?.togglePanel()
        }
        if globalHotKey?.isRegistered != true {
            NSLog("Reddict could not register the ⌃⌥⌘L global shortcut.")
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

        let menu = NSMenu()
        menu.addItem(
            withTitle: "显示 / 隐藏浮窗（⌃⌥⌘L）",
            action: #selector(togglePanel),
            keyEquivalent: ""
        )
        menu.addItem(withTitle: "精读当前剪贴板", action: #selector(translateClipboard), keyEquivalent: "")
        menu.addItem(withTitle: "学习语言、显示与 API 设置…", action: #selector(showAPISettings), keyEquivalent: ",")
        menu.addItem(.separator())
        let shortcutHint = globalHotKey?.isRegistered == true
            ? "新剪贴板会自动精读；再次按下可隐藏"
            : "⌃⌥⌘L 被其他应用占用，可从这里翻译"
        let hotKeyHint = NSMenuItem(title: shortcutHint, action: nil, keyEquivalent: "")
        hotKeyHint.isEnabled = false
        menu.addItem(hotKeyHint)
        let hint = NSMenuItem(title: "或：选中文字 → 右键 → 服务 → Reddict", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Reddict", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
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
        menu.addItem(
            withTitle: language.text(
                "显示 / 隐藏浮窗（⌃⌥⌘L）",
                "Show / Hide Window (⌃⌥⌘L)"
            ),
            action: #selector(togglePanel),
            keyEquivalent: ""
        )
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
        let shortcutHint = globalHotKey?.isRegistered == true
            ? language.text(
                "新剪贴板会自动精读；再次按下可隐藏",
                "A new clipboard is analyzed automatically; press again to hide"
            )
            : language.text(
                "⌃⌥⌘L 被其他应用占用，可从这里翻译",
                "⌃⌥⌘L is in use; analyze from this menu instead"
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
        menu.items.forEach { $0.target = self }
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

    @objc private func togglePanel() {
        let pasteboard = NSPasteboard.general
        let text = pasteboard.string(forType: .string) ?? ""
        panelController?.toggleClipboard(
            text: text,
            changeCount: pasteboard.changeCount
        )
    }

    @objc private func showAPISettings() {
        panelController?.showSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
