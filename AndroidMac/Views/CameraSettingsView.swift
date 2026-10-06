import SwiftUI

/// Routes a real camera into the Android guest's camera apps, instead of the
/// emulator's default fake spinning-scene. Any macOS-visible webcam works,
/// including an iPhone via Continuity Camera — Android just sees it as a
/// normal camera, so any app that requests the camera can use it.
struct CameraSettingsView: View {
    let emulator: EmulatorService
    let avdService: AVDManagerService?
    let avdName: String
    @Environment(\.dismiss) private var dismiss

    private let builtin: [(id: String, label: String)] = [
        ("emulated", "Emulated (default fake scene)"),
        ("none", "None (disabled)"),
    ]

    @State private var webcams: [Webcam] = []
    @State private var isLoading = true
    @State private var backSelection = "emulated"
    @State private var frontSelection = "emulated"
    @State private var applied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Camera source").font(.title3.bold())
                Spacer()
                Button("Done") { dismiss() }
            }

            Text("Pick a real camera for the back/front Android camera. On this Mac "
               + "that includes the built-in camera and, with Continuity Camera on "
               + "(System Settings → General → AirDrop & Handoff, same Apple ID, "
               + "Wi-Fi + Bluetooth on both devices, iPhone nearby), your iPhone's "
               + "camera — it shows up in the list below like any other webcam.")
                .font(.caption)
                .foregroundColor(.secondary)

            if isLoading {
                ProgressView("Looking for cameras…")
            } else if webcams.isEmpty {
                Text("No webcams detected. Connect one or turn on Continuity Camera, "
                   + "then Refresh.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            Picker("Back camera", selection: $backSelection) {
                ForEach(options, id: \.id) { Text($0.label).tag($0.id) }
            }
            Picker("Front camera", selection: $frontSelection) {
                ForEach(options, id: \.id) { Text($0.label).tag($0.id) }
            }

            HStack {
                Button("Refresh list") { Task { await loadWebcams() } }
                Spacer()
                Button("Apply") { apply() }
                    .buttonStyle(.borderedProminent)
            }

            if applied {
                Text(emulator.isRunning
                     ? "Saved. Restart Android for the new camera to take effect."
                     : "Saved. It'll be used next time you start Android.")
                    .font(.caption).foregroundColor(.green)
                if emulator.isRunning {
                    Button("Restart now") {
                        emulator.stop()
                        Task {
                            try? await Task.sleep(nanoseconds: 2_000_000_000)
                            emulator.start(avdName: avdName)
                        }
                        dismiss()
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 420, height: 360)
        .task {
            if let current = avdService?.currentCameraSelection(for: avdName) {
                backSelection = current.back
                frontSelection = current.front
            }
            await loadWebcams()
        }
    }

    private var options: [(id: String, label: String)] {
        builtin + webcams.map { ($0.id, "\($0.id) — \($0.deviceName)") }
    }

    private func loadWebcams() async {
        isLoading = true
        webcams = await emulator.listWebcams()
        isLoading = false
    }

    private func apply() {
        _ = avdService?.setCamera(for: avdName, back: backSelection, front: frontSelection)
        applied = true
    }
}
