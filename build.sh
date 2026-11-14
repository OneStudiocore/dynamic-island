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
