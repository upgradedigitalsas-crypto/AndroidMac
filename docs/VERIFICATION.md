# Verification Results

## Build

- [x] `./build.sh` produces a runnable `AndroidMac.app` (ad-hoc signed, arm64) on a
      Command Line Tools–only machine — it probes installed macOS SDKs and picks
      one the available `swiftc` can parse.
- [x] `swiftc` whole-module build of all sources: **no errors, no warnings**.
- [x] `xcodegen generate` + `xcodebuild` path exercised by `.github/workflows/ci.yml`.

## App flow

- [x] **SDK detection:** `AndroidSDKManager` checks for `sdkmanager`, `adb`, and
      `emulator` under `~/Library/Android/sdk`.
- [x] **Setup can't hang:** `installSDK()` always clears `isInstalling` (via
      `defer`), surfaces the real error, and offers **Retry**. Downloads have a
      hard timeout instead of blocking forever.
- [x] **Java:** missing JDK is reported as `brew install openjdk@17`; when present,
      `JAVA_HOME` is injected into every spawned tool.
- [x] **Latest Android:** `resolveLatestAPILevel()` installs the newest
      `arm64-v8a` Play Store image `sdkmanager` offers (fallback API 36 / Android 16).
- [x] **AVD:** created from the Play Store ARM64 image; `config.ini` gets the
      performance + `hw.keyboard=yes` settings, with keys replaced (not
      duplicated) and re-applied on every launch.
- [x] **Start emulator:** launched with `-gpu host -accel on -cores 4 -memory 4096
      -no-boot-anim`; boot polled via `adb ... getprop sys.boot_completed` for ~6 min.
- [x] **Host keyboard:** typing in the emulator window works directly; the app's
      text field also injects text/Enter over `adb`.
- [x] **Nav keys:** Back (4), Home (3), Recents (187) via `adb shell input keyevent`.
- [x] **Screenshot:** `adb shell screencap -p` + `adb pull` to `~/Desktop`.
- [x] **Install APK:** file importer + `adb install -r`.
- [x] **Stop:** `adb emu kill` (saves Quick Boot snapshot) then `Process.terminate()`.
- [x] **Persistence:** no `-wipe-data`; Play Store login and apps survive restarts.

## Known follow-ups

- Signed + notarized release (currently ad-hoc; `xattr -dr com.apple.quarantine`
  needed on first open of a downloaded build).
- App icon asset catalog (`ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon` is set but
  no `.xcassets` is committed yet).
