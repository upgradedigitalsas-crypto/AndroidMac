# Technical Decisions

## 1. Android Emulator on Apple Silicon
- **Emulation vs Virtualization:** Apple Silicon requires ARM64 system images. x86 emulation is severely degraded or impossible. We use `arm64-v8a` images natively supported by the Google Android Emulator for Apple Silicon.
- **Emulator Control:** We do not attempt to "embed" the emulator window into a SwiftUI `NSViewRepresentable` because Google does not provide a supported public API for X11/Wayland embedding on macOS. Hacks like `CGSSetWindowOwner` or reparenting are unstable. Instead, the app acts as a launcher and controller, opening the emulator as a standard external window, but tightly managing its lifecycle and position.
- **Startup Detection:** We rely on `adb shell getprop sys.boot_completed` returning `1` to verify the emulator is fully booted, rather than just checking if the process exists.

## 2. Google Play
- **System Image:** We use the `system-images;android-34;google_apis_playstore;arm64-v8a` (or latest available) to provide Google Play support natively.
- **Login:** Login is handled directly inside the Android Emulator by the user to avoid credential interception and adhere to Google's authentication mechanisms.

## 3. macOS Application Architecture
- **Framework:** SwiftUI with MVVM.
- **Concurrency:** Swift `async/await` and `Task` for managing external processes to avoid blocking the MainActor.
- **Process Management:** We use a centralized `ProcessRunner` based on `Foundation.Process` to execute `sdkmanager`, `avdmanager`, `emulator`, and `adb` safely.
- **Build System:** We generate an Xcode project using `XcodeGen` to satisfy the project requirement and provide a standard developer experience, while also offering a custom `build.sh` for environments where Swift Package Manager or `xcodebuild` is restricted.
