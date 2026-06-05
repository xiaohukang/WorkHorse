#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
APP_DIR="$BUILD_DIR/WorkHorse.app"
PKG_DIR="$BUILD_DIR/pkg-root"
DMG_DIR="$BUILD_DIR/dmg-staging"
NOTARY_ZIP="$BUILD_DIR/WorkHorse-notary.zip"

VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUNDLE_ID="${BUNDLE_ID:-com.workhorse.menu}"
PKG_ID="${PKG_ID:-$BUNDLE_ID.pkg}"
PRODUCT_ID="${PRODUCT_ID:-$BUNDLE_ID.product}"
APP_NAME="${APP_NAME:-牛马时光.app}"
APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-牛马时光}"
VOLUME_NAME="${VOLUME_NAME:-牛马时光}"
OUTPUT_BASENAME="${OUTPUT_BASENAME:-WorkHorse-$VERSION}"
ARCHS="${ARCHS:-arm64 x86_64}"
REQUIRE_NOTARIZATION="${REQUIRE_NOTARIZATION:-0}"

APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:-}"
INSTALLER_SIGN_IDENTITY="${INSTALLER_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

PKG_OUTPUT="$BUILD_DIR/$OUTPUT_BASENAME.pkg"
DMG_OUTPUT="$BUILD_DIR/$OUTPUT_BASENAME.dmg"
ZIP_OUTPUT="$BUILD_DIR/$OUTPUT_BASENAME.zip"

ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
ICONSET_SRC_1024="$ROOT_DIR/Sources/WorkHorse/Resources/Assets.xcassets/alarm-horse.imageset/app-icon-1024.png"
BUILD_PRODUCTS_DIR=""
EXECUTABLE=""

cd "$ROOT_DIR"

has_developer_id_signing() {
  [[ -n "$APP_SIGN_IDENTITY" ]]
}

has_notarization() {
  [[ -n "$NOTARY_PROFILE" ]]
}

requires_release_distribution() {
  [[ "$REQUIRE_NOTARIZATION" == "1" || -n "$APP_SIGN_IDENTITY" || -n "$INSTALLER_SIGN_IDENTITY" || -n "$NOTARY_PROFILE" ]]
}

require_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "缺少工具: $tool" >&2
    exit 1
  fi
}

require_identity() {
  local identity="$1"
  local policy="$2"

  if ! security find-identity -v -p "$policy" | grep -F "\"$identity\"" >/dev/null; then
    echo "找不到签名证书: $identity" >&2
    echo "请确认已在钥匙串中导入对应 Developer ID 证书，并且私钥可用。" >&2
    exit 1
  fi
}

preflight_release_distribution() {
  if ! requires_release_distribution; then
    return
  fi

  if [[ -z "$APP_SIGN_IDENTITY" || -z "$NOTARY_PROFILE" ]]; then
    echo "正式发布需要同时设置 APP_SIGN_IDENTITY 和 NOTARY_PROFILE。" >&2
    echo "例如：" >&2
    echo "  APP_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \\" >&2
    echo "  INSTALLER_SIGN_IDENTITY='Developer ID Installer: Your Name (TEAMID)' \\" >&2
    echo "  NOTARY_PROFILE='notarytool-password' \\" >&2
    echo "  REQUIRE_NOTARIZATION=1 \\" >&2
    echo "  ./scripts/package_app.sh" >&2
    exit 1
  fi

  require_identity "$APP_SIGN_IDENTITY" codesigning

  if [[ -n "$INSTALLER_SIGN_IDENTITY" ]]; then
    require_identity "$INSTALLER_SIGN_IDENTITY" basic
  else
    echo "未设置 INSTALLER_SIGN_IDENTITY，.pkg 会生成但不会作为正式安装包公证。"
  fi

  echo "==> 验证 notarytool profile"
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null; then
    echo "无法使用 notarytool profile: $NOTARY_PROFILE" >&2
    echo "请先运行 xcrun notarytool store-credentials 保存 Apple ID / Team ID / App 专用密码。" >&2
    exit 1
  fi
}

build_release() {
  local arch_args=()

  if [[ "$ARCHS" == "native" ]]; then
    echo "==> 编译 release 版本 (native)"
    swift build -c release
    BUILD_PRODUCTS_DIR="$BUILD_DIR/release"
  else
    echo "==> 编译 universal release 版本 ($ARCHS)"
    for arch in ${=ARCHS}; do
      arch_args+=(--arch "$arch")
    done
    swift build -c release "${arch_args[@]}"
    BUILD_PRODUCTS_DIR="$BUILD_DIR/apple/Products/Release"
  fi

  EXECUTABLE="$BUILD_PRODUCTS_DIR/WorkHorse"
}

