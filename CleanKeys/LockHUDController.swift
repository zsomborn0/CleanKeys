import AppKit
import SwiftUI

@MainActor
final class LockHUDController {
    private var panels: [NSPanel] = []

    func show(model: LockHUDViewModel) {
        close()

        guard model.blackoutEnabled else { return }
        let size = CGSize(width: 480, height: 260)
        // Each blacked-out display gets synchronized instructions. The normal
        // cleaning mode stays entirely within the existing main window.
        let screens = NSScreen.screens

        panels = screens.map { screen in
            let frame = Self.frame(size: size, screenFrame: screen.frame)
            let panel = NSPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )

            panel.contentView = NSHostingView(rootView: LockHUDView(model: model))
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isFloatingPanel = true
            panel.becomesKeyOnlyIfNeeded = true
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.ignoresMouseEvents = true
            panel.orderFrontRegardless()
            return panel
        }
    }

    func close() {
        panels.forEach {
            $0.orderOut(nil)
            $0.contentView = nil
        }
        panels.removeAll()
    }

    static func frame(size: CGSize, screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
