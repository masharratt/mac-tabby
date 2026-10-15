#!/bin/bash
# Builds a release binary and wraps it in build/Tabby.app, signed with the local "Flameshot Local"
# identity. Fails if that identity is missing: an ad-hoc signature changes on every build and
# would silently invalidate the Accessibility / Screen Recording grants.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Tabby.app"
IDENTITY="Flameshot Local"

if ! security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    echo "error: code signing identity \"$IDENTITY\" not found in the keychain." >&2
    echo "Create it (Keychain Access > Certificate Assistant > Create a Certificate, type Code Signing) and retry." >&2
    exit 1
fi

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Tabby"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Tabby"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Tabby</string>
    <key>CFBundleIdentifier</key><string>local.tabby</string>
    <key>CFBundleName</key><string>Tabby</string>
    <key>CFBundleDisplayName</key><string>Tabby</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSScreenCaptureUsageDescription</key><string>Tabby shows window thumbnails in the switcher. Images never leave this Mac.</string>
</dict>
</plist>
PLIST

# No hardened runtime, per spec.
codesign --force --deep --sign "$IDENTITY" "$APP"
echo "Built $APP (signed: $IDENTITY)"

# --install: replace /Applications/Tabby.app and relaunch it.
if [[ "${1:-}" == "--install" ]]; then
    pkill -x Tabby || true
    rm -rf /Applications/Tabby.app
    cp -R "$APP" /Applications/
    open /Applications/Tabby.app
    echo "Installed /Applications/Tabby.app"
fi
