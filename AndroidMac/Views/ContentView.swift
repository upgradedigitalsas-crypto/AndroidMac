import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var sdkManager = AndroidSDKManager.shared
    @StateObject private var avdManager = AVDManagerViewModel()
    
    var body: some View {
        VStack {
            if !sdkManager.isSDKInstalled {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.yellow)
                    Text("Android environment incomplete")
                        .font(.headline)
                    if sdkManager.isInstalling {
                        ProgressView(sdkManager.statusMessage)
                    } else {
                        Button("SET UP ANDROID") {
                            Task {
                                try? await sdkManager.installSDK()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
            } else {
                MainView(avdManager: avdManager)
            }
        }
        .frame(width: 400, height: 500)
        .onAppear {
            if sdkManager.isSDKInstalled {
                avdManager.loadAVDs(sdkRoot: sdkManager.sdkRoot)
            }
        }
        .onChange(of: sdkManager.isSDKInstalled) { installed in
            if installed {
                avdManager.loadAVDs(sdkRoot: sdkManager.sdkRoot)
            }
        }
    }
}

class AVDManagerViewModel: ObservableObject {
    @Published var avds: [String] = []
    @Published var selectedAVD: String?
    @Published var isCreating = false
    
    var service: AVDManagerService?
    var emulatorService: EmulatorService?
    
    func loadAVDs(sdkRoot: URL) {
        service = AVDManagerService(sdkRoot: sdkRoot)
        emulatorService = EmulatorService(sdkRoot: sdkRoot)
        
        Task {
            do {
                let list = try await service?.listAVDs() ?? []
                DispatchQueue.main.async {
                    self.avds = list
                    if self.avds.isEmpty {
                        self.createDefault()
                    } else {
                        self.selectedAVD = self.avds.first
                    }
                }
            } catch {
                print(error)
            }
        }
    }
    
    func createDefault() {
        isCreating = true
        Task {
            do {
                try await service?.createDefaultAVD()
                let list = try await service?.listAVDs() ?? []
                DispatchQueue.main.async {
                    self.avds = list
                    self.selectedAVD = list.first
                    self.isCreating = false
                }
            } catch {
                print(error)
                DispatchQueue.main.async { self.isCreating = false }
            }
        }
    }
}
