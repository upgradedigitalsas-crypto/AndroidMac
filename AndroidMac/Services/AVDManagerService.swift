import Foundation

class AVDManagerService {
    let sdkRoot: URL
    let avdmanager: URL
    let apiLevel: Int

    init(sdkRoot: URL, apiLevel: Int = AndroidConfig.preferredAPILevel) {
        self.sdkRoot = sdkRoot
        self.apiLevel = apiLevel
        self.avdmanager = sdkRoot.appendingPathComponent("cmdline-tools/latest/bin/avdmanager")
    }

    func listAVDs() async throws -> [String] {
        let result = try await ProcessRunner.runCommand(
            avdmanager,
            arguments: ["list", "avd", "-c"],
            environment: AndroidEnvironment.toolchain(sdkRoot: sdkRoot),
            timeout: 60)
        guard result.isSuccess else {
            throw ProcessError.executionFailed(result.exitCode, result.stdout, result.stderr)
        }
        return result.stdout
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func createDefaultAVD() async throws {
        let package = AndroidConfig.systemImage(api: apiLevel)

        let result = try await ProcessRunner.runShell(
            "echo no | \"\(avdmanager.path)\" create avd "
            + "-n \"\(AndroidConfig.avdName)\" -k \"\(package)\" "
            + "-d \"\(AndroidConfig.deviceProfile)\" --force",
            environment: AndroidEnvironment.toolchain(sdkRoot: sdkRoot),
            timeout: 120)

        guard result.isSuccess else {
            throw ProcessError.executionFailed(result.exitCode, result.stdout, result.stderr)
        }

        applyHardwareConfig(to: AndroidConfig.avdName)
    }

    /// Merge the performance / keyboard settings into an AVD's `config.ini`,
    /// replacing existing keys instead of appending duplicates (the old bug:
    /// duplicated keys made the emulator ignore the tuning).
    ///
    /// Safe to call on every launch so AVDs created by earlier versions also
    /// pick up `hw.keyboard=yes` and `hw.gpu.mode=host`.
    @discardableResult
    func applyHardwareConfig(to avdName: String) -> Bool {
        let configPath = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".android/avd/\(avdName).avd/config.ini")

        guard let existing = try? String(contentsOf: configPath, encoding: .utf8) else { return false }

        var pairs: [(String, String)] = []
        var seen = Set<String>()
        for rawLine in existing.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            guard let eq = line.firstIndex(of: "="), !line.hasPrefix("#") else {
                if !line.trimmingCharacters(in: .whitespaces).isEmpty { pairs.append((line, "")) }
                continue
            }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if AndroidConfig.avdHardwareConfig[key] != nil { continue }  // will be re-added below
            if seen.insert(key).inserted { pairs.append((key, value)) }
        }
        for (key, value) in AndroidConfig.avdHardwareConfig.sorted(by: { $0.key < $1.key }) {
            pairs.append((key, value))
        }

        let rendered = pairs
            .map { $0.1.isEmpty ? $0.0 : "\($0.0)=\($0.1)" }
            .joined(separator: "\n") + "\n"

        do {
            try rendered.write(to: configPath, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
}
