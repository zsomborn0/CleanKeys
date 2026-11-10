import AppKit

@MainActor
protocol LockPresenting: AnyObject {
    func show(model: LockHUDViewModel)
    func hide()
}

@MainActor
final class LockPresentation: LockPresenting {
    private let blackout = ScreenBlackoutController()
    private let shield = PointerShieldController()
    private let hud = LockHUDController()

    func show(model: LockHUDViewModel) {
        if model.blackoutEnabled { blackout.show() }
        shield.show()
        // Without blackout, the main CleanKeys window presents this model.
        // Separate transparent panels are only needed above blacked-out screens.
        if model.blackoutEnabled { hud.show(model: model) }
    }

    func hide() {
        hud.close()
        shield.hide()
        blackout.hide()
    }
}
