#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ENV="$PROJECT_ROOT/.build-venv"
OUTPUT_DIR="$PROJECT_ROOT/dist/macos"
APP_DIR="$OUTPUT_DIR/N-AI.app"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Build the macOS app on a Mac." >&2
    exit 1
fi

command -v swiftc >/dev/null || { echo "Xcode Command Line Tools are required." >&2; exit 1; }
command -v hdiutil >/dev/null || { echo "hdiutil is required to create the DMG." >&2; exit 1; }

python3 -m venv "$BUILD_ENV"
"$BUILD_ENV/bin/python" -m pip install --upgrade pip
"$BUILD_ENV/bin/python" -m pip install -r "$PROJECT_ROOT/requirements-build.txt"

mkdir -p "$OUTPUT_DIR"
BUILD_DIR="$(mktemp -d "$OUTPUT_DIR/.build.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

"$BUILD_ENV/bin/pyinstaller" \
    --clean \
    --noconfirm \
    --onefile \
    --paths "$PROJECT_ROOT" \
    --name N-AIBackend \
    --distpath "$BUILD_DIR/backend" \
    --workpath "$BUILD_DIR/pyinstaller-work" \
    --specpath "$BUILD_DIR" \
    "$PROJECT_ROOT/backend/main.py"

cp "$BUILD_DIR/backend/N-AIBackend" "$APP_DIR/Contents/Resources/N-AIBackend"
swiftc -O \
    "$PROJECT_ROOT/macos/OverlayApp.swift" \
    "$PROJECT_ROOT/macos/CaptureManager.swift" \
    "$PROJECT_ROOT/macos/PythonBridge.swift" \
    -o "$APP_DIR/Contents/MacOS/N-AI"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>N-AI</string>
    <key>CFBundleIdentifier</key><string>com.nai.overlay</string>
    <key>CFBundleName</key><string>N-AI</string>
    <key>CFBundleDisplayName</key><string>N-AI</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSMicrophoneUsageDescription</key><string>N-AI uses your microphone to transcribe your speech and provide responses.</string>
</dict>
</plist>
PLIST

cat > "$OUTPUT_DIR/SETUP.txt" <<'SETUP'
N-AI setup

1. Open N-AI-macOS.dmg, then double-click N-AI-Installer.pkg.
2. Follow the Installer prompts to install N-AI into Applications.
3. Open N-AI. Allow microphone access when macOS asks.
4. Click the key icon in N-AI, paste your OpenAI API key, then choose Save key.
   The key is stored locally in:
   ~/Library/Application Support/N-AI/.env
5. Quit and reopen N-AI after saving the key.

The installer does not include an API key. This unsigned build may require
right-click > Open on the package the first time. For public distribution, sign
and notarize the app and package.
SETUP

DMG_PATH="$OUTPUT_DIR/N-AI-macOS.dmg"
DMG_STAGING="$BUILD_DIR/dmg-root"
rm -f "$DMG_PATH"
mkdir -p "$DMG_STAGING"
mkdir -p "$BUILD_DIR/pkg-root"
cp -R "$APP_DIR" "$BUILD_DIR/pkg-root/"
pkgbuild \
    --root "$BUILD_DIR/pkg-root" \
    --identifier com.nai.overlay \
    --version 1.0.0 \
    --install-location /Applications \
    "$DMG_STAGING/N-AI-Installer.pkg"
cp "$OUTPUT_DIR/SETUP.txt" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "N-AI" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"
echo "Created $DMG_PATH"
