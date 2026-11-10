import SwiftUI

// The same quiet lock/countdown presentation lives in the main window during
// normal cleaning and in transparent panels on every blacked-out display.
struct LockHUDView: View {
    @ObservedObject var model: LockHUDViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let count = model.escapeCountdown {
                rollingDigit(count)
                    .overlay {
                        Text(L10n.text("Hold Esc to unlock"))
                            .font(.system(size: 16, weight: .light, design: .rounded))
                            .tracking(0.2)
                            .fixedSize()
                            .offset(y: -80)
                        Text(L10n.text("Release to cancel"))
                            .font(.system(size: 13, weight: .regular))
                            .tracking(0.2)
                            .fixedSize()
                            .offset(y: 84)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.format("Hold Escape to unlock. %d seconds remaining. Release to cancel.", count))
                    .transition(.opacity)
            } else {
                VStack(spacing: 24) {
                    Image(systemName: "lock")
                        .font(.system(size: 32, weight: .light))
                        .accessibilityHidden(true)
                    Text(L10n.text("Keyboard, trackpad & mouse locked"))
                        .font(.system(size: 16, weight: .regular))
                        .tracking(0.3)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .overlay(alignment: .bottom) {
                    if !model.blackoutEnabled {
                        Text(L10n.text("Hold Esc for 3 seconds to unlock"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                            .offset(y: 48)
                    }
                }
                .transition(.opacity)
            }
        }
        .foregroundStyle(model.blackoutEnabled ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: reduceMotion ? 0.1 : 0.2), value: model.escapeCountdown != nil)
    }

    private func rollingDigit(_ count: Int) -> some View {
        ZStack {
            Text(count, format: .number)
                .font(.system(size: 88, weight: .light, design: .rounded).monospacedDigit())
                .tracking(-1.5)
                .id(count)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .offset(y: 72).combined(with: .opacity),
                    removal: .offset(y: -72).combined(with: .opacity)
                ))
        }
        .frame(width: 120, height: 112)
        .clipped()
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .timingCurve(0.22, 1, 0.36, 1, duration: 0.48),
            value: count
        )
    }
}
