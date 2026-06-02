#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/WorkHorse.app"
EXECUTABLE="$ROOT_DIR/.build/release/WorkHorse"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Library/Developer/CommandLineTools" ]]; then
  export DEVELOPER_DIR="/Library/Developer/CommandLineTools"
fi

cd "$ROOT_DIR"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/WorkHorse"
cp "$ROOT_DIR/Sources/WorkHorse/Resources/statusbar-icon.svg" "$APP_DIR/Contents/Resources/statusbar-icon.svg"

find "$ROOT_DIR/.build/release" -maxdepth 1 \( -name '*.resources' -o -name '*.bundle' \) -exec cp -R {} "$APP_DIR/Contents/Resources/" \;

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>牛马时光</string>
  <key>CFBundleExecutable</key>
  <string>WorkHorse</string>
  <key>CFBundleIdentifier</key>
  <string>com.workhorse.menu</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>WorkHorse</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSUserNotificationAlertStyle</key>
  <string>alert</string>
</dict>
</plist>
PLIST

chmod +x "$APP_DIR/Contents/MacOS/WorkHorse"
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

printf '%s\n' "$APP_DIR"