create_app_icon() {
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
}

write_info_plist() {
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
}

assemble_app() {
  echo "==> 组装 .app 包"
  rm -rf "$APP_DIR"
  mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
  cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/WorkHorse"

  if [[ -f "$ROOT_DIR/Sources/WorkHorse/Resources/statusbar-icon.png" ]]; then
    cp "$ROOT_DIR/Sources/WorkHorse/Resources/statusbar-icon.png" "$APP_DIR/Contents/Resources/statusbar-icon.png"
  fi
  cp "$ROOT_DIR/Sources/WorkHorse/Resources/popup-brand-icon.png" "$APP_DIR/Contents/Resources/popup-brand-icon.png"

  find "$BUILD_PRODUCTS_DIR" -maxdepth 1 \( -name '*.resources' -o -name '*.bundle' \) -exec cp -R {} "$APP_DIR/Contents/Resources/" \;
  create_app_icon
  write_info_plist
  chmod +x "$APP_DIR/Contents/MacOS/WorkHorse"
}

sign_app() {
  echo "==> 签名 .app"
  if has_developer_id_signing; then
    codesign --force --deep --options runtime --timestamp --sign "$APP_SIGN_IDENTITY" "$APP_DIR"
    codesign --verify --deep --strict --verbose=2 "$APP_DIR"
  else
    echo "未设置 APP_SIGN_IDENTITY，使用 ad-hoc 签名。本产物不能用于正式公证。"
    codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
  fi
}

create_pkg() {
  echo "==> 生成 .pkg"
  local component_plist="$BUILD_DIR/workhorse-component.plist"
  local component_pkg="$BUILD_DIR/WorkHorse-component.pkg"
  local scripts_dir="$BUILD_DIR/pkg-scripts"

  rm -rf "$PKG_DIR" "$PKG_OUTPUT" "$component_pkg" "$component_plist" "$scripts_dir"
  mkdir -p "$PKG_DIR/Applications" "$scripts_dir"
  cp -R "$APP_DIR" "$PKG_DIR/Applications/$APP_NAME"

  cat > "$component_plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
  <dict>
    <key>BundleHasStrictIdentifier</key>
    <true/>
    <key>BundleIsRelocatable</key>
    <false/>
    <key>BundleIsVersionChecked</key>
    <true/>
    <key>BundleOverwriteAction</key>
    <string>upgrade</string>
    <key>BundlePostInstallScriptPath</key>
    <string>postinstall</string>
    <key>Identifier</key>
    <string>$BUNDLE_ID</string>
    <key>Name</key>
    <string>$APP_NAME</string>
    <key>PackageIdentifier</key>
    <string>$PKG_ID</string>
    <key>RootRelativeBundlePath</key>
    <string>Applications/$APP_NAME</string>
    <key>StrictVersions</key>
    <true/>
    <key>Version</key>
    <string>$VERSION</string>
  </dict>
</array>
</plist>
PLIST

  cat > "$scripts_dir/postinstall" <<POSTINSTALL
#!/usr/bin/env zsh
xattr -dr com.apple.quarantine "/Applications/$APP_NAME" 2>/dev/null || true
exit 0
POSTINSTALL
  chmod +x "$scripts_dir/postinstall"

  pkgbuild \
    --root "$PKG_DIR" \
    --component-plist "$component_plist" \
    --scripts "$scripts_dir" \
    --identifier "$PKG_ID" \
    --version "$VERSION" \
    --install-location / \
    "$component_pkg"

  local productbuild_args=(
    --package "$component_pkg"
    --identifier "$PRODUCT_ID"
    --version "$VERSION"
  )

  if [[ -n "$INSTALLER_SIGN_IDENTITY" ]]; then
    productbuild_args+=(--sign "$INSTALLER_SIGN_IDENTITY")
  else
    echo "未设置 INSTALLER_SIGN_IDENTITY，生成未签名 .pkg。"
  fi

  productbuild "${productbuild_args[@]}" "$PKG_OUTPUT"
  rm -rf "$PKG_DIR" "$component_pkg" "$component_plist" "$scripts_dir"
}

