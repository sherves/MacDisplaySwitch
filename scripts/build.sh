#!/bin/bash
# 在 macOS 上构建 CLI 与菜单栏 App，并打包为 DisplayFocus.app
set -euo pipefail
cd "$(dirname "$0")/.."
[ "${SKIP_SWIFT_BUILD:-}" = 1 ] || swift build -c release
BIN=.build/release
APP=build/DisplayFocus.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp "$BIN/DisplayFocusApp" "$APP/Contents/MacOS/DisplayFocus"
cp "$BIN/displayfocus" "$APP/Contents/MacOS/DisplayFocusRecovery"
# Case-insensitive macOS volumes must not alias the GUI and recovery helper.
if cmp -s "$APP/Contents/MacOS/DisplayFocus" "$APP/Contents/MacOS/DisplayFocusRecovery"; then
    echo "GUI and recovery helper unexpectedly identical" >&2
    exit 1
fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>DisplayFocus</string>
<key>CFBundleIdentifier</key><string>com.holmes.displayfocus</string>
<key>CFBundleExecutable</key><string>DisplayFocus</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.2</string>
<key>CFBundleVersion</key><string>20261028.4</string>
<key>CFBundleDevelopmentRegion</key><string>zh-Hans</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
xattr -cr "$APP" 2>/dev/null || true
codesign --force --sign - "$APP/Contents/MacOS/DisplayFocusRecovery"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
echo "CLI: $BIN/displayfocus"
echo "App: $APP"
