#!/bin/bash
set -e

APP_NAME="AndroidMac"
APP_DIR="${APP_NAME}.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RESOURCES_DIR="${APP_DIR}/Contents/Resources"

echo "🧹 Cleaning up..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

echo "🔨 Compiling Swift files..."
swiftc \
  -O \
  -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk -module-cache-path ./.module-cache \
  -target arm64-apple-macosx14.0 \
  -o "${MACOS_DIR}/${APP_NAME}" \
  AndroidMac/App/*.swift \
  AndroidMac/Views/*.swift \
  AndroidMac/ViewModels/*.swift \
  AndroidMac/Models/*.swift \
  AndroidMac/Services/*.swift \
  AndroidMac/Utilities/*.swift 2>/dev/null || \
swiftc \
  -O \
  -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.5.sdk -module-cache-path ./.module-cache \
  -target arm64-apple-macosx14.0 \
  -o "${MACOS_DIR}/${APP_NAME}" \
  AndroidMac/App/*.swift \
  AndroidMac/Views/*.swift

echo "📝 Creating Info.plist..."
cat <<EOF > "${APP_DIR}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.antigravity.${APP_NAME}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "🖋️ Codesigning..."
codesign --force --deep -s - "${APP_DIR}"

echo "✅ Build complete! Run with: open ${APP_DIR}"
