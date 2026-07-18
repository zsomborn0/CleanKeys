import Foundation

enum LockPhase: Equatable {
    case idle
    case countdown(Int)
    case locked
    case ending

    var isBusy: Bool {
        self != .idle
    }
}

enum InputSignal: Sendable {
    case escapeChanged(isDown: Bool)
    case tapDisabled
}

enum InputBlockerError: LocalizedError {
    case permissionMissing
    case tapCreationFailed
    case tapEnableFailed
    case pointerLockFailed

    var errorDescription: String? {
        switch self {
        case .permissionMissing:
            return "To lock the keyboard, allow CleanKeys in System Settings › Privacy & Security › Accessibility."
        case .tapCreationFailed:
            return "macOS could not create the input filter. Check the permission and try again."
        case .tapEnableFailed:
            return "The input filter was created but could not be enabled. The keyboard was not locked."
        case .pointerLockFailed:
            return "macOS could not lock the pointer. CleanKeys did not start cleaning mode for safety."
        }
    }
}

struct LockOptions: Equatable {
    let lockPointer: Bool
    let blackoutScreen: Bool
    let durationSeconds: Int
}

@MainActor
final class LockHUDViewModel: ObservableObject {
    @Published var remainingSeconds: Int

    let pointerLocked: Bool
    let blackoutEnabled: Bool
    let onUnlock: () -> Void

    init(
        remainingSeconds: Int,
        pointerLocked: Bool,
        blackoutEnabled: Bool,
        onUnlock: @escaping () -> Void
    ) {
        self.remainingSeconds = remainingSeconds
        self.pointerLocked = pointerLocked
        self.blackoutEnabled = blackoutEnabled
        self.onUnlock = onUnlock
    }

    var formattedRemainingTime: String {
        String(format: "%d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }
}
