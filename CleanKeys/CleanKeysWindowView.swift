import SwiftUI

struct CleanKeysWindowView: View {
    @ObservedObject var model: CleanKeysModel

    private let durations = [30, 60, 120, 300]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Divider()

            if !model.permissionGranted {
                permissionCard
            } else {
                controls
            }

            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Label("CleanKeys quits completely when you close this window", systemImage: "power")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .task {
            while !Task.isCancelled {
                model.refreshPermission()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: model.phase.isBusy ? "lock.fill" : "keyboard")
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(model.phase.isBusy ? Color.orange : Color.accentColor)
                .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text("CleanKeys")
                    .font(.title3.weight(.semibold))
                Text(model.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Permission required", systemImage: "hand.raised.fill")
                .font(.headline)

            Text("macOS Accessibility permission allows CleanKeys to discard input while you clean. The app does not record or store keystrokes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Grant Permission") {
                model.requestPermission()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("The keyboard will always be locked", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Toggle("Lock trackpad and mouse", isOn: $model.lockPointer)
                .disabled(model.phase.isBusy)

            Toggle("Black out displays", isOn: $model.blackoutScreen)
                .disabled(model.phase.isBusy)

            if model.blackoutScreen {
                Text("Screen blackout also locks the trackpad and mouse.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Duration", selection: $model.durationSeconds) {
                ForEach(durations, id: \.self) { seconds in
                    Text(durationLabel(seconds)).tag(seconds)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.phase.isBusy)

            actionButton
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch model.phase {
        case .idle:
            Button {
                model.beginCountdown()
            } label: {
                Label("Start Cleaning", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

        case .countdown(let value):
            Button {
                model.cancelCountdown()
            } label: {
                Text("Cancel — locking in \(value)…")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

        case .locked:
            if !model.lockPointer {
                Button {
                    model.endSession()
                } label: {
                    Text("Unlock")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            } else {
                Text("Manual unlock: hold Esc for 3 seconds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .ending:
            ProgressView()
                .frame(maxWidth: .infinity)
        }
    }

    private func durationLabel(_ seconds: Int) -> String {
        switch seconds {
        case 30: return "30 sec"
        case 60: return "1 min"
        default: return "\(seconds / 60) min"
        }
    }
}
