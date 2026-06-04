#!/usr/bin/env node

import { execFile } from 'node:child_process';
import { access } from 'node:fs/promises';
import { constants } from 'node:fs';
import { homedir } from 'node:os';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

const appName = '牛马时光.app';
const candidatePaths = [
  `/Applications/${appName}`,
  `${homedir()}/Applications/${appName}`
];

function printHelp() {
  console.log(`牛马时光 WorkHorse

Usage:
  workhorse                 启动菜单栏常驻 WorkHorse
  workhorse open            等价于无参数
  workhorse install         把 .app 拷到 /Applications 并注册到 Launchpad
  workhorse uninstall       从 /Applications 移除 WorkHorse.app
  workhorse help            显示本帮助
`);
}

async function findInstalledApp() {
  for (const candidate of candidatePaths) {
    try {
      await access(candidate, constants.F_OK);
      return candidate;
    } catch {
      // try next
    }
  }
  return null;
}

async function openApp(appPath) {
  await execFileAsync('open', ['-a', appPath]);
}

async function runInstall() {
  const { fileURLToPath } = await import('node:url');
  const { dirname, resolve } = await import('node:path');
  const installScript = resolve(
    dirname(fileURLToPath(import.meta.url)),
    '..',
    'scripts',
    'install-macos-app.mjs'
  );
  await execFileAsync(process.execPath, [installScript], { stdio: 'inherit' });
}

async function runUninstall() {
  for (const target of candidatePaths) {
    try {
      await access(target, constants.F_OK);
    } catch {
      continue;
    }
    await execFileAsync('rm', ['-rf', target]).catch(() => {});
    console.log(`已移除: ${target}`);
  }
  console.log('WorkHorse 已卸载。');
}

async function main() {
  const args = process.argv.slice(2);
  const command = args[0];

  if (command === 'help' || args.includes('--help') || args.includes('-h')) {
    printHelp();
    return;
  }

  if (command === 'install') {
    await runInstall();
    return;
  }

  if (command === 'uninstall') {
    await runUninstall();
    return;
  }

  const appPath = await findInstalledApp();
  if (!appPath) {
    console.error('未检测到 WorkHorse.app，请先执行：');
    console.error('  workhorse-install');
    console.error('或在 npm 装好后跑：');
    console.error('  npm install -g workhorse-menu   # 重新装一次');
    console.error('  workhorse install               # 然后再启动');
    process.exitCode = 1;
    return;
  }

  await openApp(appPath);
  console.log(`已启动: ${appPath}`);
}

main().catch((error) => {
  console.error(error && error.stack ? error.stack : error);
  process.exitCode = 1;
});
