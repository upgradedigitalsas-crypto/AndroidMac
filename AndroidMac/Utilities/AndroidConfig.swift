import Foundation

/// Single source of truth for the Android target and emulator tuning.
///
/// Bump `preferredAPILevel` when a newer stable Android platform ships.
/// At install time `AndroidSDKManager` also asks `sdkmanager` for the newest
/// `arm64-v8a` Play Store image actually available and uses that if it is higher,
/// so the app keeps installing "the latest Android" without a code change.
enum AndroidConfig {

    // MARK: Android version

    /// API 36 == Android 16. Fallback when dynamic resolution is unavailable.
    static let preferredAPILevel = 36
    static let minimumAPILevel = 34

    static let abi = "arm64-v8a"
    static let systemImageTag = "google_apis_playstore"

    static func systemImage(api: Int) -> String {
        "system-images;android-\(api);\(systemImageTag);\(abi)"
    }
    static func platform(api: Int) -> String {
        "platforms;android-\(api)"
    }

    // MARK: AVD

    static let avdName = "Antigravity_Phone"
    /// `pixel` is guaranteed to exist in every `avdmanager` device list.
    static let deviceProfile = "pixel"

    // MARK: Performance tuning (Apple Silicon)

    /// Physical cores to hand to the guest. Kept at 4: enough for smooth UI,
    /// low enough to leave the host responsive on an 8-core M3.
    static let cpuCores = 4
    static let ramMB = 4096
    static let vmHeapMB = 512
    static let dataPartitionMB = 8192
    static let lcdDensity = 420
    static let lcdWidth = 1080
    static let lcdHeight = 2400

    /// GPU rendering backend, used both for the `-gpu` flag and `hw.gpu.mode`
    /// (kept in sync so they can't disagree).
    ///
    /// `auto` = the emulator picks the fastest backend it can actually drive on
    /// this host (Metal/host on Apple Silicon) and falls back on its own instead
    /// of rendering a blank window. Change to `swiftshader_indirect` if you still
    /// get a blank/white screen (pure software, slower but always renders), or to
    /// `host` to force the GPU path.
    static let gpuMode = "auto"

    /// Written verbatim into the AVD's `config.ini`. Existing keys are replaced,
    /// not duplicated. `hw.keyboard=yes` is what lets you type into the emulator
    /// window straight from the Mac keyboard instead of the on-screen keyboard.
    static var avdHardwareConfig: [String: String] {
        [
            "hw.gpu.enabled": "yes",
            "hw.gpu.mode": gpuMode,
            "hw.cpu.ncore": "\(cpuCores)",
            "hw.ramSize": "\(ramMB)",
            "vm.heapSize": "\(vmHeapMB)",
            "disk.dataPartition.size": "\(dataPartitionMB)M",
            "hw.keyboard": "yes",
            "hw.keyboard.lid": "yes",
            "hw.mainKeys": "no",
            "hw.lcd.density": "\(lcdDensity)",
            "hw.lcd.width": "\(lcdWidth)",
            "hw.lcd.height": "\(lcdHeight)",
            "hw.initialOrientation": "Portrait",
            "showDeviceFrame": "no",
        ]
    }

    /// Emulator CLI flags. `-gpu` + `-cores` are the main speed levers on Apple
    /// Silicon; snapshots are left at their default so Quick Boot and the user's
    /// Play Store login persist between sessions.
    ///
    /// The boot animation is deliberately kept (no `-no-boot-anim`) — it is the
    /// only on-screen signal that a cold boot is progressing rather than hung,
    /// and it costs ~2 s.
    ///
    /// `-dns-server` is pinned to public resolvers: the emulator otherwise
    /// inherits the host's DNS, and split-tunnel VPNs / corporate resolvers are
    /// the usual reason Google sign-in fails with "couldn't communicate with
    /// Google servers".
    static func emulatorLaunchArgs(coldBoot: Bool = false) -> [String] {
        var args = [
            "-gpu", gpuMode,
            "-accel", "on",
            "-cores", "\(cpuCores)",
            "-memory", "\(ramMB)",
            "-netdelay", "none",
            "-netspeed", "full",
            "-dns-server", "8.8.8.8,8.8.4.4",
        ]
        if coldBoot {
            // Ignore any saved snapshot for this run — the fix for a window that
            // opens blank/white because a broken GPU state got snapshotted.
            args += ["-no-snapshot-load"]
        }
        return args
    }
}
