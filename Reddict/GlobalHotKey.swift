import Carbon.HIToolbox
import Foundation

final class GlobalHotKey {
    private static let signature: OSType = 0x52444443

    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?
    private let action: @MainActor () -> Void

    private(set) var isRegistered = false

    init(
        keyCode: UInt32,
        modifiers: UInt32,
        action: @escaping @MainActor () -> Void
    ) {
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
                      identifier.id == 1 else {
                    return OSStatus(eventNotHandledErr)
                }

                let hotKey = Unmanaged<GlobalHotKey>
                    .fromOpaque(context)
                    .takeUnretainedValue()
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

        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
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
