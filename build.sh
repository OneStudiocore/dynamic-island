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
cp assets/preview-wallpaper.png "$APP_DIR/Contents/Resources/preview-wallpaper.png"
cp -R assets/logos "$APP_DIR/Contents/Resources/logos"

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
