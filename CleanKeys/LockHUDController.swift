import AppKit
import SwiftUI

@MainActor
final class LockHUDController {
    private var panel: NSPanel?

    func show(model: LockHUDViewModel) {
        close()

        let size = CGSize(width: 390, height: model.pointerLocked ? 190 : 225)
        let frame = Self.frame(size: size, centered: model.blackoutEnabled)
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.contentView = NSHostingView(rootView: LockHUDView(model: model))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = model.blackoutEnabled || model.pointerLocked
            ? NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            : .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = model.pointerLocked
        panel.orderFrontRegardless()

        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
    }

    private static func frame(size: CGSize, centered: Bool) -> CGRect {
        guard let screen = NSScreen.main else {
            return CGRect(origin: .zero, size: size)
        }
        let visible = screen.visibleFrame
        let x = visible.midX - size.width / 2
        let y = centered
            ? visible.midY - size.height / 2
            : visible.maxY - size.height - 28
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}
