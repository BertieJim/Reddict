import AppKit

final class SelectionServicesProvider: NSObject {
    private weak var panelController: FloatingPanelController?

    init(panelController: FloatingPanelController) {
        self.panelController = panelController
        super.init()
    }

    @objc(translateSelection:userData:error:)
    func translateSelection(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        handle(pasteboard, mode: .closeReading, error: error)
    }

    @objc(explainVocabulary:userData:error:)
    func explainVocabulary(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        handle(pasteboard, mode: .closeReading, error: error)
    }

    @objc(explainCulture:userData:error:)
    func explainCulture(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        handle(pasteboard, mode: .closeReading, error: error)
    }

    @objc(suggestReplies:userData:error:)
    func suggestReplies(
        _ pasteboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        handle(pasteboard, mode: .replies, error: error)
    }

    private func handle(
        _ pasteboard: NSPasteboard,
        mode: AnalysisMode,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let text = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            error.pointee = "Reddict 没有读到选中的文字。" as NSString
            return
        }

        Task { @MainActor [weak self] in
            self?.panelController?.show(text: text, mode: mode)
        }
    }
}