create_dmg() {
  echo "==> 生成 .dmg"
  rm -rf "$DMG_DIR" "$DMG_OUTPUT"
  mkdir -p "$DMG_DIR"
  cp -R "$APP_DIR" "$DMG_DIR/$APP_NAME"
  ln -s /Applications "$DMG_DIR/Applications"
  hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_OUTPUT"
  rm -rf "$DMG_DIR"
}

create_zip() {
  echo "==> 生成 .zip"
  rm -f "$ZIP_OUTPUT"
  ditto -c -k --keepParent "$APP_DIR" "$ZIP_OUTPUT"
}

notarize_file() {
  local file="$1"
  echo "提交公证: $file"
  xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait
}

notarize_app_and_staple() {
  if ! has_developer_id_signing || ! has_notarization; then
    echo "==> 跳过 .app 公证。设置 APP_SIGN_IDENTITY 和 NOTARY_PROFILE 后会启用。"
    return
  fi

  echo "==> 公证 .app 并 staple"
  rm -f "$NOTARY_ZIP"
  ditto -c -k --keepParent "$APP_DIR" "$NOTARY_ZIP"
  notarize_file "$NOTARY_ZIP"
  xcrun stapler staple "$APP_DIR"
  xcrun stapler validate "$APP_DIR"
  rm -f "$NOTARY_ZIP"
}

notarize_distribution_artifacts() {
  if ! has_developer_id_signing || ! has_notarization; then
    echo "==> 跳过 .dmg/.pkg 公证。设置 APP_SIGN_IDENTITY 和 NOTARY_PROFILE 后会启用。"
    return
  fi

  echo "==> 公证 .dmg 并 staple"
  notarize_file "$DMG_OUTPUT"
  xcrun stapler staple "$DMG_OUTPUT"
  xcrun stapler validate "$DMG_OUTPUT"

  if [[ -n "$INSTALLER_SIGN_IDENTITY" ]]; then
    echo "公证 .pkg 并 staple"
    notarize_file "$PKG_OUTPUT"
    xcrun stapler staple "$PKG_OUTPUT"
    xcrun stapler validate "$PKG_OUTPUT"
  else
    echo "跳过 .pkg 公证：未设置 INSTALLER_SIGN_IDENTITY。"
  fi
}

verify_artifacts() {
  echo "==> 验证产物"
  codesign --verify --deep --strict --verbose=2 "$APP_DIR"
  echo "架构: $(lipo -archs "$APP_DIR/Contents/MacOS/WorkHorse")"

  if has_developer_id_signing && has_notarization; then
    spctl --assess --type execute --verbose "$APP_DIR"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG_OUTPUT"
    if [[ -n "$INSTALLER_SIGN_IDENTITY" ]]; then
      spctl --assess --type install --verbose "$PKG_OUTPUT"
    fi
  else
    echo "当前不是 Developer ID + 公证产物，跳过 Gatekeeper 通过性校验。"
  fi
}

print_summary() {
  echo ""
  echo "打包完成"
  echo "  .app: $APP_DIR"
  echo "  .pkg: $PKG_OUTPUT"
  echo "  .dmg: $DMG_OUTPUT"
  echo "  .zip: $ZIP_OUTPUT"
  echo ""

  if has_developer_id_signing && has_notarization; then
    echo "已完成 .app 和 .dmg 的 Developer ID 签名、公证和 staple。"
    if [[ -n "$INSTALLER_SIGN_IDENTITY" ]]; then
      echo ".pkg 也已完成 Developer ID Installer 签名、公证和 staple。"
    else
      echo ".pkg 未设置 Installer 证书，不能作为正式安装包分发。"
    fi
  else
    echo "当前是本地打包产物。正式发布请设置："
    echo "  APP_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'"
    echo "  INSTALLER_SIGN_IDENTITY='Developer ID Installer: Your Name (TEAMID)'"
    echo "  NOTARY_PROFILE='notarytool-password'"
    echo "  REQUIRE_NOTARIZATION=1"
  fi
}

require_tool swift
require_tool sips
require_tool iconutil
require_tool codesign
require_tool hdiutil
require_tool ditto
require_tool pkgbuild
require_tool productbuild
require_tool lipo
require_tool spctl

preflight_release_distribution
build_release
assemble_app
sign_app
notarize_app_and_staple
create_pkg
create_dmg
create_zip
notarize_distribution_artifacts
verify_artifacts
print_summary
