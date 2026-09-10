import Foundation

class ADBService {
    let adb: URL
    let sdkRoot: URL

    init(sdkRoot: URL) {
        self.sdkRoot = sdkRoot
        self.adb = sdkRoot.appendingPathComponent("platform-tools/adb")
    }

    private var env: [String: String] { AndroidEnvironment.toolchain(sdkRoot: sdkRoot) }

    @discardableResult
    private func run(_ args: [String], timeout: TimeInterval = 30) async throws -> ProcessResult {
        try await ProcessRunner.runCommand(adb, arguments: args, environment: env, timeout: timeout)
    }

    func startServer() async throws { try await run(["start-server"]) }

    func waitForDevice() async throws { try await run(["wait-for-device"], timeout: 180) }

    func isBootCompleted() async -> Bool {
        guard let result = try? await run(["shell", "getprop", "sys.boot_completed"], timeout: 10) else {
            return false
        }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    func sendKeyEvent(_ code: Int) async throws {
        try await run(["shell", "input", "keyevent", "\(code)"])
    }

    /// Type a string into whatever field currently has focus in the guest.
    /// `adb shell input text` needs spaces encoded as `%s` and can't carry newlines.
    func inputText(_ text: String) async throws {
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            if !line.isEmpty {
                let encoded = line
                    .replacingOccurrences(of: " ", with: "%s")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                try await run(["shell", "input", "text", encoded])
            }
            if index < lines.count - 1 {
                try await sendKeyEvent(66)   // KEYCODE_ENTER
            }
        }
    }

    func installAPK(url: URL) async throws -> ProcessResult {
        try await run(["install", "-r", url.path], timeout: 300)
    }

    func takeScreenshot(saveTo path: String) async throws {
        try await run(["shell", "screencap", "-p", "/sdcard/screen.png"])
        try await run(["pull", "/sdcard/screen.png", path], timeout: 60)
        try await run(["shell", "rm", "/sdcard/screen.png"])
    }

    func getLogs() async throws -> String {
        try await run(["logcat", "-d"], timeout: 30).stdout
    }

    func clearLogs() async throws { try await run(["logcat", "-c"]) }

    /// Ask the emulator to save its Quick Boot snapshot and exit cleanly.
    func emuKill() async { _ = try? await run(["emu", "kill"], timeout: 15) }

    // MARK: Google sign-in recovery

    /// The Google Services Framework Android ID, needed to register the emulator
    /// at google.com/android/uncertified when sign-in is blocked as "not
    /// certified". Returns `nil` when the provider isn't readable (dial
    /// `*#*#8255#*#*` in the emulator to read it manually in that case).
    func googleServicesFrameworkID() async -> String? {
        let query = "content query --uri content://com.google.android.gsf/gservices "
                  + "--projection value --where \"name=\\'android_id\\'\""
        guard let r = try? await run(["shell", query], timeout: 15), r.isSuccess else { return nil }
        // Output looks like: Row: 0 value=3f1c...
        guard let range = r.stdout.range(of: "value=") else { return nil }
        let id = r.stdout[range.upperBound...].prefix { $0 != " " && $0 != "\n" }
        return id.isEmpty ? nil : String(id)
    }

    /// Clear the cached Google login state and reboot so the sign-in flow starts
    /// fresh (run after registering the device or updating Play services).
    func resetGoogleLogin() async throws {
        _ = try? await run(["shell", "pm", "clear", "com.google.android.gsf.login"], timeout: 20)
        _ = try? await run(["shell", "pm", "clear", "com.android.vending"], timeout: 20)
        try await run(["reboot"], timeout: 20)
    }
}

@MainActor
class EmulatorService: ObservableObject {
    let sdkRoot: URL
    let emulator: URL
    let adbService: ADBService

    @Published var isRunning = false
    @Published var status = "Stopped"
    @Published var lastError: String?

    private var process: Process?

    init(sdkRoot: URL) {
        self.sdkRoot = sdkRoot
        self.emulator = sdkRoot.appendingPathComponent("emulator/emulator")
        self.adbService = ADBService(sdkRoot: sdkRoot)
    }

    /// - Parameter coldBoot: ignore any saved snapshot for this run. Use it when
    ///   the emulator window opens blank/white (a poisoned GPU snapshot).
    func start(avdName: String, coldBoot: Bool = false) {
        guard !isRunning else { return }
        status = coldBoot ? "Cold booting emulator…" : "Starting emulator…"
        isRunning = true
        lastError = nil

        // Make sure host-keyboard + GPU tuning are present even for AVDs that a
        // previous version created without them.
        AVDManagerService(sdkRoot: sdkRoot).applyHardwareConfig(to: avdName)

        let emulatorURL = emulator
        let env = AndroidEnvironment.toolchain(sdkRoot: sdkRoot)
        let args = ["-avd", avdName] + AndroidConfig.emulatorLaunchArgs(coldBoot: coldBoot)

        let proc = Process()
        proc.executableURL = emulatorURL
        proc.arguments = args
        var procEnv = ProcessInfo.processInfo.environment
        for (k, v) in env { procEnv[k] = v }
        proc.environment = procEnv
        self.process = proc

        do {
            try proc.run()
        } catch {
            self.isRunning = false
            self.status = "Failed to start"
            self.lastError = error.localizedDescription
            return
        }

        // Watch for process exit (Task inherits the main actor).
        Task { [weak self] in
            while proc.isRunning { try? await Task.sleep(nanoseconds: 500_000_000) }
            guard let self else { return }
            self.isRunning = false
            self.status = "Stopped"
            self.process = nil
        }

        // Poll for boot completion.
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.adbService.startServer()
                try await self.adbService.waitForDevice()
                self.status = "Waiting for Android to boot…"

                for _ in 0..<180 {   // up to ~6 min for a cold boot on first run
                    if await self.adbService.isBootCompleted() {
                        self.status = "● Ready"
                        return
                    }
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                }
                // Timed out waiting, but the emulator process is still alive —
                // keep it running rather than forcing the user to restart.
                self.status = "Booting is taking longer than usual…"
            } catch {
                self.status = "Error: \(error.localizedDescription)"
                self.lastError = error.localizedDescription
            }
        }
    }

    func stop() {
        status = "Stopping…"
        let adb = adbService
        let proc = process
        Task {   // inherits the main actor from @MainActor class
            await adb.emuKill()          // triggers Quick Boot snapshot save
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            proc?.terminate()
            self.isRunning = false
            self.status = "Stopped"
        }
    }
}
