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
    /// pick up `hw.keyboard=yes` and `hw.gpu.mode=host`. Keys this doesn't own
    /// (e.g. `hw.camera.*`, set separately via `setCamera`) are left untouched.
    @discardableResult
    func applyHardwareConfig(to avdName: String) -> Bool {
        mergeConfigKeys(for: avdName, overrides: AndroidConfig.avdHardwareConfig)
    }

    /// Reads the current `hw.camera.back` / `hw.camera.front` values, e.g. to
    /// preselect the right option in a camera picker. Defaults to `"emulated"`
    /// (the built-in fake scene) when the key isn't present yet.
    func currentCameraSelection(for avdName: String) -> (back: String, front: String) {
        let values = readConfigKeys(for: avdName, keys: ["hw.camera.back", "hw.camera.front"])
        return (values["hw.camera.back"] ?? "emulated", values["hw.camera.front"] ?? "emulated")
    }

    /// Point the AVD's back/front camera at a real webcam (from
    /// `EmulatorService.listWebcams()`, e.g. `"webcam0"` — on macOS this
    /// includes an iPhone connected via Continuity Camera), `"emulated"` for
    /// the default virtual scene, or `"none"` to disable. Takes effect on the
    /// next emulator launch.
    @discardableResult
    func setCamera(for avdName: String, back: String, front: String) -> Bool {
        mergeConfigKeys(for: avdName, overrides: ["hw.camera.back": back, "hw.camera.front": front])
    }

    // MARK: - config.ini helpers

    private func configPath(for avdName: String) -> URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".android/avd/\(avdName).avd/config.ini")
    }

    private func readConfigKeys(for avdName: String, keys: Set<String>) -> [String: String] {
        guard let existing = try? String(contentsOf: configPath(for: avdName), encoding: .utf8) else {
            return [:]
        }
        var found: [String: String] = [:]
        for line in existing.split(separator: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            guard keys.contains(key) else { continue }
            found[key] = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
        }
        return found
    }

    /// Replaces (never duplicates) the given keys in `config.ini`; every other
    /// existing line — including keys owned by a different caller — is kept as-is.
    @discardableResult
    private func mergeConfigKeys(for avdName: String, overrides: [String: String]) -> Bool {
        let path = configPath(for: avdName)
        guard let existing = try? String(contentsOf: path, encoding: .utf8) else { return false }

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
            if overrides[key] != nil { continue }  // will be re-added below
            if seen.insert(key).inserted { pairs.append((key, value)) }
        }
        for (key, value) in overrides.sorted(by: { $0.key < $1.key }) {
            pairs.append((key, value))
        }

        let rendered = pairs
            .map { $0.1.isEmpty ? $0.0 : "\($0.0)=\($0.1)" }
            .joined(separator: "\n") + "\n"

        do {
            try rendered.write(to: path, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
}
