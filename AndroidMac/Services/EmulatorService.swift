import Foundation

class ADBService {
    let adb: URL
    
    init(sdkRoot: URL) {
        self.adb = sdkRoot.appendingPathComponent("platform-tools/adb")
    }
    
    func startServer() async throws {
        _ = try await ProcessRunner.runCommand(adb, arguments: ["start-server"])
    }
    
    func waitForDevice() async throws {
        _ = try await ProcessRunner.runCommand(adb, arguments: ["wait-for-device"])
    }
    
    func isBootCompleted() async -> Bool {
        do {
            let result = try await ProcessRunner.runCommand(adb, arguments: ["shell", "getprop", "sys.boot_completed"])
            return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        } catch {
            return false
        }
    }
    
    func sendKeyEvent(_ code: Int) async throws {
        _ = try await ProcessRunner.runCommand(adb, arguments: ["shell", "input", "keyevent", "\(code)"])
    }
    
    func installAPK(url: URL) async throws -> ProcessResult {
        return try await ProcessRunner.runCommand(adb, arguments: ["install", "-r", url.path])
    }
    
    func takeScreenshot(saveTo path: String) async throws {
        // Screenshot inside emulator then pull it
        _ = try await ProcessRunner.runCommand(adb, arguments: ["shell", "screencap", "-p", "/sdcard/screen.png"])
        _ = try await ProcessRunner.runCommand(adb, arguments: ["pull", "/sdcard/screen.png", path])
        _ = try await ProcessRunner.runCommand(adb, arguments: ["shell", "rm", "/sdcard/screen.png"])
    }
    
    func getLogs() async throws -> String {
        let result = try await ProcessRunner.runCommand(adb, arguments: ["logcat", "-d"])
        return result.stdout
    }
    
    func clearLogs() async throws {
        _ = try await ProcessRunner.runCommand(adb, arguments: ["logcat", "-c"])
    }
}

class EmulatorService: ObservableObject {
    let sdkRoot: URL
    let emulator: URL
    let adbService: ADBService
    
    @Published var isRunning = false
    @Published var status = "Stopped"
    
    var process: Process?
    
    init(sdkRoot: URL) {
        self.sdkRoot = sdkRoot
        self.emulator = sdkRoot.appendingPathComponent("emulator/emulator")
        self.adbService = ADBService(sdkRoot: sdkRoot)
    }
    
    func start(avdName: String) {
        status = "Starting Emulator..."
        isRunning = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.process = Process()
            self.process?.executableURL = self.emulator
            // Launch emulator
            self.process?.arguments = ["-avd", avdName, "-netdelay", "none", "-netspeed", "full"]
            
            do {
                try self.process?.run()
                
                Task {
                    do {
                        try await self.adbService.startServer()
                        try await self.adbService.waitForDevice()
                        
                        DispatchQueue.main.async {
                            self.status = "Waiting for Android boot..."
                        }
                        
                        var booted = false
                        for _ in 0..<60 {
                            if await self.adbService.isBootCompleted() {
                                booted = true
                                break
                            }
                            try await Task.sleep(nanoseconds: 2_000_000_000)
                        }
                        
                        DispatchQueue.main.async {
                            if booted {
                                self.status = "● Ready"
                            } else {
                                self.status = "Error: Boot timeout"
                                self.isRunning = false
                            }
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.status = "Error: \(error.localizedDescription)"
                            self.isRunning = false
                        }
                    }
                }
                
                self.process?.waitUntilExit()
                
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.status = "Stopped"
                }
            } catch {
                DispatchQueue.main.async {
                    self.status = "Failed to start"
                    self.isRunning = false
                }
            }
        }
    }
    
    func stop() {
        process?.terminate()
        isRunning = false
        status = "Stopped"
    }
}
