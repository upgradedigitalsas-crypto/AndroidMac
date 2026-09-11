import SwiftUI

/// Connects this Mac to an `androidmac-cloud` deployment: pushes emulator
/// state (screenshot, apps, accounts) there and polls it for queued remote
/// actions. See the androidmac-cloud repo's README for the one-time deploy
/// + secrets setup that has to happen before this screen has anything to
/// point at.
struct CloudSettingsView: View {
    @ObservedObject var cloudSync: CloudSyncService
    @Environment(\.dismiss) private var dismiss

    @State private var baseURL: String = ""
    @State private var deviceToken: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("AndroidMac Cloud").font(.title3.bold())
                Spacer()
                Button("Done") { dismiss() }
            }

            Text("Mirrors this emulator's screenshot, installed apps, and detected "
               + "accounts to your androidmac-cloud deployment, and lets the web/PWA "
               + "dashboard queue remote actions. Outbound-only — nothing is exposed "
               + "on this Mac.")
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Cloud URL").font(.caption).foregroundColor(.secondary)
                TextField("https://androidmac-cloud.vercel.app", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Device token").font(.caption).foregroundColor(.secondary)
                SecureField("DEVICE_TOKEN from Vercel env vars", text: $deviceToken)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Save & Enable") {
                    cloudSync.configure(baseURL: baseURL, deviceToken: deviceToken)
                }
                .buttonStyle(.borderedProminent)
                .disabled(baseURL.isEmpty || deviceToken.isEmpty)

                if cloudSync.isEnabled {
                    Button("Sync now") { Task { await cloudSync.syncNow() } }
                        .disabled(cloudSync.isSyncing)
                    Button("Disable", role: .destructive) { cloudSync.disable() }
                }
            }

            if cloudSync.isEnabled {
                Divider()
                statusRow
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 380, height: cloudSync.isEnabled ? 340 : 280)
        .onAppear {
            baseURL = cloudSync.baseURLForDisplay
        }
    }

    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(cloudSync.isEnabled ? "Enabled" : "Disabled", systemImage: "icloud.fill")
                .font(.caption)
                .foregroundColor(cloudSync.isEnabled ? .green : .secondary)
            if cloudSync.isSyncing {
                Text("Syncing…").font(.caption2).foregroundColor(.secondary)
            } else if let last = cloudSync.lastSyncAt {
                Text("Last sync: \(last.formatted())").font(.caption2).foregroundColor(.secondary)
            }
            if let error = cloudSync.lastError {
                Text(error).font(.caption2).foregroundColor(.red).textSelection(.enabled)
            }
        }
    }
}
