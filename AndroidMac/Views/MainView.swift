import SwiftUI

struct MainView: View {
    @ObservedObject var avdManager: AVDManagerViewModel
    @State private var showFileImporter = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Android Phone")
                    .font(.title2.bold())
                Spacer()
                Button(action: {}) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Status and Start
            VStack(spacing: 20) {
                if avdManager.isCreating {
                    ProgressView("Creating Android Device...")
                } else if let avd = avdManager.selectedAVD {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Device: \(avd)")
                        Text("Architecture: arm64")
                        Text("Status: \(avdManager.emulatorService?.status ?? "Unknown")")
                            .foregroundColor((avdManager.emulatorService?.status.contains("Ready") == true) ? .green : .secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    
                    if let emulator = avdManager.emulatorService {
                        if emulator.isRunning {
                            Button("STOP ANDROID") {
                                emulator.stop()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        } else {
                            Button("START ANDROID") {
                                emulator.start(avdName: avd)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        }
                    }
                }
            }
            .padding()
            
            Spacer()
            
            // Controls
            if avdManager.emulatorService?.status.contains("Ready") == true {
                Divider()
                HStack(spacing: 20) {
                    ControlButton(icon: "arrow.left", action: { sendKey(4) }) // KEYCODE_BACK
                    ControlButton(icon: "circle", action: { sendKey(3) }) // KEYCODE_HOME
                    ControlButton(icon: "square", action: { sendKey(187) }) // KEYCODE_APP_SWITCH
                    
                    Divider().frame(height: 20)
                    
                    ControlButton(icon: "rotate.left", action: {
                        // Rotation isn't universally mapped to a simple key in emulator, but usually requires telnet or specific commands.
                        // We'll map standard keyevents where possible.
                    })
                    ControlButton(icon: "camera", action: takeScreenshot)
                    
                    Button("APK") {
                        showFileImporter = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url):
                installAPK(url: url)
            case .failure(let error):
                print(error)
            }
        }
    }
    
    func sendKey(_ code: Int) {
        Task {
            try? await avdManager.emulatorService?.adbService.sendKeyEvent(code)
        }
    }
    
    func takeScreenshot() {
        Task {
            let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/Screenshot-\(Date().timeIntervalSince1970).png")
            try? await avdManager.emulatorService?.adbService.takeScreenshot(saveTo: path.path)
        }
    }
    
    func installAPK(url: URL) {
        Task {
            let result = try? await avdManager.emulatorService?.adbService.installAPK(url: url)
            print("APK Install result: \(result?.stdout ?? "") \(result?.stderr ?? "")")
        }
    }
}

struct ControlButton: View {
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
        }
        .buttonStyle(.plain)
    }
}
