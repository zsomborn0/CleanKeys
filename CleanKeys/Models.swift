import Foundation
import Combine

enum LockPhase: Equatable {
    case idle
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
            return L10n.text("To lock the keyboard, allow CleanKeys in System Settings › Privacy & Security › Accessibility.")
        case .tapCreationFailed:
            return L10n.text("macOS could not create the input filter. Check the permission and try again.")
        case .tapEnableFailed:
            return L10n.text("The input filter was created but could not be enabled. The keyboard was not locked.")
        case .pointerLockFailed:
            return L10n.text("macOS could not lock the pointer. CleanKeys did not start cleaning mode for safety.")
        }
    }
}

@MainActor
final class LockHUDViewModel: ObservableObject {
    @Published var escapeHoldProgress: Double = 0

    var escapeCountdown: Int? {
        guard escapeHoldProgress > 0 else { return nil }
        return max(1, 3 - Int(escapeHoldProgress * 3))
    }

    let blackoutEnabled: Bool

    init(blackoutEnabled: Bool) {
        self.blackoutEnabled = blackoutEnabled
    }
}
