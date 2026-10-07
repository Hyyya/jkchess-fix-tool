#!/bin/bash
# 构建「金铲铲修复工具」独立 App（无需完整 Xcode）
set -e
cd "$(dirname "$0")"

echo "[1/5] 编译主程序 ..."
SDK="$(xcrun --show-sdk-path)"
swiftc -parse-as-library -O -target arm64-apple-macosx13.0 -sdk "$SDK" \
  JKChessFixTool.swift -o JKChessFixTool \
  -framework SwiftUI -framework AppKit

echo "[2/5] 生成应用图标 ..."
rm -rf /tmp/jk_icon.iconset
mkdir -p /tmp/jk_icon.iconset
SRC_ICON="icon_design.png"
sips -z 16 16 "$SRC_ICON" --out /tmp/jk_icon.iconset/icon_16x16.png >/dev/null
sips -z 32 32 "$SRC_ICON" --out /tmp/jk_icon.iconset/icon_16x16@2x.png >/dev/null
sips -z 32 32 "$SRC_ICON" --out /tmp/jk_icon.iconset/icon_32x32.png >/dev/null
sips -z 64 64 "$SRC_ICON" --out /tmp/jk_icon.iconset/icon_32x32@2x.png >/dev/null
sips -z 128 128 "$SRC_ICON" --out /tmp/jk_icon.iconset/icon_128x128.png >/dev/null
sips -z 256 256 "$SRC_ICON" --out /tmp/jk_icon.iconset/icon_128x128@2x.png >/dev/null
sips -z 256 256 "$SRC_ICON" --out /tmp/jk_icon.iconset/icon_256x256.png >/dev/null
sips -z 512 512 "$SRC_ICON" --out /tmp/jk_icon.iconset/icon_256x256@2x.png >/dev/null
sips -z 512 512 "$SRC_ICON" --out /tmp/jk_icon.iconset/icon_512x512.png >/dev/null
sips -z 1024 1024 "$SRC_ICON" --out /tmp/jk_icon.iconset/icon_512x512@2x.png >/dev/null
iconutil -c icns /tmp/jk_icon.iconset -o AppIcon.icns

echo "[3/5] 组装 .app 结构 ..."
APP="金铲铲修复工具.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp JKChessFixTool "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp actions.sh "$APP/Contents/Resources/"
cp ../com.tencent.jkchess.plist "$APP/Contents/Resources/com.tencent.jkchess.plist"
chmod +x "$APP/Contents/MacOS/JKChessFixTool" "$APP/Contents/Resources/actions.sh"

echo "[4/5] 签名(ad-hoc) ..."
codesign --force --sign - "$APP"

echo "[5/5] 完成：$(pwd)/$APP"
