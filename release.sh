#!/bin/bash
# 发布「金铲铲修复工具」新版本到 GitHub Releases
# 用法: ./release.sh [更新说明(可多条，空格分隔)]
set -e
cd "$(dirname "$0")"

# 从 Info.plist 读取版本号
VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)"
TAG="v$VER"
NOTES="${*:-金铲铲修复工具 $TAG}"

# 走本地代理（如未开代理可注释掉这两行）
export HTTPS_PROXY=http://127.0.0.1:7900
export HTTP_PROXY=http://127.0.0.1:7900

echo "[1/4] 编译构建 ..."
./build.sh

echo "[2/4] 打包 zip ..."
ZIP="JKChessFixTool-$VER.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "金铲铲修复工具.app" "$ZIP"

echo "[3/4] 创建/更新 Release $TAG ..."
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "  $TAG 已存在，删除后重建"
  gh release delete "$TAG" --yes --cleanup-tag
fi
gh release create "$TAG" "$ZIP" --title "金铲铲修复工具 $TAG" --notes "$NOTES"

echo "[4/4] 发布完成"
gh release view "$TAG" --json url,assets --jq '"  页面: \(.url)\n  附件: \([.assets[].name] | join(", "))"'
