import SwiftUI

struct LockHUDView: View {
    @ObservedObject var model: LockHUDViewModel

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Keyboard locked")
                        .font(.headline)
                    Text("Time remaining: \(model.formattedRemainingTime)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if model.pointerLocked {
                Divider()

                VStack(spacing: 6) {
                    Label("Unlock: hold Esc for 3 seconds", systemImage: "escape")
                        .font(.subheadline)
                }
            } else {
                SlideToUnlockView(onUnlock: model.onUnlock)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.16))
        }
        .padding(4)
    }
}
