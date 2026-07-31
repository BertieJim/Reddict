import AppKit
import SwiftUI

@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    let viewModel = AnalysisViewModel()
    private let panel: NSPanel
    private var lastClipboardChangeCount = -1

    override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 570, height: 720),
            styleMask: [.titled, .fullSizeContentView, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.delegate = self
        panel.title = "Reddict"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.titlebarSeparatorStyle = .none
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 500, height: 580)
        panel.maxSize = NSSize(width: 720, height: 900)
        panel.contentView = NSHostingView(rootView: AnalysisView(viewModel: viewModel))
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
    }

    func show(text: String, mode: AnalysisMode) {
        viewModel.begin(text: text, mode: mode)
        lastClipboardChangeCount = NSPasteboard.general.changeCount
        present()
    }

    func toggleClipboard(text: String, changeCount: Int) {
        if panel.isVisible {
            panel.orderOut(nil)
            return
        }

        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldPreserveCurrentWork = viewModel.isAnyRequestRunning
            || viewModel.hasUnsubmittedManualInput
            || viewModel.isShowingAPISettings
            || viewModel.isShowingHistory
        let clipboardChanged = changeCount != lastClipboardChangeCount

        if !shouldPreserveCurrentWork,
           clipboardChanged,
           !normalized.isEmpty {
            viewModel.begin(text: normalized, mode: .closeReading)
            lastClipboardChangeCount = changeCount
        }
        present()
    }

    func showSettings() {
        viewModel.openAPISettings()
        present()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        panel.orderOut(nil)
        return false
    }

    private func present() {
        if !panel.isVisible {
            positionNearPointer()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    private func positionNearPointer() {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) })
            ?? NSScreen.main
        guard let frame = screen?.visibleFrame else {
            panel.center()
            return
        }

        var origin = NSPoint(
            x: pointer.x + 18,
            y: pointer.y - panel.frame.height * 0.42
        )
        origin.x = min(max(origin.x, frame.minX + 12), frame.maxX - panel.frame.width - 12)
        origin.y = min(max(origin.y, frame.minY + 12), frame.maxY - panel.frame.height - 12)
        panel.setFrameOrigin(origin)
    }
}
