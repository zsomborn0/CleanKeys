import AppKit
import ApplicationServices
import Foundation

@MainActor
final class CleanKeysModel: ObservableObject {
    @Published private(set) var phase: LockPhase = .idle
    @Published private(set) var permissionGranted = AXIsProcessTrusted()
    @Published private(set) var remainingSeconds = 0
    @Published var errorMessage: String?

    @Published var lockPointer = false {
        didSet {
            if !lockPointer && blackoutScreen {
                blackoutScreen = false
            }
        }
    }

    @Published var blackoutScreen = false {
        didSet {
            if blackoutScreen && !lockPointer {
                lockPointer = true
            }
        }
    }

    @Published var durationSeconds = 60

    private let inputBlocker = InputBlocker()
    private let blackoutController = ScreenBlackoutController()
    private let pointerShieldController = PointerShieldController()
    private let hudController = LockHUDController()

    private var countdownTask: Task<Void, Never>?
    private var sessionTimerTask: Task<Void, Never>?
    private var escapeHoldTask: Task<Void, Never>?
    private var notificationTokens: [NSObjectProtocol] = []
    private var hudModel: LockHUDViewModel?

    init() {
        refreshPermission()

        inputBlocker.onSignal = { [weak self] signal in
            Task { @MainActor in
                self?.handle(signal: signal)
            }
        }

        observeSafetyNotifications()
    }

    deinit {
        notificationTokens.forEach(NotificationCenter.default.removeObserver)
    }

    var statusText: String {
        switch phase {
        case .idle:
            return "Keyboard is available"
        case .countdown(let value):
            return "Locking in \(value)…"
        case .locked:
            return "Keyboard locked"
        case .ending:
            return "Unlocking…"
        }
    }

    func refreshPermission() {
        permissionGranted = AXIsProcessTrusted()
    }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openAccessibilitySettings()
    }

    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func beginCountdown() {
        guard phase == .idle else { return }
        refreshPermission()
        guard permissionGranted else {
            errorMessage = "Grant macOS Accessibility permission first."
            requestPermission()
            return
        }

        errorMessage = nil
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            guard let self else { return }

            for value in stride(from: 3, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                phase = .countdown(value)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }

            guard !Task.isCancelled else { return }
            startSession()
        }
    }

    func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        phase = .idle
    }

    private func stopForSafety(message: String) {
        if case .countdown = phase {
            cancelCountdown()
            errorMessage = message
        } else {
            endSession(message: message)
        }
    }

    func endSession(message: String? = nil) {
        guard phase == .locked || phase == .ending else { return }
        phase = .ending

        countdownTask?.cancel()
        sessionTimerTask?.cancel()
        escapeHoldTask?.cancel()
        countdownTask = nil
        sessionTimerTask = nil
        escapeHoldTask = nil

        inputBlocker.stop()
        pointerShieldController.hide()
        blackoutController.hide()
        hudController.close()
        hudModel = nil

        remainingSeconds = 0
        phase = .idle
        if let message {
            errorMessage = message
        }
    }

    func quitApplication() {
        if phase == .locked || phase == .ending {
            endSession()
        } else if case .countdown = phase {
            cancelCountdown()
        }
        NSApplication.shared.terminate(nil)
    }

    private func startSession() {
        let options = LockOptions(
            lockPointer: lockPointer,
            blackoutScreen: blackoutScreen,
            durationSeconds: durationSeconds
        )

        do {
            try inputBlocker.start(lockPointer: options.lockPointer)
        } catch {
            phase = .idle
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            refreshPermission()
            return
        }

        guard inputBlocker.isBlocking else {
            inputBlocker.stop()
            phase = .idle
            errorMessage = InputBlockerError.tapEnableFailed.localizedDescription
            return
        }

        remainingSeconds = options.durationSeconds
        phase = .locked

        if options.blackoutScreen {
            blackoutController.show()
        }

        if options.lockPointer {
            pointerShieldController.show()
        }

        let hudModel = LockHUDViewModel(
            remainingSeconds: remainingSeconds,
            pointerLocked: options.lockPointer,
            blackoutEnabled: options.blackoutScreen,
            onUnlock: { [weak self] in
                self?.endSession()
            }
        )
        self.hudModel = hudModel
        hudController.show(model: hudModel)

        startSessionTimer()
    }

    private func startSessionTimer() {
        sessionTimerTask?.cancel()
        sessionTimerTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled && phase == .locked {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled && phase == .locked else { return }

                remainingSeconds = max(0, remainingSeconds - 1)
                hudModel?.remainingSeconds = remainingSeconds

                if remainingSeconds == 0 {
                    endSession()
                    return
                }
            }
        }
    }

    private func handle(signal: InputSignal) {
        guard phase == .locked else { return }

        switch signal {
        case .escapeChanged(let isDown):
            if isDown {
                startEscapeHoldIfNeeded()
            } else {
                escapeHoldTask?.cancel()
                escapeHoldTask = nil
            }

        case .tapDisabled:
            endSession(
                message: "macOS disabled the input filter. CleanKeys unlocked immediately for safety."
            )
        }
    }

    private func startEscapeHoldIfNeeded() {
        guard escapeHoldTask == nil else { return }

        escapeHoldTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.endSession()
        }
    }

    private func observeSafetyNotifications() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        notificationTokens.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.stopForSafety(message: "The Mac is going to sleep, so CleanKeys stopped the lock.")
                }
            }
        )

        notificationTokens.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.sessionDidResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.stopForSafety(message: "The user session changed, so CleanKeys stopped the lock.")
                }
            }
        )

        notificationTokens.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.inputBlocker.stop()
                    self?.pointerShieldController.hide()
                    self?.blackoutController.hide()
                    self?.hudController.close()
                }
            }
        )
    }
}
