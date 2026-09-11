import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var sdkManager = AndroidSDKManager.shared
    @StateObject private var avdManager = AVDManagerViewModel()
    @StateObject private var cloudSync = CloudSyncService()

    var body: some View {
        VStack {
            if !sdkManager.isSDKInstalled {
                setupView
            } else {
                MainView(avdManager: avdManager, cloudSync: cloudSync)
            }
        }
        .frame(width: 400, height: 520)
        .onAppear {
            cloudSync.avdManager = avdManager
            cloudSync.startPolling()
            if sdkManager.isSDKInstalled {
                avdManager.loadAVDs(sdkRoot: sdkManager.sdkRoot, apiLevel: sdkManager.installedAPILevel)
            }
        }
        .onChange(of: sdkManager.isSDKInstalled) { _, installed in
            if installed {
                avdManager.loadAVDs(sdkRoot: sdkManager.sdkRoot, apiLevel: sdkManager.installedAPILevel)
            }
        }
    }

    private var setupView: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.yellow)
            Text("Android environment incomplete")
                .font(.headline)

            if sdkManager.isInstalling {
                ProgressView(sdkManager.statusMessage)
                    .multilineTextAlignment(.center)
            } else {
                if let error = sdkManager.errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                }
                Button(sdkManager.errorMessage == nil ? "SET UP ANDROID" : "RETRY SETUP") {
                    Task { await sdkManager.installSDK() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

@MainActor
class AVDManagerViewModel: ObservableObject {
    @Published var avds: [String] = []
    @Published var selectedAVD: String?
    @Published var isCreating = false
    @Published var errorMessage: String?

    private(set) var service: AVDManagerService?
    @Published var emulatorService: EmulatorService?

    func loadAVDs(sdkRoot: URL, apiLevel: Int) {
        let service = AVDManagerService(sdkRoot: sdkRoot, apiLevel: apiLevel)
        self.service = service
        self.emulatorService = EmulatorService(sdkRoot: sdkRoot)
        self.errorMessage = nil

        Task {
            do {
                let list = try await service.listAVDs()
                self.avds = list
                if let first = list.first {
                    self.selectedAVD = first
                    service.applyHardwareConfig(to: first)   // pick up keyboard/GPU tuning
                } else {
                    self.createDefault()
                }
            } catch {
                self.errorMessage = "Could not list Android devices: \(error.localizedDescription)"
            }
        }
    }

    func createDefault() {
        guard let service else { return }
        isCreating = true
        errorMessage = nil
        Task {
            defer { self.isCreating = false }
            do {
                try await service.createDefaultAVD()
                let list = try await service.listAVDs()
                self.avds = list
                self.selectedAVD = list.first
            } catch {
                self.errorMessage = "Could not create the Android device: \(error.localizedDescription)"
            }
        }
    }
}
