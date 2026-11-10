import AppKit
import CoreGraphics
import Foundation

// These doubles replace only system effects. The real session model, event
// handler, resource loader and display geometry run unchanged in the checks.
private final class FakeInput: InputBlocking {
    var onSignal: (@MainActor (InputSignal) -> Void)?
    var isBlocking = false
    var startCount = 0
    var stopCount = 0
    var failure: InputBlockerError?
    var enableSucceeds = true
    func start() throws {
        startCount += 1
        isBlocking = enableSucceeds
        if let failure { throw failure }
    }
    func stop() { stopCount += 1; isBlocking = false }
    @MainActor func send(_ signal: InputSignal) { onSignal?(signal) }
}

@MainActor
private final class FakePresentation: LockPresenting {
    var showCount = 0
    var hideCount = 0
    var hud: LockHUDViewModel?
    func show(model: LockHUDViewModel) { showCount += 1; hud = model }
    func hide() { hideCount += 1; hud = nil }
}

@main
struct BehaviorChecks {
    @MainActor
    static func main() async throws {
        let app = Bundle(url: URL(fileURLWithPath: "Build/Release/CleanKeys.app"))!
        let logo = CleanKeysWindowView.loadLogo(in: app)
        precondition(logo?.isValid == true && logo!.size.width > 0, "Packaged logo must decode")
        let hu = Bundle(path: app.path(forResource: "hu", ofType: "lproj")!)!
        let en = Bundle(path: app.path(forResource: "en", ofType: "lproj")!)!
        precondition(L10n.text("Start Cleaning", bundle: hu) == "Tisztítás indítása")
        precondition(L10n.text("Start Cleaning", bundle: en) == "Start Cleaning")

        let suite = "CleanKeys.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "lockPointer")
        var allowed = true
        let input = FakeInput()
        let presentation = FakePresentation()
        let model = CleanKeysModel(defaults: defaults, inputBlocker: input, presentation: presentation,
                                   permissionCheck: { allowed })
        precondition(defaults.object(forKey: "lockPointer") == nil)
        model.blackoutScreen = true
        let restored = CleanKeysModel(defaults: defaults, inputBlocker: FakeInput(), presentation: FakePresentation(),
                                      permissionCheck: { true }, observeSystemEvents: false)
        precondition(restored.blackoutScreen)
        model.blackoutScreen = false
        precondition(!defaults.bool(forKey: "blackoutScreen"))

        // No request may present a lock without both permission and a live tap.
        allowed = false
        model.startCleaning()
        precondition(model.phase == .idle && input.startCount == 0 && presentation.showCount == 0)
        allowed = true
        input.failure = .pointerLockFailed
        model.startCleaning()
        precondition(model.phase == .idle && !input.isBlocking && presentation.showCount == 0 && model.errorMessage != nil)
        input.failure = nil
        input.enableSucceeds = false
        model.startCleaning()
        precondition(model.phase == .idle && presentation.showCount == 0 && model.errorMessage != nil)
        input.enableSucceeds = true

        model.blackoutScreen = true
        model.startCleaning()
        precondition(model.phase == .locked && input.isBlocking && presentation.showCount == 1)
        precondition(presentation.hud?.blackoutEnabled == true)
        let starts = input.startCount
        model.startCleaning()
        precondition(input.startCount == starts, "Double start must not install another filter")
        input.send(.escapeChanged(isDown: true))
        try await Task.sleep(nanoseconds: 120_000_000)
        let progress = presentation.hud!.escapeHoldProgress
        precondition(progress > 0)
        input.send(.escapeChanged(isDown: true))
        try await Task.sleep(nanoseconds: 120_000_000)
        precondition(presentation.hud!.escapeHoldProgress > progress, "Repeated presses must not restart the hold")
        input.send(.escapeChanged(isDown: false))
        precondition(presentation.hud?.escapeHoldProgress == 0)
        try await Task.sleep(nanoseconds: 80_000_000)
        precondition(model.phase == .locked)

        let heldSince = ProcessInfo.processInfo.systemUptime
        input.send(.escapeChanged(isDown: true))
        try await Task.sleep(nanoseconds: 2_700_000_000)
        if ProcessInfo.processInfo.systemUptime - heldSince < 3 {
            precondition(model.phase == .locked, "No early unlock")
        }
        try await Task.sleep(nanoseconds: 500_000_000)
        precondition(model.phase == .idle && !input.isBlocking && presentation.hud == nil)
        precondition(model.completedSession && model.errorMessage == nil)
        let stops = input.stopCount
        model.endSession()
        precondition(input.stopCount == stops, "Cleanup must be idempotent")

        model.startCleaning()
        precondition(model.phase == .locked && !model.completedSession)
        input.send(.escapeChanged(isDown: true))
        input.send(.tapDisabled)
        precondition(model.phase == .idle && !input.isBlocking && !model.completedSession && model.errorMessage != nil)
        model.dismissError()
        precondition(model.errorMessage == nil)

        // Permission loss and silent tap failure release the whole session.
        model.startCleaning()
        allowed = false
        model.refreshPermission()
        precondition(model.phase == .idle && !input.isBlocking)
        allowed = true
        model.startCleaning()
        input.isBlocking = false
        try await Task.sleep(nanoseconds: 1_150_000_000)
        precondition(model.phase == .idle && presentation.hud == nil && model.errorMessage != nil)

        for (center, notification) in [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.sessionDidResignActiveNotification),
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification),
            (NotificationCenter.default, NSApplication.willTerminateNotification),
        ] {
            model.startCleaning()
            input.send(.escapeChanged(isDown: true))
            center.post(name: notification, object: nil)
            precondition(model.phase == .idle && !input.isBlocking && presentation.hud == nil,
                         "Safety cleanup must finish synchronously")
        }
        // The main window must observe the exact same live countdown model
        // used for a session, then return to idle when that model is released.
        model.blackoutScreen = false
        model.startCleaning()
        precondition(model.hudModel === presentation.hud && model.hudModel?.blackoutEnabled == false)
        input.send(.escapeChanged(isDown: true))
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(model.hudModel?.escapeCountdown == 3)
        input.send(.escapeChanged(isDown: false))
        precondition(model.hudModel?.escapeCountdown == nil && model.phase == .locked)
        model.endSession()
        precondition(model.hudModel == nil && model.completedSession)

        try await checkEventHandler()
        checkDisplayGeometry()
        print("Passed: packaged logo and translations, preference migration, real start/failure lifecycle, repeated starts, interrupted/repeated Escape holds, 3-second unlock, completion state, tap and permission loss, synchronous safety cleanup, stale event rejection, shared main-window countdown, multi-display HUD geometry.")
    }

    @MainActor
    private static func checkEventHandler() async throws {
        let mask = InputBlocker.eventMask()
        for type: CGEventType in [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .mouseMoved, .leftMouseDragged, .rightMouseDragged,
            .scrollWheel, .tabletPointer, .tabletProximity,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
        ] { precondition(mask & (1 << type.rawValue) != 0) }
        precondition(mask & (1 << 14) != 0)

        let blocker = InputBlocker()
        var signals: [InputSignal] = []
        blocker.onSignal = { signals.append($0) }
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)!
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        precondition(blocker.process(type: .keyDown, event: event) == nil)
        try await Task.sleep(nanoseconds: 30_000_000)
        precondition(signals.isEmpty)
        event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
        _ = blocker.process(type: .keyDown, event: event)
        _ = blocker.process(type: .keyUp, event: event)
        _ = blocker.process(type: .tapDisabledByTimeout, event: event)
        try await Task.sleep(nanoseconds: 30_000_000)
        precondition(signals.count == 3)
        guard case .escapeChanged(isDown: true) = signals[0],
              case .escapeChanged(isDown: false) = signals[1],
              case .tapDisabled = signals[2] else { fatalError("Wrong event order") }
        signals.removeAll()
        _ = blocker.process(type: .keyDown, event: event)
        blocker.stop()
        try await Task.sleep(nanoseconds: 30_000_000)
        precondition(signals.isEmpty, "An old session's queued event must not affect a later session")
    }

    @MainActor
    private static func checkDisplayGeometry() {
        // Unequal displays to the left and above the main screen must use their
        // own global coordinates, without accidentally centering on screen 1.
        for screen in [CGRect(x: 0, y: 0, width: 1512, height: 982),
                       CGRect(x: -2560, y: -400, width: 2560, height: 1440),
                       CGRect(x: 0, y: 982, width: 1920, height: 1080)] {
            let frame = LockHUDController.frame(size: CGSize(width: 480, height: 260), screenFrame: screen)
            precondition(frame.midX == screen.midX && frame.midY == screen.midY)
        }
    }
}
