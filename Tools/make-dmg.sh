#!/bin/bash
# 打一个能直接拖进「应用程序」的 DMG
# 用法：./Tools/make-dmg.sh [版本号，默认 1.0]
set -euo pipefail

cd "$(dirname "$0")/.."

APP="灵动岛.app"
VERSION="${1:-1.0}"
DMG="dist/灵动岛-${VERSION}.dmg"
STAGE="dist/stage"

if [ ! -d "$APP" ]; then
  echo "==> 没找到 $APP，先跑 ./build.sh"
  exit 1
fi

rm -rf dist
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> 打包 DMG"
hdiutil create \
  -volname "灵动岛" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG" >/dev/null

rm -rf "$STAGE"
echo "==> 完成: ${DMG}（$(du -h "$DMG" | cut -f1)）"
