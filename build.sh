#!/bin/bash
# Build AndroidMac.app without depending on a full Xcode install.
# If a real Xcode IS selected we use xcodebuild; otherwise we compile the
# SwiftUI sources directly with swiftc against a compatible macOS SDK.
set -euo pipefail

APP_NAME="AndroidMac"
APP_DIR="${APP_NAME}.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RESOURCES_DIR="${APP_DIR}/Contents/Resources"
DEPLOY_TARGET="14.0"

SOURCES=$(find AndroidMac -name '*.swift' | sort)
if [ -z "${SOURCES}" ]; then
  echo "❌ No Swift sources found under AndroidMac/"; exit 1
fi

# ---------------------------------------------------------------------------
# Path 1: full Xcode available -> let xcodebuild do it properly.
# ---------------------------------------------------------------------------
XCODE_PATH="$(xcode-select -p 2>/dev/null || true)"
if [[ "${XCODE_PATH}" == *".app/"* ]] && command -v xcodebuild >/dev/null 2>&1; then
  echo "🛠  Building with xcodebuild (${XCODE_PATH})…"
  if command -v xcodegen >/dev/null 2>&1; then
    xcodegen generate
  fi
  xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "${APP_NAME}" \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath .build build
  BUILT=$(find .build -name "${APP_NAME}.app" -type d | head -n1)
  rm -rf "${APP_DIR}"
  cp -R "${BUILT}" "${APP_DIR}"
  echo "✅ Build complete: ${APP_DIR}"
  exit 0
fi

# ---------------------------------------------------------------------------
# Path 2: Command Line Tools only -> swiftc against a compatible SDK.
# ---------------------------------------------------------------------------
echo "🧹 Cleaning…"
rm -rf "${APP_DIR}" .module-cache
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

pick_sdk() {
  # Try the default SDK first, then fall back to the newest installed SDK that
  # the current swiftc can actually parse (newer SDKs need a newer toolchain).
  local candidates=()
  local def
  def="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
  [ -n "${def}" ] && candidates+=("${def}")
  local clt="/Library/Developer/CommandLineTools/SDKs"
  if [ -d "${clt}" ]; then
    while IFS= read -r sdk; do candidates+=("${sdk}"); done \
      < <(ls -d "${clt}"/MacOSX*.sdk 2>/dev/null | sort -Vr)
  fi
  printf 'import Foundation\nlet _ = ProcessInfo.processInfo\n' > /tmp/.androidmac_probe.swift
  for sdk in "${candidates[@]}"; do
    [ -d "${sdk}" ] || continue
    if swiftc -sdk "${sdk}" -target "arm64-apple-macosx${DEPLOY_TARGET}" \
         -typecheck /tmp/.androidmac_probe.swift >/dev/null 2>&1; then
      echo "${sdk}"; return 0
    fi
  done
  return 1
}

SDK="$(pick_sdk)" || { echo "❌ No usable macOS SDK found for this swiftc."; exit 1; }
echo "🔨 Compiling with swiftc → SDK: ${SDK}"

swiftc \
  -O -whole-module-optimization \
  -sdk "${SDK}" \
  -target "arm64-apple-macosx${DEPLOY_TARGET}" \
  -module-cache-path ./.module-cache \
  -o "${MACOS_DIR}/${APP_NAME}" \
  ${SOURCES}

echo "📝 Writing Info.plist…"
cat > "${APP_DIR}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>com.antigravity.${APP_NAME}</string>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleVersion</key><string>1.1</string>
    <key>CFBundleShortVersionString</key><string>1.1</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>${DEPLOY_TARGET}</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Antigravity</string>
</dict>
</plist>
EOF

echo "🖋  Codesigning (ad-hoc)…"
codesign --force --deep -s - "${APP_DIR}"

echo "✅ Build complete! Run with: open ${APP_DIR}"
