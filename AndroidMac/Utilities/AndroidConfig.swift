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

    /// Written verbatim into the AVD's `config.ini`. Existing keys are replaced,
    /// not duplicated. `hw.keyboard=yes` is what lets you type into the emulator
    /// window straight from the Mac keyboard instead of the on-screen keyboard.
    static var avdHardwareConfig: [String: String] {
        [
            "hw.gpu.enabled": "yes",
            "hw.gpu.mode": "host",
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

    /// Emulator CLI flags. `-gpu host` + `-cores` are the main speed levers on
    /// Apple Silicon; snapshots are left at their default so Quick Boot and the
    /// user's Play Store login persist between sessions.
    static var emulatorLaunchArgs: [String] {
        [
            "-gpu", "host",
            "-accel", "on",
            "-cores", "\(cpuCores)",
            "-memory", "\(ramMB)",
            "-no-boot-anim",
            "-netdelay", "none",
            "-netspeed", "full",
        ]
    }
}
