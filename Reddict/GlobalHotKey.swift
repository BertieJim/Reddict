import Carbon.HIToolbox
import Foundation

enum ShortcutPanelTransition: Equatable {
  case hide
  case show
  case switchMode
}

enum ShortcutPanelPolicy {
  static func transition(
    isVisible: Bool,
    activeMode: AnalysisMode,
    requestedMode: AnalysisMode
  ) -> ShortcutPanelTransition {
    guard isVisible else { return .show }
    return activeMode == requestedMode ? .hide : .switchMode
  }
}

enum AppShortcut: CaseIterable, Hashable {
  case closeReading
  case replies
  case howToSay

  var mode: AnalysisMode {
    switch self {
    case .closeReading: .closeReading
    case .replies: .replies
    case .howToSay: .howToSay
    }
  }

  var hotKeyID: UInt32 {
    switch self {
    case .closeReading: 1
    case .replies: 2
    case .howToSay: 3
    }
  }

  var keyCode: UInt32 {
    switch self {
    case .closeReading: UInt32(kVK_ANSI_T)
    case .replies: UInt32(kVK_ANSI_L)
    case .howToSay: UInt32(kVK_ANSI_H)
    }
  }

  var displayShortcut: String {
    switch self {
    case .closeReading: "⌃⌥⌘T"
    case .replies: "⌃⌥⌘L"
    case .howToSay: "⌃⌥⌘H"
    }
  }

  func menuTitle(for language: InterfaceLanguage) -> String {
    switch self {
    case .closeReading:
      language.text("翻译 / 精读（\(displayShortcut)）", "Translate / Close Reading (\(displayShortcut))")
    case .replies:
      language.text("怎么回（\(displayShortcut)）", "Replies (\(displayShortcut))")
    case .howToSay:
      "How To Say（\(displayShortcut)）"
    }
  }
}

final class GlobalHotKey {
  private static let signature: OSType = 0x5244_4443

  private var hotKeyReference: EventHotKeyRef?
  private var eventHandlerReference: EventHandlerRef?
  private let hotKeyID: UInt32
  private let action: @MainActor () -> Void

  private(set) var isRegistered = false

  init(
    id: UInt32,
    keyCode: UInt32,
    modifiers: UInt32,
    action: @escaping @MainActor () -> Void
  ) {
    hotKeyID = id
    self.action = action

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    let context = Unmanaged.passUnretained(self).toOpaque()
    let handlerStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, context in
        guard let event, let context else {
          return OSStatus(eventNotHandledErr)
        }

        let hotKey = Unmanaged<GlobalHotKey>
          .fromOpaque(context)
          .takeUnretainedValue()

        var identifier = EventHotKeyID()
        let status = GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &identifier
        )
        guard status == noErr,
          identifier.signature == GlobalHotKey.signature,
          identifier.id == hotKey.hotKeyID
        else {
          return OSStatus(eventNotHandledErr)
        }
        Task { @MainActor in
          hotKey.action()
        }
        return noErr
      },
      1,
      &eventType,
      context,
      &eventHandlerReference
    )

    guard handlerStatus == noErr else { return }

    let identifier = EventHotKeyID(signature: Self.signature, id: hotKeyID)
    let registrationStatus = RegisterEventHotKey(
      keyCode,
      modifiers,
      identifier,
      GetApplicationEventTarget(),
      0,
      &hotKeyReference
    )
    isRegistered = registrationStatus == noErr
  }

  deinit {
    if let hotKeyReference {
      UnregisterEventHotKey(hotKeyReference)
    }
    if let eventHandlerReference {
      RemoveEventHandler(eventHandlerReference)
    }
  }
}
