import Foundation

enum ProcessError: Error {
    case executionFailed(Int, String, String)
    case timedOut
}

struct ProcessResult {
    let exitCode: Int
    let stdout: String
    let stderr: String

    var isSuccess: Bool { exitCode == 0 }
}

class ProcessRunner {

    /// Run an executable and await its full output.
    ///
    /// - Parameters:
    ///   - environment: extra variables merged on top of the current environment.
    ///   - timeout: if the process runs longer than this it is terminated and
    ///     `ProcessError.timedOut` is thrown. `nil` waits forever.
    static func runCommand(_ executableURL: URL,
                           arguments: [String],
                           environment: [String: String]? = nil,
                           timeout: TimeInterval? = nil) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment ?? [:] { env[key] = value }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Drain pipes concurrently so a chatty child (sdkmanager downloads) can't
        // deadlock by filling the 64 KB pipe buffer while we wait on exit.
        let stdoutAcc = DataAccumulator(stdoutPipe.fileHandleForReading)
        let stderrAcc = DataAccumulator(stderrPipe.fileHandleForReading)

        try process.run()

        let exited = Task.detached(priority: .utility) {
            process.waitUntilExit()
        }

        if let timeout {
            let timedOut = await withTaskGroup(of: Bool.self) { group -> Bool in
                group.addTask { await exited.value; return false }
                group.addTask {
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    return true
                }
                let first = await group.next() ?? false
                group.cancelAll()
                return first
            }
            if timedOut {
                process.terminate()
                await exited.value
                throw ProcessError.timedOut
            }
        } else {
            await exited.value
        }

        stdoutAcc.finish()
        stderrAcc.finish()

        return ProcessResult(
            exitCode: Int(process.terminationStatus),
            stdout: stdoutAcc.string.trimmingCharacters(in: .whitespacesAndNewlines),
            stderr: stderrAcc.string.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Run a `/bin/sh -c` snippet with the Android toolchain environment applied.
    static func runShell(_ script: String,
                         environment: [String: String]? = nil,
                         timeout: TimeInterval? = nil) async throws -> ProcessResult {
        var env = AndroidEnvironment.toolchain()
        for (key, value) in environment ?? [:] { env[key] = value }
        return try await runCommand(URL(fileURLWithPath: "/bin/sh"),
                                    arguments: ["-c", script],
                                    environment: env,
                                    timeout: timeout)
    }
}

/// Reads a file handle to EOF on a background queue, avoiding pipe-buffer deadlocks.
private final class DataAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let handle: FileHandle

    init(_ handle: FileHandle) {
        self.handle = handle
        handle.readabilityHandler = { [weak self] h in
            let chunk = h.availableData
            guard let self, !chunk.isEmpty else { h.readabilityHandler = nil; return }
            self.lock.lock(); self.data.append(chunk); self.lock.unlock()
        }
    }

    /// Pull anything buffered after the process has exited, then stop reading.
    func finish() {
        handle.readabilityHandler = nil
        let rest = handle.availableData
        if !rest.isEmpty { lock.lock(); data.append(rest); lock.unlock() }
    }

    var string: String {
        lock.lock(); defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Resolves `JAVA_HOME` / `ANDROID_*` so child tools (`sdkmanager`, `emulator`,
/// `adb`) work even when the app is launched from Finder with a bare `PATH`.
enum AndroidEnvironment {

    static let sdkRoot: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Android/sdk")

    /// Path returned by `/usr/libexec/java_home`, preferring JDK 17+. `nil` when
    /// no JDK is installed — the caller surfaces an actionable message.
    static func javaHome() -> String? {
        for args in [["-v", "17+"], ["-v", "17"], []] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/libexec/java_home")
            p.arguments = args
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = Pipe()
            do {
                try p.run(); p.waitUntilExit()
                if p.terminationStatus == 0 {
                    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                                     encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !out.isEmpty { return out }
                }
            } catch { continue }
        }
        return nil
    }

    static func toolchain(sdkRoot: URL = AndroidEnvironment.sdkRoot) -> [String: String] {
        var env: [String: String] = [
            "ANDROID_SDK_ROOT": sdkRoot.path,
            "ANDROID_HOME": sdkRoot.path,
        ]
        if let java = javaHome() {
            env["JAVA_HOME"] = java
            let extraPath = [
                "\(java)/bin",
                "\(sdkRoot.path)/cmdline-tools/latest/bin",
                "\(sdkRoot.path)/platform-tools",
                "\(sdkRoot.path)/emulator",
            ].joined(separator: ":")
            let current = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
            env["PATH"] = "\(extraPath):\(current)"
        }
        return env
    }
}
