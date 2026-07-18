import AppKit

@MainActor
final class ScreenBlackoutController {
    private var windows: [NSWindow] = []

    func show() {
        hide()

        windows = NSScreen.screens.map { screen in
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.backgroundColor = .black
            window.isOpaque = true
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.ignoresMouseEvents = true
            window.orderFrontRegardless()
            return window
        }
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

@MainActor
final class PointerShieldController {
    private var windows: [NSPanel] = []
    private var cursorGuardTask: Task<Void, Never>?
    private var cursorAnchor: CGPoint?
    private var cursorIsHidden = false

    var isActive: Bool {
        !windows.isEmpty
    }

    func show() {
        hide()

        cursorAnchor = CGEvent(source: nil)?.location
        _ = CGAssociateMouseAndMouseCursorPosition(0)
        if let cursorAnchor {
            _ = CGWarpMouseCursorPosition(cursorAnchor)
        }
        NSCursor.hide()
        cursorIsHidden = true

        cursorGuardTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled, let self, let cursorAnchor else { return }

                // macOS may temporarily reconnect the mouse and cursor when a
                // system window appears or focus changes. Keep pinning it to
                // the same screen position while the lock is active.
                _ = CGAssociateMouseAndMouseCursorPosition(0)
                _ = CGWarpMouseCursorPosition(cursorAnchor)
            }
        }

        windows = NSScreen.screens.map { screen in
            let panel = PointerShieldPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false,
                screen: screen
            )

            let shieldView = PointerShieldView(frame: screen.frame)
            shieldView.autoresizingMask = [.width, .height]

            panel.contentView = shieldView
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isFloatingPanel = true
            panel.becomesKeyOnlyIfNeeded = true
            panel.worksWhenModal = true
            panel.level = .screenSaver
            panel.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .stationary,
                .ignoresCycle,
            ]
            panel.ignoresMouseEvents = false
            panel.acceptsMouseMovedEvents = true
            panel.orderFrontRegardless()
            return panel
        }
    }

    func hide() {
        cursorGuardTask?.cancel()
        cursorGuardTask = nil

        windows.forEach {
            $0.orderOut(nil)
            $0.contentView = nil
        }
        windows.removeAll()

        _ = CGAssociateMouseAndMouseCursorPosition(1)
        cursorAnchor = nil

        if cursorIsHidden {
            NSCursor.unhide()
            cursorIsHidden = false
        }
    }
}

private final class PointerShieldPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class PointerShieldView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        acceptsTouchEvents = true
        wantsRestingTouches = true
        allowedTouchTypes = [.direct, .indirect]
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        acceptsTouchEvents = true
        wantsRestingTouches = true
        allowedTouchTypes = [.direct, .indirect]
    }

    override func hitTest(_ point: NSPoint) -> NSView? { self }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func rightMouseUp(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
    override func otherMouseUp(with event: NSEvent) {}
    override func mouseMoved(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func rightMouseDragged(with event: NSEvent) {}
    override func otherMouseDragged(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}
    override func magnify(with event: NSEvent) {}
    override func rotate(with event: NSEvent) {}
    override func swipe(with event: NSEvent) {}
    override func smartMagnify(with event: NSEvent) {}
    override func pressureChange(with event: NSEvent) {}
    override func beginGesture(with event: NSEvent) {}
    override func endGesture(with event: NSEvent) {}
    override func touchesBegan(with event: NSEvent) {}
    override func touchesMoved(with event: NSEvent) {}
    override func touchesEnded(with event: NSEvent) {}
    override func touchesCancelled(with event: NSEvent) {}
}
