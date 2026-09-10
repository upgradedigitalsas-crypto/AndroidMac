# AndroidMac

A native macOS application built with SwiftUI that acts as a manager and launcher for the official Android Emulator on Apple Silicon (M3/ARM64).

## Requirements
- **macOS:** 14.0+ (Apple Silicon recommended)
- **Java:** JDK 17+ (Required by Android command-line tools. e.g., `brew install openjdk@17`)

## Features
- Detects or automatically downloads the Android SDK (command line tools).
- Installs the required ARM64 Google Play System Image.
- Creates and manages AVDs (Android Virtual Devices).
- Boots the emulator, verifying `sys.boot_completed` via `adb`.
- Native SwiftUI interface to trigger Android key events (Back, Home, Recents).
- Capture screenshots directly to your Desktop.
- Install APKs via file selection.
- Preserves app data naturally across sessions.

## Installation & Building

### If you have a working Swift Package Manager / Xcode:
1. Open `AndroidMac.xcodeproj`.
2. Select the `AndroidMac` scheme and your Mac as the destination.
3. Click Build and Run.

### If you want to build via Terminal:
A custom build script is provided to compile directly using `swiftc`:
```bash
chmod +x build.sh
./build.sh
open AndroidMac.app
```

## Troubleshooting
- **Unable to locate a Java Runtime**: The app will fail to download the SDK packages if Java is not installed. Install Java via Homebrew (`brew install java`) or from [java.com](https://java.com).
- **Emulator doesn't start**: Check the logs in the console. Ensure your AVD has enough RAM allocated (`AndroidMac/Services/AVDManagerService.swift` sets 4096MB by default).

## Technical Architecture
Read the decisions that shaped the app in [docs/TECHNICAL_DECISIONS.md](docs/TECHNICAL_DECISIONS.md).
