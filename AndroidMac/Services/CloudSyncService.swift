import Foundation

/// Connection details for the AndroidMac Cloud companion (see the
/// `androidmac-cloud` repo). Stored outside the app bundle so it survives
/// rebuilds; never committed to git.
struct CloudConfig: Codable {
    var baseURL: String
    var deviceToken: String
}

enum CloudConfigStore {
    static let fileURL: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AndroidMac", isDirectory: true)
        return dir.appendingPathComponent("cloud.json")
    }()

    static func load() -> CloudConfig? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(CloudConfig.self, from: data)
    }

    static func save(_ config: CloudConfig) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

private struct CloudCommand: Codable {
    let id: String
    let type: String
    let payload: String?
    let queuedAt: String
}

private struct CloudCommandResponse: Codable {
    let command: CloudCommand?
}

/// Pushes emulator state (screenshot, installed apps, detected accounts) to
/// the AndroidMac Cloud backend and polls it for queued remote actions —
/// the Mac only ever makes outbound HTTPS calls, nothing is exposed to the
/// internet locally.
@MainActor
final class CloudSyncService: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published var isSyncing = false
    @Published var lastSyncAt: Date?
    @Published var lastError: String?

    /// Injected by ContentView once the AVD/emulator are known.
    weak var avdManager: AVDManagerViewModel?

    private var config: CloudConfig?
    private var pollTask: Task<Void, Never>?
    private let pollInterval: UInt64 = 12_000_000_000 // 12s

    init() {
        let loaded = CloudConfigStore.load()
        config = loaded
        isEnabled = loaded != nil
    }

    var baseURLForDisplay: String { config?.baseURL ?? "" }
    var hasDeviceToken: Bool { !(config?.deviceToken.isEmpty ?? true) }

    func configure(baseURL: String, deviceToken: String) {
        var cleaned = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasSuffix("/") { cleaned.removeLast() }
        let cfg = CloudConfig(baseURL: cleaned, deviceToken: deviceToken.trimmingCharacters(in: .whitespacesAndNewlines))
        CloudConfigStore.save(cfg)
        config = cfg
        isEnabled = true
        lastError = nil
        startPolling()
    }

    func disable() {
        isEnabled = false
        pollTask?.cancel()
        CloudConfigStore.clear()
        config = nil
    }

    func startPolling() {
        guard isEnabled, config != nil else { return }
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                guard let interval = self?.pollInterval else { return }
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    func stopPolling() { pollTask?.cancel() }

    // MARK: - Sync (Mac -> Cloud)

    func syncNow() async {
        guard let config else { return }
        isSyncing = true
        defer { isSyncing = false }

        let emulator = avdManager?.emulatorService
        let running = emulator?.isRunning == true

        var screenshotData: Data?
        var apps: [[String: String]] = []
        var accounts: [String] = []

        if running, let adb = emulator?.adbService {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("androidmac-cloud-\(UUID().uuidString).png")
            if (try? await adb.takeScreenshot(saveTo: tmp.path)) != nil {
                screenshotData = try? Data(contentsOf: tmp)
            }
            try? FileManager.default.removeItem(at: tmp)
            apps = await adb.listThirdPartyPackages().map { ["packageName": $0] }
            accounts = await adb.listAccountNames()
        }

        guard let url = URL(string: "\(config.baseURL)/api/sync") else {
            lastError = "Invalid Cloud URL."
            return
        }

        var form = MultipartFormBuilder()
        form.addField("avdName", avdManager?.selectedAVD ?? "")
        if let json = jsonString(apps) { form.addField("apps", json) }
        if let json = jsonString(accounts) { form.addField("accounts", json) }
        if let screenshotData {
            form.addFile("screenshot", filename: "screenshot.png", mimeType: "image/png", data: screenshotData)
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.deviceToken)", forHTTPHeaderField: "Authorization")
        request.setValue(form.contentTypeHeader, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finish()

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                lastError = "Sync failed (server rejected the request)."
                return
            }
            lastSyncAt = Date()
            lastError = nil
        } catch {
            lastError = "Sync failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Commands (Cloud -> Mac)

    private func pollOnce() async {
        guard let config, let url = URL(string: "\(config.baseURL)/api/command") else { return }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("Bearer \(config.deviceToken)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(CloudCommandResponse.self, from: data),
              let command = decoded.command
        else { return }

        let (ok, message) = await execute(command)
        await report(command: command, ok: ok, message: message)
        await syncNow()   // push fresh state/screenshot after acting on a command
    }

    private func execute(_ command: CloudCommand) async -> (ok: Bool, message: String) {
        guard let avdManager else { return (false, "No AVD manager available.") }
        let emulator = avdManager.emulatorService

        switch command.type {
        case "start":
            guard let avd = avdManager.selectedAVD else { return (false, "No AVD selected.") }
            emulator?.start(avdName: avd)
            return (true, "Starting.")
        case "stop":
            emulator?.stop()
            return (true, "Stopping.")
        case "cold_boot":
            guard let avd = avdManager.selectedAVD else { return (false, "No AVD selected.") }
            emulator?.start(avdName: avd, coldBoot: true)
            return (true, "Cold booting.")
        case "key_back":
            try? await emulator?.adbService.sendKeyEvent(4)
            return (true, "Sent Back.")
        case "key_home":
            try? await emulator?.adbService.sendKeyEvent(3)
            return (true, "Sent Home.")
        case "key_recents":
            try? await emulator?.adbService.sendKeyEvent(187)
            return (true, "Sent Recents.")
        case "type_text":
            guard let text = command.payload, !text.isEmpty else { return (false, "No text provided.") }
            try? await emulator?.adbService.inputText(text)
            return (true, "Typed text.")
        case "screenshot":
            return (true, "Screenshot refreshed.")   // capture happens in the syncNow() that follows
        case "install_apk_url":
            guard let urlString = command.payload, let apkURL = URL(string: urlString) else {
                return (false, "Invalid APK URL.")
            }
            do {
                let (tmp, _) = try await URLSession.shared.download(from: apkURL)
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("androidmac-cloud-\(UUID().uuidString).apk")
                try FileManager.default.moveItem(at: tmp, to: dest)
                defer { try? FileManager.default.removeItem(at: dest) }
                guard let result = try? await emulator?.adbService.installAPK(url: dest) else {
                    return (false, "Install failed to run.")
                }
                return (result.isSuccess, result.isSuccess ? "APK installed." : result.stderr)
            } catch {
                return (false, "Download failed: \(error.localizedDescription)")
            }
        default:
            return (false, "Unknown command type.")
        }
    }

    private func report(command: CloudCommand, ok: Bool, message: String) async {
        guard let config, let url = URL(string: "\(config.baseURL)/api/command") else { return }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(config.deviceToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "command": [
                "id": command.id, "type": command.type,
                "payload": command.payload as Any, "queuedAt": command.queuedAt,
            ],
            "ok": ok,
            "message": message,
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: request)
    }

    private func jsonString(_ value: Any) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Hand-rolled `multipart/form-data` body — Foundation has no built-in helper.
private struct MultipartFormBuilder {
    let boundary = "AndroidMacCloud-\(UUID().uuidString)"
    private var body = Data()

    var contentTypeHeader: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(_ name: String, _ value: String) {
        body.append("--\(boundary)\r\n".utf8Data)
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8Data)
        body.append(value.utf8Data)
        body.append("\r\n".utf8Data)
    }

    mutating func addFile(_ name: String, filename: String, mimeType: String, data: Data) {
        body.append("--\(boundary)\r\n".utf8Data)
        body.append(
            "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8Data)
        body.append("Content-Type: \(mimeType)\r\n\r\n".utf8Data)
        body.append(data)
        body.append("\r\n".utf8Data)
    }

    func finish() -> Data {
        var result = body
        result.append("--\(boundary)--\r\n".utf8Data)
        return result
    }
}

private extension String {
    var utf8Data: Data { data(using: .utf8) ?? Data() }
}
