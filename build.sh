#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
APP_NAME="灵动岛"
EXEC_NAME="DynamicIsland"
APP_DIR="$APP_NAME.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp src/Info.plist "$APP_DIR/Contents/Info.plist"

# 二进制素材是可选的：仓库里没带壁纸和位图 logo 时，跳过拷贝也能编出可用 App
if [ -f assets/preview-wallpaper.png ]; then
  cp assets/preview-wallpaper.png "$APP_DIR/Contents/Resources/preview-wallpaper.png"
else
  echo "==> 跳过 preview-wallpaper.png（未提供，设置页预览会退回渐变底）"
fi

if [ -d assets/logos ]; then
  cp -R assets/logos "$APP_DIR/Contents/Resources/logos"
else
  echo "==> 跳过 logos（未提供，厂商图标会退回 SF Symbol）"
fi

# 图标是代码画的：每次构建重新渲染 iconset → icns，不往仓库塞二进制
echo "==> 绘制 App 图标"
mkdir -p build
if swiftc -O Tools/make-icon.swift -o build/make-icon \
   && ./build/make-icon build \
   && iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns; then
  cp build/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
else
  echo "==> 图标生成失败，跳过（App 会用系统默认图标）"
fi

echo "==> 编译 Swift 源码"
swiftc \
  -O \
  -target arm64-apple-macos26.0 \
  -o "$APP_DIR/Contents/MacOS/$EXEC_NAME" \
  src/*.swift src/Services/*.swift

echo "==> 生成 PkgInfo"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

echo "==> 临时签名"
codesign --force --sign - --timestamp=none "$APP_DIR" >/dev/null 2>&1 || true

echo "==> 完成: $APP_DIR"
