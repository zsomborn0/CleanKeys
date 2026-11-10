import AppKit
import ApplicationServices
import Foundation
import Combine

@MainActor
final class CleanKeysModel: ObservableObject {
    @Published private(set) var phase: LockPhase = .idle
    @Published private(set) var permissionGranted = false
    @Published private(set) var isWaitingForPermission = false
    @Published private(set) var completedSession = false
    @Published private(set) var connectedDisplayCount = NSScreen.screens.count
    @Published private(set) var errorMessage: String?

    @Published var blackoutScreen = false {
        didSet { defaults.set(blackoutScreen, forKey: "blackoutScreen") }
    }

    private let defaults: UserDefaults
    private let inputBlocker: any InputBlocking
    private let presentation: any LockPresenting
    private let permissionCheck: () -> Bool
    private var escapeHoldTask: Task<Void, Never>?
    private var permissionWaitTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var notificationTokens: [(NotificationCenter, NSObjectProtocol)] = []
    @Published private(set) var hudModel: LockHUDViewModel?

    init(
        defaults: UserDefaults = .standard,
        inputBlocker: any InputBlocking = InputBlocker(),
        presentation: (any LockPresenting)? = nil,
        permissionCheck: @escaping () -> Bool = { AXIsProcessTrusted() },
        observeSystemEvents: Bool = true
    ) {
        self.defaults = defaults
        self.inputBlocker = inputBlocker
        self.presentation = presentation ?? LockPresentation()
        self.permissionCheck = permissionCheck
        blackoutScreen = defaults.bool(forKey: "blackoutScreen")
        defaults.removeObject(forKey: "lockPointer")
        refreshPermission()
        // The event tap delivers signals in order on the main queue. Do not
        // introduce another asynchronous hop that could reorder press/release.
        inputBlocker.onSignal = { [weak self] signal in self?.handle(signal: signal) }
        if observeSystemEvents { observeSafetyNotifications() }
    }

    deinit {
        escapeHoldTask?.cancel()
        permissionWaitTask?.cancel()
        watchdogTask?.cancel()
        notificationTokens.forEach { center, token in center.removeObserver(token) }
    }

    var title: String {
        if phase.isBusy { return L10n.text("Take your time.") }
        if completedSession { return L10n.text("All set.") }
        return L10n.text("Ready to clean.")
    }

    var subtitle: String {
        if phase.isBusy { return L10n.text("Keyboard, trackpad & mouse are locked.") }
        if completedSession { return L10n.text("Everything is unlocked. Back to your day.") }
        return L10n.text("Lock your keyboard, trackpad & mouse in one click.")
    }

    var displayDescription: String {
        if connectedDisplayCount > 1 {
            return L10n.format("All %d connected displays", connectedDisplayCount)
        }
        return L10n.text("This display")
    }

    func dismissError() { errorMessage = nil }

    func refreshPermission() {
        let wasGranted = permissionGranted
        permissionGranted = permissionCheck()
        if permissionGranted {
            isWaitingForPermission = false
            permissionWaitTask?.cancel()
            permissionWaitTask = nil
            if !wasGranted { errorMessage = nil }
        } else if phase == .locked {
            endSession(message: L10n.text("Accessibility access was removed. All input has been unlocked."))
        }
    }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openAccessibilitySettings()
        refreshPermission()
        guard !permissionGranted else { return }
        isWaitingForPermission = true
        permissionWaitTask?.cancel()
        permissionWaitTask = Task { [weak self] in
            // Poll only during an explicit setup attempt, never while idle.
            for _ in 0..<120 {
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                guard let self else { return }
                refreshPermission()
                if permissionGranted { return }
            }
            self?.isWaitingForPermission = false
            self?.permissionWaitTask = nil
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    func startCleaning() {
        guard phase == .idle else { return }
        refreshPermission()
        completedSession = false
        guard permissionGranted else { return }
        errorMessage = nil

        do {
            try inputBlocker.start()
            guard inputBlocker.isBlocking else { throw InputBlockerError.tapEnableFailed }
        } catch {
            inputBlocker.stop()
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            refreshPermission()
            return
        }

        let hudModel = LockHUDViewModel(blackoutEnabled: blackoutScreen)
        self.hudModel = hudModel
        phase = .locked
        presentation.show(model: hudModel)
        startWatchdog()
    }

    func endSession(message: String? = nil) {
        guard phase == .locked else { return }
        phase = .ending
        escapeHoldTask?.cancel()
        watchdogTask?.cancel()
        escapeHoldTask = nil
        watchdogTask = nil
        // Remove shields and stop cursor pinning before restoring normal input.
        presentation.hide()
        inputBlocker.stop()
        hudModel = nil
        completedSession = message == nil
        errorMessage = message
        phase = .idle
    }

    func quitApplication() {
        endSession()
        NSApplication.shared.terminate(nil)
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
                hudModel?.escapeHoldProgress = 0
            }
        case .tapDisabled:
            endSession(message: L10n.text("macOS interrupted the input lock. Everything has been unlocked safely."))
        }
    }

    private func startEscapeHoldIfNeeded() {
        guard escapeHoldTask == nil else { return }
        let started = ProcessInfo.processInfo.systemUptime
        escapeHoldTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, phase == .locked else { return }
                let progress = min(1, (ProcessInfo.processInfo.systemUptime - started) / 3)
                hudModel?.escapeHoldProgress = progress
                if progress >= 1 {
                    endSession()
                    return
                }
                do { try await Task.sleep(nanoseconds: 16_000_000) } catch { return }
            }
        }
    }

    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                guard let self, phase == .locked else { return }
                guard inputBlocker.isBlocking else {
                    handle(signal: .tapDisabled)
                    return
                }
                refreshPermission()
            }
        }
    }

    private func observeSafetyNotifications() {
        observe(NSWorkspace.willSleepNotification, center: NSWorkspace.shared.notificationCenter) { model in
            model.endSession(message: L10n.text("The Mac is going to sleep. Everything has been unlocked."))
        }
        observe(NSWorkspace.sessionDidResignActiveNotification, center: NSWorkspace.shared.notificationCenter) { model in
            model.endSession(message: L10n.text("The user session changed. Everything has been unlocked."))
        }
        observe(NSApplication.didChangeScreenParametersNotification) { model in
            model.connectedDisplayCount = NSScreen.screens.count
            model.endSession(message: L10n.text("Displays changed. Start cleaning again to cover the new arrangement."))
        }
        observe(NSApplication.didBecomeActiveNotification) { $0.refreshPermission() }
        observe(NSApplication.willTerminateNotification) { $0.endSession() }
    }

    private func observe(
        _ name: Notification.Name,
        center: NotificationCenter = .default,
        action: @escaping @MainActor (CleanKeysModel) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            // Especially on termination/sleep, cleanup must finish now rather
            // than waiting for an unstructured task that may never run.
            MainActor.assumeIsolated {
                if let self { action(self) }
            }
        }
        notificationTokens.append((center, token))
    }
}
