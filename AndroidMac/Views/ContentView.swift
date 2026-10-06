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
        .frame(width: 400, height: 600)
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
    @Published var isCreating = false
    @Published var errorMessage: String?

    /// Which session ("patrón") is selected. Persisted across launches.
    @Published private(set) var profile: AndroidProfile = AndroidProfile.stored()

    /// The AVD of the selected profile, once it exists on disk.
    var selectedAVD: String? { avds.contains(profile.avdName) ? profile.avdName : nil }

    private(set) var service: AVDManagerService?
    @Published var emulatorService: EmulatorService?

    func loadAVDs(sdkRoot: URL, apiLevel: Int) {
        let service = AVDManagerService(sdkRoot: sdkRoot, apiLevel: apiLevel)
        self.service = service
        self.emulatorService = EmulatorService(sdkRoot: sdkRoot)
        self.errorMessage = nil

        Task {
            do {
                self.avds = try await service.listAVDs()
                await ensureProfileExists()
            } catch {
                self.errorMessage = "Could not list Android devices: \(error.localizedDescription)"
            }
        }
    }

    /// Switch session. Ignored while Android is running — two emulators at once
    /// would make every `adb` call ambiguous ("more than one device").
    func selectProfile(_ newProfile: AndroidProfile) {
        guard newProfile != profile, emulatorService?.isRunning != true else { return }
        profile = newProfile
        newProfile.store()
        errorMessage = nil
        Task { await ensureProfileExists() }
    }

    /// Start the selected session. Patrón 2 erases its own data first; Patrón 1
    /// never does.
    func startSelected(coldBoot: Bool = false) {
        guard let avd = selectedAVD, let emulator = emulatorService else { return }
        emulator.start(avdName: avd, coldBoot: coldBoot, wipeData: profile.wipesOnLaunch)
    }

    func createDefault() {
        Task { await ensureProfileExists() }
    }

    /// Create the selected profile's AVD only if it's missing — never touches
    /// an existing one (that's where the user's data lives).
    private func ensureProfileExists() async {
        guard let service else { return }
        if avds.contains(profile.avdName) {
            service.applyHardwareConfig(to: profile.avdName)   // keyboard/GPU tuning
            return
        }
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        do {
            try await service.createAVD(named: profile.avdName)
            avds = try await service.listAVDs()
        } catch {
            errorMessage = "Could not create the Android device: \(error.localizedDescription)"
        }
    }
}
