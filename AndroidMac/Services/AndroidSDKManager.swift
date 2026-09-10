import Foundation

enum SDKManagerError: Error {
    case downloadFailed
    case installationFailed(String)
}

class AndroidSDKManager: ObservableObject {
    static let shared = AndroidSDKManager()
    
    @Published var isSDKInstalled: Bool = false
    @Published var isInstalling: Bool = false
    @Published var statusMessage: String = "Checking Android SDK..."
    
    let sdkRoot: URL
    
    init() {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        sdkRoot = homeDir.appendingPathComponent("Library/Android/sdk")
        checkInstallation()
    }
    
    func checkInstallation() {
        let sdkmanagerPath = sdkRoot.appendingPathComponent("cmdline-tools/latest/bin/sdkmanager")
        let adbPath = sdkRoot.appendingPathComponent("platform-tools/adb")
        let emulatorPath = sdkRoot.appendingPathComponent("emulator/emulator")
        
        isSDKInstalled = FileManager.default.fileExists(atPath: sdkmanagerPath.path) &&
                         FileManager.default.fileExists(atPath: adbPath.path) &&
                         FileManager.default.fileExists(atPath: emulatorPath.path)
    }
    
    func installSDK() async throws {
        DispatchQueue.main.async {
            self.isInstalling = true
            self.statusMessage = "Downloading Command Line Tools..."
        }
        
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: sdkRoot.path) {
            try fileManager.createDirectory(at: sdkRoot, withIntermediateDirectories: true)
        }
        
        // 1. Download command line tools
        let toolsURL = URL(string: "https://dl.google.com/android/repository/commandlinetools-mac-11479570_latest.zip")!
        let (tempURL, _) = try await URLSession.shared.download(from: toolsURL)
        
        DispatchQueue.main.async {
            self.statusMessage = "Extracting Command Line Tools..."
        }
        
        // 2. Extract using unzip
        let cmdlineToolsDir = sdkRoot.appendingPathComponent("cmdline-tools")
        if fileManager.fileExists(atPath: cmdlineToolsDir.path) {
            try fileManager.removeItem(at: cmdlineToolsDir)
        }
        try fileManager.createDirectory(at: cmdlineToolsDir, withIntermediateDirectories: true)
        
        let unzipResult = try await ProcessRunner.runCommand(URL(fileURLWithPath: "/usr/bin/unzip"), arguments: ["-q", tempURL.path, "-d", cmdlineToolsDir.path])
        if unzipResult.exitCode != 0 {
            throw SDKManagerError.installationFailed("Failed to extract tools: \(unzipResult.stderr)")
        }
        
        // 3. Move cmdline-tools/cmdline-tools to cmdline-tools/latest
        let extractedDir = cmdlineToolsDir.appendingPathComponent("cmdline-tools")
        let latestDir = cmdlineToolsDir.appendingPathComponent("latest")
        try fileManager.moveItem(at: extractedDir, to: latestDir)
        
        // 4. Accept licenses and install platform-tools, emulator, and system-image
        DispatchQueue.main.async {
            self.statusMessage = "Installing SDK packages..."
        }
        
        let sdkmanager = latestDir.appendingPathComponent("bin/sdkmanager")
        
        let packages = [
            "\"platform-tools\"",
            "\"emulator\"",
            "\"system-images;android-34;google_apis_playstore;arm64-v8a\"",
            "\"platforms;android-34\""
        ]
        
        // Accept licenses
        let yes = Data(repeating: 121, count: 1000) // 'y' * 1000
        let yesURL = FileManager.default.temporaryDirectory.appendingPathComponent("yes.txt")
        try yes.write(to: yesURL)
        
        let installResult = try await ProcessRunner.runCommand(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "yes | \"\(sdkmanager.path)\" --sdk_root=\"\(sdkRoot.path)\" \(packages.joined(separator: " "))"]
        )
        
        if installResult.exitCode != 0 {
            throw SDKManagerError.installationFailed("Failed to install packages: \(installResult.stderr)")
        }
        
        DispatchQueue.main.async {
            self.statusMessage = "Ready."
            self.isSDKInstalled = true
            self.isInstalling = false
        }
    }
}
