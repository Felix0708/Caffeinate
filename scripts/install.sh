#!/bin/bash
set -e

# Caffeine One-Click Installer for macOS

cd "$(dirname "$0")/.."

echo "========================================"
echo "☕️ Caffeine Installer for macOS"
echo "========================================"

# 1. Build the latest app bundle
echo "🔨 [1/3] Building the latest Caffeine release..."
./scripts/build_app.sh

# 2. Stop running instance if any
echo "🛑 [2/3] Closing any running Caffeine..."
killall Caffeine 2>/dev/null || true
sleep 1

# 3. Determine target install directory
TARGET_DIR="/Applications"
if [ ! -w "$TARGET_DIR" ]; then
    TARGET_DIR="$HOME/Applications"
    mkdir -p "$TARGET_DIR"
fi

echo "🚀 [3/3] Installing to $TARGET_DIR/Caffeine.app..."
rm -rf "$TARGET_DIR/Caffeine.app"
cp -R "Caffeine.app" "$TARGET_DIR/"
xattr -cr "$TARGET_DIR/Caffeine.app" 2>/dev/null || true

echo ""
echo "========================================"
echo "🎉 설치가 완료되었습니다!"
echo "========================================"
echo "설치 위치: $TARGET_DIR/Caffeine.app"
echo ""
echo "이제 다음과 같이 사용하실 수 있습니다:"
echo "1. 터미널에서 실행: open \"$TARGET_DIR/Caffeine.app\""
echo "2. Spotlight / Launchpad에서 'Caffeine' 검색 후 실행"
echo "3. 메뉴바에서 커피잔 아이콘 클릭 후 '🚀 컴퓨터 켤 때 자동 시작' 체크"
echo ""
