import ApplicationServices
import CoreGraphics
import Foundation

final class InputBlocker {
    var onSignal: ((InputSignal) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var cursorIsDisconnected = false

    var isBlocking: Bool {
        guard let eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: eventTap)
    }

    func start(lockPointer: Bool) throws {
        stop()

        guard AXIsProcessTrusted() else {
            throw InputBlockerError.permissionMissing
        }

        let mask = Self.eventMask(lockPointer: lockPointer)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: cleanKeysEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw InputBlockerError.tapCreationFailed
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            throw InputBlockerError.tapCreationFailed
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        guard CGEvent.tapIsEnabled(tap: tap) else {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFMachPortInvalidate(tap)
            throw InputBlockerError.tapEnableFailed
        }

        eventTap = tap
        runLoopSource = source

        if lockPointer {
            let result = CGAssociateMouseAndMouseCursorPosition(0)
            guard result == .success else {
                stop()
                throw InputBlockerError.pointerLockFailed
            }
            cursorIsDisconnected = true
        }
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil

        if cursorIsDisconnected {
            _ = CGAssociateMouseAndMouseCursorPosition(1)
            cursorIsDisconnected = false
        }
    }

    deinit {
        stop()
    }

    fileprivate func process(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }

            if eventTap == nil || !(eventTap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false) {
                DispatchQueue.main.async { [weak self] in
                    self?.onSignal?(.tapDisabled)
                }
            }

            return nil
        }

        if type == .keyDown || type == .keyUp {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == 53 {
                let isDown = type == .keyDown
                DispatchQueue.main.async { [weak self] in
                    self?.onSignal?(.escapeChanged(isDown: isDown))
                }
            }
        }

        return nil
    }

    static func eventMask(lockPointer: Bool) -> CGEventMask {
        var types: [CGEventType] = [
            .keyDown,
            .keyUp,
            .flagsChanged,
        ]

        if lockPointer {
            types += [
                .leftMouseDown,
                .leftMouseUp,
                .rightMouseDown,
                .rightMouseUp,
                .mouseMoved,
                .leftMouseDragged,
                .rightMouseDragged,
                .scrollWheel,
                .tabletPointer,
                .tabletProximity,
                .otherMouseDown,
                .otherMouseUp,
                .otherMouseDragged,
            ]
        }

        let standardMask = types.reduce(CGEventMask(0)) { partial, type in
            partial | (CGEventMask(1) << type.rawValue)
        }

        // Brightness, volume, and media keys arrive as NX_SYSDEFINED events.
        // CoreGraphics does not expose a named Swift CGEventType case for them,
        // but the documented raw event type is 14.
        let systemDefinedMask = CGEventMask(1) << 14
        return standardMask | systemDefinedMask
    }
}

private func cleanKeysEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let blocker = Unmanaged<InputBlocker>.fromOpaque(userInfo).takeUnretainedValue()
    return blocker.process(type: type, event: event)
}
