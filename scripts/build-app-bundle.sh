#!/usr/bin/env zsh
# 只产 .app（不产 .pkg/.dmg/.zip），专给 CI 在 npm 发版前预编译用。
# 复用 scripts/package_app.sh 的 assemble / icon / plist / sign 流程，
# 但跳过分发产物与公证，产物固定在 dist/牛马时光.app。

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
APP_DIR="$BUILD_DIR/WorkHorse.app"
DIST_APP="$ROOT_DIR/dist/牛马时光.app"

VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUNDLE_ID="${BUNDLE_ID:-com.workhorse.menu}"
APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-牛马时光}"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
ICONSET_SRC_1024="$ROOT_DIR/Sources/WorkHorse/Resources/Assets.xcassets/alarm-horse.imageset/app-icon-1024.png"

APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:-}"
ARCHS="${ARCHS:-arm64 x86_64}"

require_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "缺少工具: $tool" >&2
    exit 1
  fi
}

require_tool swift
require_tool sips
require_tool iconutil
require_tool codesign
require_tool cp
require_tool mkdir

cd "$ROOT_DIR"

# 1) 编译
if [[ "$ARCHS" == "native" ]]; then
  echo "==> swift build -c release (native)"
  swift build -c release
  BUILD_PRODUCTS_DIR="$BUILD_DIR/release"
else
  echo "==> swift build -c release universal ($ARCHS)"
  local -a arch_args=()
  for arch in ${=ARCHS}; do
    arch_args+=(--arch "$arch")
  done
  swift build -c release "${arch_args[@]}"
  BUILD_PRODUCTS_DIR="$BUILD_DIR/apple/Products/Release"
fi
BUILD_PRODUCTS_DIR="$(cd "$BUILD_PRODUCTS_DIR" && pwd -P)"

EXECUTABLE="$BUILD_PRODUCTS_DIR/WorkHorse"
if [[ ! -f "$EXECUTABLE" ]]; then
  echo "找不到编译产物: $EXECUTABLE" >&2
  exit 1
fi

# 2) 组装 .app
echo "==> 组装 .app 到 dist/牛马时光.app"
rm -rf "$APP_DIR" "$DIST_APP"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/WorkHorse"

if [[ -f "$ROOT_DIR/Sources/WorkHorse/Resources/statusbar-icon.png" ]]; then
  cp "$ROOT_DIR/Sources/WorkHorse/Resources/statusbar-icon.png" "$APP_DIR/Contents/Resources/statusbar-icon.png"
fi
cp "$ROOT_DIR/Sources/WorkHorse/Resources/popup-brand-icon.png" "$APP_DIR/Contents/Resources/popup-brand-icon.png"

# SwiftPM 资源包（*.resources / *.bundle）拷到 Resources
find "$BUILD_PRODUCTS_DIR" -maxdepth 1 \( -name '*.resources' -o -name '*.bundle' \) -exec cp -R {} "$APP_DIR/Contents/Resources/" \;

# 3) 生成 AppIcon.icns
echo "==> 生成 AppIcon.icns"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
make_icon() {
  local size="$1"
  local out="$2"
  sips -s format png -z "$size" "$size" "$ICONSET_SRC_1024" --out "$out" >/dev/null
}
make_icon 16   "$ICONSET_DIR/icon_16x16.png"
make_icon 32   "$ICONSET_DIR/icon_16x16@2x.png"
make_icon 32   "$ICONSET_DIR/icon_32x32.png"
make_icon 64   "$ICONSET_DIR/icon_32x32@2x.png"
make_icon 128  "$ICONSET_DIR/icon_128x128.png"
make_icon 256  "$ICONSET_DIR/icon_128x128@2x.png"
make_icon 256  "$ICONSET_DIR/icon_256x256.png"
make_icon 512  "$ICONSET_DIR/icon_256x256@2x.png"
make_icon 512  "$ICONSET_DIR/icon_512x512.png"
cp "$ICONSET_SRC_1024" "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET_DIR"

# 4) Info.plist
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleExecutable</key>
  <string>WorkHorse</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>WorkHorse</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSUserNotificationAlertStyle</key>
  <string>alert</string>
</dict>
</plist>
PLIST

chmod +x "$APP_DIR/Contents/MacOS/WorkHorse"

# 5) 签名
echo "==> 签名 .app"
if [[ -n "$APP_SIGN_IDENTITY" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$APP_SIGN_IDENTITY" "$APP_DIR"
  codesign --verify --deep --strict --verbose=2 "$APP_DIR"
else
  echo "未设置 APP_SIGN_IDENTITY，使用 ad-hoc 签名。"
  codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
fi

# 6) 拷到 dist/
mkdir -p "$(dirname "$DIST_APP")"
rm -rf "$DIST_APP"
cp -R "$APP_DIR" "$DIST_APP"

echo ""
echo "构建完成: $DIST_APP"
echo "可直接执行: open \"$DIST_APP\""
