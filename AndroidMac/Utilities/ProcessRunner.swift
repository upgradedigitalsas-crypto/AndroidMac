import Foundation

enum ProcessError: Error {
    case executionFailed(Int, String, String)
    case timedOut
}

struct ProcessResult {
    let exitCode: Int
    let stdout: String
    let stderr: String
}

class ProcessRunner {
    static func runCommand(_ executableURL: URL, arguments: [String], environment: [String: String]? = nil) async throws -> ProcessResult {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            
            if let env = environment {
                var currentEnv = ProcessInfo.processInfo.environment
                for (key, value) in env {
                    currentEnv[key] = value
                }
                process.environment = currentEnv
            }
            
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            
            process.terminationHandler = { process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                
                let stdoutString = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderrString = String(data: stderrData, encoding: .utf8) ?? ""
                
                let result = ProcessResult(
                    exitCode: Int(process.terminationStatus),
                    stdout: stdoutString.trimmingCharacters(in: .whitespacesAndNewlines),
                    stderr: stderrString.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                
                continuation.resume(returning: result)
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
