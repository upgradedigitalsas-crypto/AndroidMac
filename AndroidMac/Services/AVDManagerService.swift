import Foundation

class AVDManagerService {
    let sdkRoot: URL
    let avdmanager: URL
    
    init(sdkRoot: URL) {
        self.sdkRoot = sdkRoot
        self.avdmanager = sdkRoot.appendingPathComponent("cmdline-tools/latest/bin/avdmanager")
    }
    
    func listAVDs() async throws -> [String] {
        let result = try await ProcessRunner.runCommand(avdmanager, arguments: ["list", "avd", "-c"])
        if result.exitCode == 0 {
            return result.stdout.components(separatedBy: "\n").filter { !$0.isEmpty }
        }
        return []
    }
    
    func createDefaultAVD() async throws {
        let avdName = "Antigravity_Phone"
        let package = "system-images;android-34;google_apis_playstore;arm64-v8a"
        let device = "pixel"
        
        let result = try await ProcessRunner.runCommand(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "echo no | \"\(avdmanager.path)\" create avd -n \"\(avdName)\" -k \"\(package)\" -d \"\(device)\" --force"]
        )
        
        if result.exitCode != 0 {
            throw ProcessError.executionFailed(result.exitCode, result.stdout, result.stderr)
        }
        
        // Update config.ini to set properties like RAM, disk, resolution if needed
        let avdDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".android/avd/\(avdName).avd")
        let configPath = avdDir.appendingPathComponent("config.ini")
        if FileManager.default.fileExists(atPath: configPath.path) {
            var config = try String(contentsOf: configPath, encoding: .utf8)
            config += "\nhw.ramSize=4096"
            config += "\ndisk.dataPartition.size=32G"
            config += "\nhw.lcd.density=420"
            config += "\nhw.lcd.height=2400"
            config += "\nhw.lcd.width=1080"
            config += "\nhw.initialOrientation=Portrait"
            try config.write(to: configPath, atomically: true, encoding: .utf8)
        }
    }
}
