#!/usr/bin/env node

import { cp, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

const APP_DISPLAY_NAME = '牛马时光';
const APP_NAME = `${APP_DISPLAY_NAME}.app`;
const BUNDLE_ID = 'com.workhorse.menu';
const VERSION = '0.1.0';
const BUILD_NUMBER = '1';
const MIN_MACOS = '13.0';

const appRoot = resolve(root, 'dist', APP_NAME);
const contents = resolve(appRoot, 'Contents');
const macOS = resolve(contents, 'MacOS');
const resources = resolve(contents, 'Resources');
const iconName = 'AppIcon';

const sourceIcon = resolve(
  root,
  'Sources/WorkHorse/Resources/Assets.xcassets/alarm-horse.imageset/app-icon-1024.png'
);
const statusbarIcon = resolve(root, 'Sources/WorkHorse/Resources/statusbar-icon.png');
const popupBrandIcon = resolve(root, 'Sources/WorkHorse/Resources/popup-brand-icon.png');

function requireTool(name) {
  if (!which(name)) {
    throw new Error(
      `缺少工具: ${name}\n` +
      `请运行: xcode-select --install\n` +
      `安装完成后重试: workhorse-install`
    );
  }
}

function which(name) {
  const path = process.env.PATH ?? '';
  for (const dir of path.split(':')) {
    if (!dir) continue;
    try {
      const full = join(dir, name);
      // 走一遍 stat 来代替外部 which 命令
      // eslint-disable-next-line no-sync
      require('node:fs').accessSync(full);
      return full;
    } catch {
      // continue
    }
  }
  return null;
}

async function buildReleaseBinary() {
  console.log('==> swift build -c release');
  await execFileAsync('swift', ['build', '-c', 'release'], {
    cwd: root,
    stdio: 'inherit'
  });
}

function executablePath() {
  return resolve(root, '.build', 'release', 'WorkHorse');
}

async function writeInfoPlist() {
  const plist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_DISPLAY_NAME}</string>
  <key>CFBundleExecutable</key>
  <string>WorkHorse</string>
  <key>CFBundleIconFile</key>
  <string>${iconName}</string>
  <key>CFBundleIconName</key>
  <string>${iconName}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>WorkHorse</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key>
  <string>${MIN_MACOS}</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSUserNotificationAlertStyle</key>
  <string>alert</string>
</dict>
</plist>
`;
  await writeFile(resolve(contents, 'Info.plist'), plist);
}

async function createAppIcon() {
  console.log('==> 生成 AppIcon.icns');
  const tempDir = await mkdtemp(join(tmpdir(), 'workhorse-icon-'));
  const iconset = resolve(tempDir, 'AppIcon.iconset');
  await mkdir(iconset, { recursive: true });

  const specs = [
    ['icon_16x16.png', 16],
    ['icon_16x16@2x.png', 32],
    ['icon_32x32.png', 32],
    ['icon_32x32@2x.png', 64],
    ['icon_128x128.png', 128],
    ['icon_128x128@2x.png', 256],
    ['icon_256x256.png', 256],
    ['icon_256x256@2x.png', 512],
    ['icon_512x512.png', 512],
    ['icon_512x512@2x.png', 1024]
  ];

  for (const [fileName, size] of specs) {
    await execFileAsync('sips', [
      '-s', 'format', 'png',
      '-z', String(size), String(size),
      sourceIcon,
      '--out', resolve(iconset, fileName)
    ]);
  }

  await execFileAsync('iconutil', [
    '-c', 'icns',
    iconset,
    '-o', resolve(resources, `${iconName}.icns`)
  ]);
  await rm(tempDir, { recursive: true, force: true });
}

async function copyBundledResources() {
  const sourceResources = resolve(root, '.build', 'release');
  const { readdir } = await import('node:fs/promises');
  const entries = await readdir(sourceResources, { withFileTypes: true });
  for (const entry of entries) {
    if (entry.isDirectory() && (entry.name.endsWith('.resources') || entry.name.endsWith('.bundle'))) {
      await cp(resolve(sourceResources, entry.name), resolve(resources, entry.name), { recursive: true });
    }
  }
}

async function assembleApp() {
  console.log('==> 组装 .app 包');
  await rm(appRoot, { recursive: true, force: true });
  await mkdir(macOS, { recursive: true });
  await mkdir(resources, { recursive: true });

  await cp(executablePath(), resolve(macOS, 'WorkHorse'));
  await cp(statusbarIcon, resolve(resources, 'statusbar-icon.png'));
  await cp(popupBrandIcon, resolve(resources, 'popup-brand-icon.png'));
  await copyBundledResources();
  await createAppIcon();
  await writeInfoPlist();
  // 复制源码（与 MacCleanLens 一致，便于后续在 .app 内定位）
  // 不在此处复制整个 Sources，避免 npm 包体过大。
}

async function signApp() {
  console.log('==> ad-hoc 签名 .app');
  await execFileAsync('codesign', ['--force', '--deep', '--sign', '-', appRoot]).catch((error) => {
    console.warn('ad-hoc 签名失败（可忽略，未签名也能运行）：', error.message);
  });
}

async function build() {
  for (const tool of ['swift', 'sips', 'iconutil', 'codesign']) {
    requireTool(tool);
  }

  await buildReleaseBinary();
  await assembleApp();
  await signApp();

  console.log('');
  console.log('构建完成:', appRoot);
  console.log('可直接执行: open "' + appRoot + '"');
}

build().catch((error) => {
  console.error('');
  console.error(error && error.message ? error.message : error);
  if (!error?.message?.includes('缺少工具')) {
    console.error(error?.stack ?? '');
  }
  console.error('');
  console.error('如果以上是工具缺失，请先安装 Xcode Command Line Tools:');
  console.error('  xcode-select --install');
  console.error('然后重试: workhorse-install');
  process.exitCode = 1;
});
