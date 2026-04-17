#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="MarkdownViewer"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"

rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

echo "Compiling Swift sources..."
swiftc \
    -O \
    -target arm64-apple-macos13.0 \
    -framework SwiftUI \
    -framework WebKit \
    -framework AppKit \
    -parse-as-library \
    -o "$MACOS_DIR/$APP_NAME" \
    Sources/*.swift

echo "Generating app icon..."
ICONSET="$BUILD_DIR/AppIcon.iconset"
swift Scripts/make-icon.swift "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$RES_DIR/AppIcon.icns"

echo "Copying resources..."
cp Info.plist "$CONTENTS/Info.plist"
cp Resources/viewer.html "$RES_DIR/viewer.html"

echo "Ad-hoc signing..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "Built: $APP_BUNDLE"
echo ""
echo "Run with:   open $APP_BUNDLE"
echo "Install:    cp -R $APP_BUNDLE /Applications/"
