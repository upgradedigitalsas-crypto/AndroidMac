import Foundation

enum SDKManagerError: LocalizedError {
    case javaMissing
    case downloadFailed
    case installationFailed(String)

    var errorDescription: String? {
        switch self {
        case .javaMissing:
            return "Java 17+ is required by the Android command-line tools. "
                 + "Install it with:  brew install openjdk@17"
        case .downloadFailed:
            return "Could not download the Android command-line tools. Check your connection and retry."
        case .installationFailed(let detail):
            return detail.isEmpty ? "SDK installation failed." : detail
        }
    }
}

@MainActor
class AndroidSDKManager: ObservableObject {
    static let shared = AndroidSDKManager()

    @Published var isSDKInstalled: Bool = false
    @Published var isInstalling: Bool = false
    @Published var statusMessage: String = "Checking Android SDK…"
    @Published var errorMessage: String?

    /// API level that ended up installed (dynamic "latest" or the configured fallback).
    @Published private(set) var installedAPILevel: Int = AndroidConfig.preferredAPILevel

    let sdkRoot: URL

    init() {
        sdkRoot = AndroidEnvironment.sdkRoot
        checkInstallation()
    }

    func checkInstallation() {
        let fm = FileManager.default
        let sdkmanager = sdkRoot.appendingPathComponent("cmdline-tools/latest/bin/sdkmanager")
        let adb = sdkRoot.appendingPathComponent("platform-tools/adb")
        let emulator = sdkRoot.appendingPathComponent("emulator/emulator")

        isSDKInstalled = fm.fileExists(atPath: sdkmanager.path)
            && fm.fileExists(atPath: adb.path)
            && fm.fileExists(atPath: emulator.path)
        if isSDKInstalled { statusMessage = "Ready." }
    }

    func installSDK() async {
        isInstalling = true
        errorMessage = nil
        defer { isInstalling = false }   // never leave the UI stuck on a spinner

        do {
            guard AndroidEnvironment.javaHome() != nil else { throw SDKManagerError.javaMissing }

            try await ensureCommandLineTools()
            let api = await resolveLatestAPILevel()
            installedAPILevel = api

            try await acceptLicenses()
            try await installPackages(api: api)

            checkInstallation()
            if isSDKInstalled {
                statusMessage = "Ready."
            } else {
                throw SDKManagerError.installationFailed(
                    "Packages installed but the emulator/adb binaries are missing. Try again.")
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errorMessage = message
            statusMessage = "Setup failed."
        }
    }

    // MARK: - Steps

    private func ensureCommandLineTools() async throws {
        let latestDir = sdkRoot.appendingPathComponent("cmdline-tools/latest")
        if FileManager.default.fileExists(atPath: latestDir.appendingPathComponent("bin/sdkmanager").path) {
            return
        }

        statusMessage = "Downloading command-line tools…"
        let fm = FileManager.default
        try? fm.createDirectory(at: sdkRoot, withIntermediateDirectories: true)

        let toolsURL = URL(string: "https://dl.google.com/android/repository/commandlinetools-mac-11479570_latest.zip")!
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 600   // 10 min hard cap, not an infinite hang
        config.timeoutIntervalForRequest = 120
        let session = URLSession(configuration: config)

        let tempURL: URL
        do {
            (tempURL, _) = try await session.download(from: toolsURL)
        } catch {
            throw SDKManagerError.downloadFailed
        }

        statusMessage = "Extracting command-line tools…"
        let cmdlineToolsDir = sdkRoot.appendingPathComponent("cmdline-tools")
        try? fm.removeItem(at: cmdlineToolsDir)
        try fm.createDirectory(at: cmdlineToolsDir, withIntermediateDirectories: true)

        let unzip = try await ProcessRunner.runCommand(
            URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-q", tempURL.path, "-d", cmdlineToolsDir.path],
            timeout: 180)
        guard unzip.isSuccess else {
            throw SDKManagerError.installationFailed("Failed to extract tools: \(unzip.stderr)")
        }

        let extracted = cmdlineToolsDir.appendingPathComponent("cmdline-tools")
        try? fm.removeItem(at: latestDir)
        try fm.moveItem(at: extracted, to: latestDir)
    }

    /// Ask `sdkmanager` for the newest installable `arm64-v8a` Play Store image and
    /// use it when it is newer than the configured fallback. Keeps "latest Android"
    /// working without editing code each release.
    private func resolveLatestAPILevel() async -> Int {
        statusMessage = "Resolving latest Android version…"
        let sdkmanager = sdkRoot.appendingPathComponent("cmdline-tools/latest/bin/sdkmanager").path
        guard let result = try? await ProcessRunner.runShell(
            "\"\(sdkmanager)\" --sdk_root=\"\(sdkRoot.path)\" --list 2>/dev/null "
            + "| grep -oE 'system-images;android-[0-9]+;\(AndroidConfig.systemImageTag);\(AndroidConfig.abi)'",
            timeout: 120),
              result.isSuccess else {
            return AndroidConfig.preferredAPILevel
        }

        let levels = result.stdout
            .split(separator: "\n")
            .compactMap { line -> Int? in
                line.split(separator: ";")
                    .first { $0.hasPrefix("android-") }
                    .flatMap { Int($0.dropFirst("android-".count)) }
            }
        let best = levels.max() ?? AndroidConfig.preferredAPILevel
        return max(best, AndroidConfig.preferredAPILevel, AndroidConfig.minimumAPILevel)
    }

    private func acceptLicenses() async throws {
        statusMessage = "Accepting SDK licenses…"
        let sdkmanager = sdkRoot.appendingPathComponent("cmdline-tools/latest/bin/sdkmanager").path
        // `yes |` breaks on recent cmdline-tools; feed a bounded stream instead.
        let result = try await ProcessRunner.runShell(
            "for i in $(seq 1 100); do echo y; done | "
            + "\"\(sdkmanager)\" --sdk_root=\"\(sdkRoot.path)\" --licenses",
            timeout: 180)
        // A non-zero exit here is not fatal — the install step re-prompts if needed.
        if !result.isSuccess {
            statusMessage = "Licenses step returned \(result.exitCode); continuing…"
        }
    }

    private func installPackages(api: Int) async throws {
        statusMessage = "Installing Android \(androidVersionName(api)) (API \(api))… this downloads ~1.5 GB."
        let sdkmanager = sdkRoot.appendingPathComponent("cmdline-tools/latest/bin/sdkmanager").path
        let packages = [
            "platform-tools",
            "emulator",
            AndroidConfig.platform(api: api),
            AndroidConfig.systemImage(api: api),
        ]
        let quoted = packages.map { "\"\($0)\"" }.joined(separator: " ")

        let result = try await ProcessRunner.runShell(
            "for i in $(seq 1 100); do echo y; done | "
            + "\"\(sdkmanager)\" --sdk_root=\"\(sdkRoot.path)\" \(quoted)",
            timeout: 1800)   // 30 min: large image download

        guard result.isSuccess else {
            throw SDKManagerError.installationFailed(
                "Failed to install packages (exit \(result.exitCode)).\n"
                + (result.stderr.isEmpty ? result.stdout : result.stderr))
        }
    }

    private func androidVersionName(_ api: Int) -> String {
        switch api {
        case 34: return "14"
        case 35: return "15"
        case 36: return "16"
        case 37: return "17"
        default: return "API \(api)"
        }
    }
}
