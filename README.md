# AndroidMac

A native macOS application built with SwiftUI that acts as a manager and launcher
for the official Android Emulator on Apple Silicon (M-series / ARM64).

## Requirements

- **macOS:** 14.0+ (Apple Silicon)
- **Java:** JDK 17+ — required by the Android command-line tools:
  ```bash
  brew install openjdk@17
  ```
  The app auto-detects it via `/usr/libexec/java_home` and injects `JAVA_HOME`
  into the tools it spawns, so no manual shell configuration is needed.

## Features

- Detects or automatically downloads the Android SDK (command-line tools).
- **Always installs the latest Android.** At setup the app asks `sdkmanager` for
  the newest `arm64-v8a` Google Play system image available and installs that
  (falls back to API 36 / Android 16). Bump `AndroidConfig.preferredAPILevel`
  only if you want to pin a specific version.
- Creates and manages an AVD tuned for performance on Apple Silicon.
- Boots the emulator and verifies `sys.boot_completed` via `adb`.
- **Type from your Mac keyboard.** The AVD is created with `hw.keyboard=yes`, so
  the emulator window accepts your physical keyboard directly. The app also has
  an in-window text field that injects text/Enter over `adb` even when the
  emulator window isn't focused.
- Native SwiftUI controls for Back / Home / Recents key events.
- Capture screenshots straight to your Desktop.
- Install APKs via file selection.
- Play Store login and app data persist across sessions (Quick Boot snapshots).

## Performance tuning

The emulator is launched and the AVD configured for speed on M-series hardware
(see `AndroidMac/Utilities/AndroidConfig.swift`):

| Setting | Value | Why |
|---|---|---|
| `-gpu host` / `hw.gpu.mode=host` | Metal-backed rendering | biggest single speed-up vs software GL |
| `-cores` / `hw.cpu.ncore` | 4 | smooth guest UI, host stays responsive |
| `-memory` / `hw.ramSize` | 4096 MB | avoids guest swapping |
| `vm.heapSize` | 512 MB | fewer ART GC pauses |
| `-no-boot-anim` | on | shaves a few seconds off boot |
| Quick Boot snapshot | default (kept) | warm starts instead of cold boot |

`applyHardwareConfig` re-applies these to existing AVDs on every launch, so a
device created by an older build picks up the tuning without being recreated.

## Building

### With Xcode (recommended)

```bash
brew install xcodegen
xcodegen generate
open AndroidMac.xcodeproj
```

Select the `AndroidMac` scheme and your Mac as the destination, then Build & Run.

### From the terminal (no full Xcode required)

```bash
chmod +x build.sh
./build.sh          # uses xcodebuild if a full Xcode is selected,
open AndroidMac.app # otherwise compiles directly with swiftc
```

`build.sh` picks a macOS SDK that the available `swiftc` can actually parse, so it
works on a Command Line Tools–only machine.

## Releasing / deploying

Distribution is automated by GitHub Actions:

- **CI** (`.github/workflows/ci.yml`) builds the app on every push and PR.
- **Release** (`.github/workflows/release.yml`) runs on a `v*` tag (or manual
  dispatch), builds a Release `.app`, packages a `.zip` and a `.dmg`, writes
  `SHA256SUMS.txt`, and publishes a GitHub Release with those assets.

```bash
git tag v1.1.0
git push origin v1.1.0
```

For a signed & notarized build, add `DEVELOPMENT_TEAM` / a Developer ID identity
and an `xcrun notarytool` step; the ad-hoc signature in the workflow is enough
for local use (`xattr -dr com.apple.quarantine AndroidMac.app` on first open).

## Troubleshooting

- **Stuck on "Android environment incomplete"** — the setup step now always
  clears its spinner and shows the underlying error with a **Retry** button.
  The most common cause is a missing JDK: `brew install openjdk@17`.
- **Emulator is slow** — confirm `hw.gpu.mode=host` in
  `~/.android/avd/Antigravity_Phone.avd/config.ini`; if you changed it, delete
  the AVD and let the app recreate it. Close other heavy GPU apps.
- **Emulator doesn't start** — check `~/Library/Android/sdk/emulator/emulator
  -avd Antigravity_Phone -verbose` output in a terminal for the real error.
- **Boot takes a long time on first run** — expected for a cold boot; subsequent
  starts use the Quick Boot snapshot.
- **Can't sign in to Google / "device not certified"** — see
  [`docs/GOOGLE_SIGN_IN.md`](docs/GOOGLE_SIGN_IN.md). The emulator now forces
  public DNS (`-dns-server 8.8.8.8,8.8.4.4`), which fixes most cases; the app's
  **Register device** / **Reset & reboot** buttons cover the rest.
