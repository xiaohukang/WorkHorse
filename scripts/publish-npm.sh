#!/usr/bin/env bash
# Build, verify, and publish the npm package.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

REGISTRY="${NPM_REGISTRY:-https://registry.npmjs.org/}"
TAG="${NPM_TAG:-latest}"
ACCESS="${NPM_ACCESS:-public}"
DRY_RUN="${DRY_RUN:-0}"
SKIP_BUILD="${SKIP_BUILD:-0}"
OTP="${NPM_OTP:-}"
AUTH_TYPE="${NPM_AUTH_TYPE:-}"

require_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "缺少工具: $tool" >&2
    exit 1
  fi
}

package_field() {
  local field="$1"
  node -e "const pkg = require('./package.json'); console.log(pkg[process.argv[1]] ?? '')" "$field"
}

require_tool node
require_tool npm

PACKAGE_NAME="$(package_field "name")"
PACKAGE_VERSION="$(package_field "version")"
PACKAGE_PRIVATE="$(package_field "private")"

if [[ -z "$PACKAGE_NAME" || -z "$PACKAGE_VERSION" ]]; then
  echo "package.json 缺少 name 或 version。" >&2
  exit 1
fi

if [[ "$PACKAGE_PRIVATE" == "true" ]]; then
  echo "package.json private=true，不能发布到 npm。" >&2
  exit 1
fi

echo "==> npm 账号"
npm whoami --registry "$REGISTRY" >/dev/null

echo "==> 检查版本: $PACKAGE_NAME@$PACKAGE_VERSION"
if npm view "$PACKAGE_NAME@$PACKAGE_VERSION" version --registry "$REGISTRY" >/dev/null 2>&1; then
  echo "$PACKAGE_NAME@$PACKAGE_VERSION 已经发布过，请先更新 package.json version。" >&2
  exit 1
fi

if [[ "$SKIP_BUILD" != "1" ]]; then
  echo "==> 构建 macOS .app"
  zsh ./scripts/build-app-bundle.sh
else
  echo "==> 跳过构建 (SKIP_BUILD=1)"
fi

echo "==> 测试"
npm test

echo "==> npm pack --dry-run"
npm pack --dry-run --registry "$REGISTRY"

publish_args=(publish --registry "$REGISTRY" --access "$ACCESS" --tag "$TAG")
if [[ -n "$OTP" ]]; then
  publish_args+=(--otp "$OTP")
fi
if [[ -n "$AUTH_TYPE" ]]; then
  publish_args+=(--auth-type "$AUTH_TYPE")
fi
if [[ "$DRY_RUN" == "1" ]]; then
  publish_args+=(--dry-run)
fi

echo "==> npm ${publish_args[*]}"
if ! npm "${publish_args[@]}"; then
  echo "" >&2
  echo "npm publish 失败。" >&2
  echo "如果错误是 EOTP，请完成 npm 的一次性验证后重跑，或使用：" >&2
  echo "  NPM_OTP=123456 ./scripts/publish-npm.sh" >&2
  echo "也可以指定 npm auth type，例如：" >&2
  echo "  NPM_AUTH_TYPE=legacy NPM_OTP=123456 ./scripts/publish-npm.sh" >&2
  exit 1
fi
