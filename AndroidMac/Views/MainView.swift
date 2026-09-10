import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @ObservedObject var avdManager: AVDManagerViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if avdManager.isCreating {
                Spacer()
                ProgressView("Creating Android device…")
                Spacer()
            } else if let avd = avdManager.selectedAVD, let emulator = avdManager.emulatorService {
                EmulatorControlView(emulator: emulator, avdName: avd)
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Text(avdManager.errorMessage ?? "No Android device available.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(avdManager.errorMessage == nil ? .secondary : .red)
                        .textSelection(.enabled)
                    Button("Create default device") { avdManager.createDefault() }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
                Spacer()
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Android Phone")
                .font(.title2.bold())
            Spacer()
            Image(systemName: "gearshape")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
    }
}

/// Everything that needs to react live to the emulator's state.
struct EmulatorControlView: View {
    @ObservedObject var emulator: EmulatorService
    let avdName: String

    @State private var showFileImporter = false
    @State private var typeText = ""
    @State private var gsfID: String?
    @State private var googleBusy = false
    @FocusState private var typeFieldFocused: Bool

    private var isReady: Bool { emulator.status.contains("Ready") }

    var body: some View {
        VStack(spacing: 16) {
            deviceCard

            if emulator.isRunning {
                Button("STOP ANDROID") { emulator.stop() }
                    .buttonStyle(.borderedProminent).tint(.red)
            } else {
                Button("START ANDROID") { emulator.start(avdName: avdName) }
                    .buttonStyle(.borderedProminent).tint(.green)
            }

            if let error = emulator.lastError {
                Text(error).font(.footnote).foregroundColor(.red)
                    .multilineTextAlignment(.center).textSelection(.enabled)
            }

            Spacer()

            if isReady {
                keyboardBar
                Divider()
                googleSignInBar
                Divider()
                navigationBar
            }
        }
        .padding()
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [UTType(filenameExtension: "apk") ?? .item]) { result in
            if case .success(let url) = result { installAPK(url: url) }
        }
    }

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Device: \(avdName)")
            Text("Architecture: arm64 · GPU: host")
            Text("Status: \(emulator.status)")
                .foregroundColor(isReady ? .green : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    /// Type into the guest straight from the Mac keyboard.
    private var keyboardBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Type with your Mac keyboard")
                .font(.caption).foregroundColor(.secondary)
            HStack(spacing: 8) {
                TextField("Text to send to the focused field…", text: $typeText)
                    .textFieldStyle(.roundedBorder)
                    .focused($typeFieldFocused)
                    .onSubmit(sendText)
                Button("Send", action: sendText)
                    .disabled(typeText.isEmpty)
                Button {
                    Task { try? await emulator.adbService.sendKeyEvent(66) }
                } label: { Image(systemName: "return") }
                .help("Send Enter")
            }
            Text("Tip: the emulator window also accepts your Mac keyboard directly (hardware keyboard is enabled).")
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    /// Recover from "can't sign in to Google / device not certified".
    private var googleSignInBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Google sign-in").font(.caption).foregroundColor(.secondary)
            HStack(spacing: 8) {
                Button("Register device") {
                    NSWorkspace.shared.open(URL(string: "https://www.google.com/android/uncertified")!)
                    Task { gsfID = await emulator.adbService.googleServicesFrameworkID() }
                }
                .help("Opens the Play certification page. Paste the ID below (or dial *#*#8255#*#* in the emulator).")

                Button("Reset & reboot") {
                    googleBusy = true
                    Task {
                        try? await emulator.adbService.resetGoogleLogin()
                        googleBusy = false
                    }
                }
                .disabled(googleBusy)
                .help("Clears cached Google login + Play Store data, then reboots.")

                if googleBusy { ProgressView().controlSize(.small) }
            }
            if let gsfID {
                Text("GSF ID: \(gsfID)")
                    .font(.caption2).textSelection(.enabled).foregroundColor(.secondary)
            }
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 20) {
            ControlButton(icon: "chevron.backward", help: "Back") { sendKey(4) }
            ControlButton(icon: "circle", help: "Home") { sendKey(3) }
            ControlButton(icon: "square.on.square", help: "Recents") { sendKey(187) }
            Divider().frame(height: 20)
            ControlButton(icon: "camera", help: "Screenshot to Desktop", action: takeScreenshot)
            Button("APK") { showFileImporter = true }
                .buttonStyle(.bordered)
                .help("Install an .apk on the device")
        }
    }

    // MARK: Actions

    private func sendText() {
        let text = typeText
        guard !text.isEmpty else { return }
        typeText = ""
        typeFieldFocused = true
        Task { try? await emulator.adbService.inputText(text) }
    }

    private func sendKey(_ code: Int) {
        Task { try? await emulator.adbService.sendKeyEvent(code) }
    }

    private func takeScreenshot() {
        Task {
            let path = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop/Screenshot-\(Int(Date().timeIntervalSince1970)).png")
            try? await emulator.adbService.takeScreenshot(saveTo: path.path)
        }
    }

    private func installAPK(url: URL) {
        Task {
            let result = try? await emulator.adbService.installAPK(url: url)
            print("APK install: \(result?.stdout ?? "") \(result?.stderr ?? "")")
        }
    }
}

struct ControlButton: View {
    let icon: String
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.title3)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
