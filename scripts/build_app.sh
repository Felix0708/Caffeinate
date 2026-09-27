#!/bin/bash
set -e

# Caffeine macOS App Bundle Builder
# Compiles with native swiftc and packages into Caffeine.app

cd "$(dirname "$0")/.."

APP_NAME="Caffeine"
BUNDLE_DIR="$APP_NAME.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BUILD_DIR=".build"
CACHE_DIR=$(mktemp -d)
trap 'rm -rf "$CACHE_DIR"' EXIT

mkdir -p "$BUILD_DIR" "$CACHE_DIR"

echo "☕️ [1/4] Compiling $APP_NAME for macOS (arm64)..."
swiftc \
    -O \
    -target arm64-apple-macos13.0 \
    -sdk "$(xcrun --show-sdk-path)" \
    -module-cache-path "$CACHE_DIR" \
    -Xcc -fmodules-cache-path="$CACHE_DIR" \
    Sources/Caffeine/*.swift \
    -o "$BUILD_DIR/$APP_NAME"

echo "📦 [2/4] Assembling $BUNDLE_DIR with Coffee AppIcon..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"

# Copy Info.plist
cp "Info.plist" "$CONTENTS_DIR/Info.plist"

# Copy AppIcon.icns
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

echo "🔐 [3/4] Ad-hoc code signing..."
codesign --force --deep --sign - "$BUNDLE_DIR"

echo "✅ [4/4] Successfully created $BUNDLE_DIR!"
echo ""
echo "To run the app:"
echo "  open $BUNDLE_DIR"
echo ""
echo "Or install to Applications:"
echo "  ./scripts/install.sh"
