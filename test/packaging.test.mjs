import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import test from 'node:test';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '..');

test('package.json exposes macOS install script (no postinstall, no runtime build)', async () => {
  const pkg = JSON.parse(await readFile(resolve(root, 'package.json'), 'utf8'));

  assert.equal(pkg.bin['workhorse-install'], 'scripts/install-macos-app.mjs');
  assert.equal(pkg.bin['workhorse'], 'bin/workhorse.mjs');
  assert.equal(pkg.type, 'module');
  // npm 安装时不应该触发任何编译 —— 同事机器不需要 Xcode CLT
  assert.equal(pkg.postinstall, undefined);
  assert.equal(pkg.scripts.postinstall, undefined);
  // files 白名单必须包含 dist/（CI 预编译的 .app 放这里）
  assert.ok(pkg.files.includes('dist/'));
  assert.ok(pkg.files.includes('scripts/install-macos-app.mjs'));
  assert.ok(pkg.files.includes('scripts/build-app-bundle.sh'));
});

test('install script copies prebundled .app without invoking swift', async () => {
  const installScript = await readFile(resolve(root, 'scripts/install-macos-app.mjs'), 'utf8');

  assert.match(installScript, /\/Applications/);
  assert.match(installScript, /Applications/);
  assert.match(installScript, /牛马时光\.app/);
  assert.match(installScript, /lsregister/);
  // 关键断言：install 脚本里不能有 swift 调用
  assert.doesNotMatch(installScript, /execFileAsync\(\s*'swift'|\bswift\s+build/);
});

test('build-app-bundle.sh is a real build script for CI to invoke', async () => {
  const script = await readFile(resolve(root, 'scripts/build-app-bundle.sh'), 'utf8');

  assert.match(script, /swift\s+build/);
  assert.match(script, /codesign/);
  assert.match(script, /iconutil/);
  assert.match(script, /dist\/牛马时光\.app/);
});

test('workhorse launcher only opens, does not trigger build', async () => {
  const launcher = await readFile(resolve(root, 'bin/workhorse.mjs'), 'utf8');

  assert.match(launcher, /\/Applications/);
  assert.match(launcher, /Applications/);
  assert.match(launcher, /workhorse-install/);
  assert.match(launcher, /open/);
  // 关键断言：launcher 不应该再去调 build
  assert.doesNotMatch(launcher, /swift\s+build/);
});

test('CI workflow builds the prebundled .app before npm publish', async () => {
  const workflow = await readFile(resolve(root, '.github/workflows/release.yml'), 'utf8');

  assert.match(workflow, /build-app-bundle\.sh/);
  assert.match(workflow, /npm\s+publish/);
  assert.match(workflow, /dist/);
});
