# Technical Decisions

## 1. Android Emulator on Apple Silicon
- **Emulation vs Virtualization:** Apple Silicon requires ARM64 system images. x86 emulation is severely degraded or impossible. We use `arm64-v8a` images natively supported by the Google Android Emulator for Apple Silicon.
- **Emulator Control:** We do not attempt to "embed" the emulator window into a SwiftUI `NSViewRepresentable` because Google does not provide a supported public API for X11/Wayland embedding on macOS. Hacks like `CGSSetWindowOwner` or reparenting are unstable. Instead, the app acts as a launcher and controller, opening the emulator as a standard external window, but tightly managing its lifecycle.
- **Startup Detection:** We rely on `adb shell getprop sys.boot_completed` returning `1` to verify the emulator is fully booted, rather than just checking if the process exists. The boot poll runs for ~6 minutes and, on timeout, leaves the still-running emulator alone instead of forcing a restart.

## 2. Android version — "always latest"
- **Dynamic resolution:** `AndroidSDKManager.resolveLatestAPILevel()` parses `sdkmanager --list` for the highest `system-images;android-N;google_apis_playstore;arm64-v8a` and installs that. `AndroidConfig.preferredAPILevel` (currently 36 / Android 16) is only the offline fallback / floor.
- **System Image:** `google_apis_playstore` so Google Play is available natively.
- **Login:** performed by the user inside the Android emulator; the app never handles Google credentials.

## 3. Performance tuning (Apple Silicon)
- All tuning lives in `AndroidConfig`. The emulator is launched with `-gpu auto -accel on -cores 4 -memory 4096`.
- `gpuMode` (`auto` by default) is used for both the `-gpu` flag and `hw.gpu.mode` so they can't disagree. `auto` lets the emulator pick Metal/host and fall back itself instead of rendering a blank window; `swiftshader_indirect` is the software fallback for machines where the GPU path still comes up blank.
- The boot animation is kept — it's the only signal that a cold boot is progressing vs hung.
- `start(coldBoot:)` adds `-no-snapshot-load` for one run; the **Cold boot** button uses it to recover from a blank window caused by a snapshotted bad GPU state.
- The AVD `config.ini` gets `hw.gpu.mode=auto`, `hw.cpu.ncore=4`, `hw.ramSize=4096`, `vm.heapSize=512`, `disk.dataPartition.size=8192M`.
- `AVDManagerService.applyHardwareConfig` **replaces** keys instead of appending, fixing an earlier bug where duplicate keys in `config.ini` made the emulator ignore the tuning. It is re-applied on every launch so old AVDs are upgraded in place.
- Snapshots are left at their default (Quick Boot) so warm starts are fast and the Play Store login persists.

## 4. Host keyboard input
- The AVD is created with `hw.keyboard=yes` / `hw.keyboard.lid=yes`, which is what makes the emulator window accept the Mac's physical keyboard instead of showing the on-screen keyboard.
- `ADBService.inputText` provides an app-side fallback (`adb shell input text`, spaces encoded as `%s`, newlines sent as `KEYCODE_ENTER`) for typing when the emulator window is not focused.

## 5. Process execution
- `ProcessRunner` wraps `Foundation.Process` with `async/await`, concurrent stdout/stderr draining (no pipe-buffer deadlocks), and an optional timeout so a hung child (network stall during a 1.5 GB image download) cannot freeze the app forever.
- `AndroidEnvironment` resolves `JAVA_HOME` via `/usr/libexec/java_home` and sets `ANDROID_SDK_ROOT` / `PATH` for every spawned tool, so the app works when launched from Finder with a minimal environment.
- SDK setup (`installSDK`) is wrapped so `isInstalling` is always cleared and any failure is surfaced in the UI with a Retry button — it can no longer get stuck on an infinite spinner.

## 6. macOS Application Architecture
- **Framework:** SwiftUI with MVVM; `@MainActor` on the observable services/view-models.
- **Concurrency:** Swift `async/await` and `Task`; child processes are managed off the main actor.
- **Build System:** `XcodeGen` (`project.yml`) is the source of truth for the Xcode project; a committed `.xcodeproj` and a `swiftc`-based `build.sh` cover environments without `xcodegen` or a full Xcode.
