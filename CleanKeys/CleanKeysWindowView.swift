import SwiftUI

struct CleanKeysWindowView: View {
    @ObservedObject var model: CleanKeysModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Keep the control layout in place to preserve this window's size and
        // position. Only its visible content changes during a cleaning session.
        ZStack {
            controlContent
                .opacity(model.phase.isBusy ? 0 : 1)
                .allowsHitTesting(!model.phase.isBusy)
                .accessibilityHidden(model.phase.isBusy)
            if model.phase.isBusy, let lock = model.hudModel {
                LockHUDView(model: lock)
                    .padding(28)
                    .transition(.opacity)
            }
        }
            .onAppear { model.refreshPermission() }
            .animation(.easeInOut(duration: reduceMotion ? 0.1 : 0.24), value: model.phase.isBusy)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.completedSession)
    }

    private var controlContent: some View {
        VStack(spacing: 28) {
            VStack(spacing: 18) {
                Image(nsImage: Self.logo)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 68, height: 68)
                    .overlay(alignment: .bottomTrailing) {
                        if model.completedSession {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.green)
                                .background(Color(nsColor: .windowBackgroundColor), in: Circle())
                                .offset(x: 5, y: 5)
                                .transition(.opacity)
                        }
                    }
                    .accessibilityHidden(true)

                VStack(spacing: 7) {
                    Text(model.title)
                        .font(.system(size: 24, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(model.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if model.permissionGranted {
                controls
            } else {
                permissionCard
            }

            if let errorMessage = model.errorMessage {
                HStack(alignment: .top, spacing: 10) {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button { model.dismissError() } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.text("Dismiss message"))
                }
                .foregroundStyle(.secondary)
                .padding(12)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(28)
        .padding(.vertical, 10)
    }

    // SwiftUI's asset-name lookup does not reliably find a loose PNG in a
    // locally assembled app bundle. Support both bundled files and Xcode assets.
    private static let logo: NSImage = loadLogo() ?? NSApplication.shared.applicationIconImage ?? NSImage()

    static func loadLogo(in bundle: Bundle = .main) -> NSImage? {
        if let url = bundle.url(forResource: "CleanKeysLogo", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return bundle.image(forResource: "CleanKeysLogo")
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L10n.text("One quick setup"), systemImage: "hand.raised")
                .font(.headline)
            Text(L10n.text("Enable CleanKeys in Accessibility settings. This lets it pause input while you clean. No keystrokes are recorded."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(L10n.text("Open Accessibility Settings")) { model.requestPermission() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            if model.isWaitingForPermission {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text(L10n.text("Waiting for access… This updates automatically."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(L10n.text("I've enabled access — check again")) { model.refreshPermission() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var controls: some View {
        VStack(spacing: 20) {
            Toggle(isOn: $model.blackoutScreen) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("Black out displays"))
                        .font(.system(size: 13))
                    Text(model.displayDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .help(L10n.text("When off, displays stay visible while all input is locked."))
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.primary.opacity(0.06))
            }
            .disabled(model.phase.isBusy)

            VStack(spacing: 18) {
                Button { model.startCleaning() } label: {
                    Text(L10n.text(model.phase.isBusy ? "Cleaning in progress" : "Start Cleaning"))
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.phase.isBusy)

                HStack(spacing: 8) {
                    Text("esc")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .overlay {
                            RoundedRectangle(cornerRadius: 4)
                                .strokeBorder(.secondary.opacity(0.35))
                        }
                    Text(L10n.text("Hold for 3 seconds to unlock"))
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
