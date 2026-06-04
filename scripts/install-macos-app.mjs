#!/usr/bin/env node

import { access, cp, mkdir, rm, stat } from 'node:fs/promises';
import { constants } from 'node:fs';
import { execFile } from 'node:child_process';
import { homedir } from 'node:os';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const appName = '牛马时光.app';
const bundledApp = resolve(root, 'dist', appName);

async function canWrite(directory) {
  try {
    await access(directory, constants.W_OK);
    return true;
  } catch {
    return false;
  }
}

async function pathExists(p) {
  try {
    await stat(p);
    return true;
  } catch {
    return false;
  }
}

async function registerApp(appPath) {
  const lsregister =
    '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister';
  await execFileAsync(lsregister, ['-f', appPath]).catch(() => {});
  await execFileAsync('touch', [appPath]).catch(() => {});
}

async function installInto(applicationsDir) {
  await mkdir(applicationsDir, { recursive: true });
  const destination = resolve(applicationsDir, appName);
  await rm(destination, { recursive: true, force: true });
  await cp(bundledApp, destination, { recursive: true });
  await execFileAsync('xattr', ['-dr', 'com.apple.quarantine', destination]).catch(() => {});
  await registerApp(destination);
  return destination;
}

async function install() {
  if (!(await pathExists(bundledApp))) {
    console.error(`未找到预编译的应用: ${bundledApp}`);
    console.error('');
    console.error('npm 包里缺失 dist/牛马时光.app，通常意味着：');
    console.error('  1) 你直接 `npm install` 拉了仓库源码（不是发布的 tarball）');
    console.error('  2) 你装的是旧版本包，新版本开始带预编译 .app 后还没升级');
    console.error('');
    console.error('请确认从 npm registry 拉取，例如：');
    console.error('  npm uninstall -g workhorse-menu');
    console.error('  npm install -g workhorse-menu');
    process.exitCode = 1;
    return;
  }

  const systemApplications = '/Applications';
  const userApplications = resolve(homedir(), 'Applications');
  const target = (await canWrite(systemApplications)) ? systemApplications : userApplications;
  const installedPath = await installInto(target);

  console.log(`已安装到 ${installedPath}`);
  console.log('现在可以在启动台搜索 "牛马时光" 打开，或在终端运行 workhorse。');
}

install().catch((error) => {
  console.error(error && error.stack ? error.stack : error);
  process.exitCode = 1;
});
