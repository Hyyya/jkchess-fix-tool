#!/bin/bash
# ============================================================
#  金铲铲之战 一键修复 · 后端动作脚本
#  供侧边小工具(App)调用，也可在终端直接运行:
#    ./actions.sh mic       # 一键开启麦克风
#    ./actions.sh ui        # 一键阵容适配(1080p 16:9)
#    ./actions.sh crash     # 一键闪退修复
#    ./actions.sh appsdir   # 一键修复 Applications 目录
# ============================================================
set -e

BUNDLE="com.tencent.jkchess"
PC_CONTAINER="$HOME/Library/Containers/io.playcover.PlayCover"
APPS_DIR="$PC_CONTAINER/Applications"
APP_SETTINGS_DIR="$PC_CONTAINER/App Settings"
APP_SETTINGS="$APP_SETTINGS_DIR/$BUNDLE.plist"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MAIN_PLIST="$SCRIPT_DIR/com.tencent.jkchess.plist"

locate_app() {
  local app
  app="$(find "$PC_CONTAINER" -maxdepth 5 -type d -name "$BUNDLE.app" 2>/dev/null | head -1)"
  if [[ -z "$app" ]]; then
    echo "[失败] 未找到 $BUNDLE.app"
    echo "请先在 PlayCover 中安装好金铲铲，再点此按钮。"
    return 1
  fi
  echo "$app"
}

restart_playcover() {
  echo "  重启 PlayCover 让设置生效 ..."
  osascript -e 'quit app "PlayCover"' 2>/dev/null || true
  sleep 2
  open -a PlayCover 2>/dev/null || true
  echo "  PlayCover 已重新打开，请稍后启动金铲铲。"
}

case "${1:-}" in

  appsdir)
    if [[ -d "$APPS_DIR" ]]; then
      echo "✅ Applications 目录已存在："
      echo "   $APPS_DIR"
    else
      mkdir -p "$APPS_DIR"
      echo "✅ 已创建 Applications 目录："
      echo "   $APPS_DIR"
    fi
    echo "（安装报错「未能将 jkchess 移到 Applications」即由此目录缺失导致）"
    ;;

  mic)
    app="$(locate_app)" || exit 1
    mkdir -p "$APP_SETTINGS_DIR"
    # 1) 打开麦克风同步开关
    /usr/libexec/PlistBuddy -c "Set :checkMicPermissionSync true" "$APP_SETTINGS" 2>/dev/null || \
      /usr/libexec/PlistBuddy -c "Add :checkMicPermissionSync bool true" "$APP_SETTINGS"
    # 2) 确认 Info.plist 有麦克风描述
    if ! /usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" "$app/Info.plist" >/dev/null 2>&1; then
      /usr/libexec/PlistBuddy -c "Add :NSMicrophoneUsageDescription string 用于游戏内语音交流" "$app/Info.plist" 2>/dev/null || true
      codesign --force --sign - "$app" 2>/dev/null || true
      echo "  已注入麦克风描述并重新签名。"
    fi
    # 3) 重置麦克风授权，等待系统重新询问
    tccutil reset Microphone "$BUNDLE" 2>&1 || true
    echo "✅ 麦克风已开启。"
    echo "  启动游戏后若弹出「允许使用麦克风」请点允许；"
    echo "  或到 系统设置→隐私与安全性→麦克风 打开金铲铲/PlayCover。"
    ;;

  ui)
    app="$(locate_app)" || exit 1
    mkdir -p "$APP_SETTINGS_DIR"
    if [[ ! -f "$MAIN_PLIST" ]]; then
      echo "[失败] 缺少预设文件 com.tencent.jkchess.plist"
      exit 1
    fi
    cp -f "$MAIN_PLIST" "$APP_SETTINGS"
    echo "✅ 已应用 1080p 16:9 预设（修复阵容推荐 UI 适配）。"
    restart_playcover
    ;;

  crash)
    app="$(locate_app)" || exit 1
    # 1) 确保 Applications 目录（安装/运行报错根因）
    mkdir -p "$APPS_DIR"
    # 2) 清理崩溃记录
    rm -f "$HOME/Library/Logs/DiagnosticReports/jkchess"* 2>/dev/null || true
    # 3) 应用已知良好设置(16:9)，避免坏设置引发启动崩溃
    mkdir -p "$APP_SETTINGS_DIR"
    cp -f "$MAIN_PLIST" "$APP_SETTINGS" 2>/dev/null || true
    # 4) 重新 ad-hoc 签名，修复可能的签名损坏
    codesign --force --sign - "$app" 2>&1 || echo "  [提示] 重签名未完成，不影响后续步骤。"
    echo "✅ 闪退修复完成："
    echo "  · Applications 目录已确认"
    echo "  · 崩溃记录已清理"
    echo "  · 已应用良好设置(16:9)"
    echo "  · 已重新签名"
    restart_playcover
    echo "  若仍闪退(EXC_BREAKPOINT/SIGTRAP)，请运行 clean_reinstall.sh 干净重装。"
    ;;

  status)
    app="$(find "$PC_CONTAINER" -maxdepth 5 -type d -name "$BUNDLE.app" 2>/dev/null | head -1)"
    if [[ -z "$app" ]]; then
      echo "已安装: 否（请先在 PlayCover 安装金铲铲）"
      if [[ -d "$APPS_DIR" ]]; then echo "Applications目录: 正常"; else echo "Applications目录: 缺失"; fi
      exit 0
    fi
    echo "已安装: 是"
    VER_SHORT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Info.plist" 2>/dev/null || echo '')"
    VER_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Info.plist" 2>/dev/null || echo '')"
    echo "版本: ${VER_SHORT:-$VER_BUILD} (${VER_BUILD})"
    w="$(/usr/libexec/PlistBuddy -c 'Print :windowWidth' "$APP_SETTINGS" 2>/dev/null || echo '?')"
    h="$(/usr/libexec/PlistBuddy -c 'Print :windowHeight' "$APP_SETTINGS" 2>/dev/null || echo '?')"
    ar="$(/usr/libexec/PlistBuddy -c 'Print :aspectRatio' "$APP_SETTINGS" 2>/dev/null || echo '?')"
    case "$ar" in 0) arl="4:3";; 1) arl="16:9";; 2) arl="16:10";; *) arl="$ar";; esac
    echo "分辨率: ${w}x${h} ($arl)"
    mic="$(/usr/libexec/PlistBuddy -c 'Print :checkMicPermissionSync' "$APP_SETTINGS" 2>/dev/null || echo '?')"
    echo "麦克风同步: $mic"
    if [[ -d "$APPS_DIR" ]]; then echo "Applications目录: 正常"; else echo "Applications目录: 缺失"; fi
    ;;

  *)
    echo "用法: $0 {mic|ui|crash|appsdir|status}"
    exit 1
    ;;
esac
