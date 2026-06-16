#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="Copilot Notify"
BUNDLE_NAME="CopilotNotify.app"
BUILD_DIR=".build/release"
DIST_DIR="dist"
INSTALL_DIR="$HOME/Applications"

echo "Building CopilotNotify (release)..."
swift build -c release 2>&1

echo "Creating app bundle..."
rm -rf "$DIST_DIR/$BUNDLE_NAME"
mkdir -p "$DIST_DIR/$BUNDLE_NAME/Contents/MacOS"
mkdir -p "$DIST_DIR/$BUNDLE_NAME/Contents/Resources"

cp "$BUILD_DIR/CopilotNotify" "$DIST_DIR/$BUNDLE_NAME/Contents/MacOS/"
cp Resources/Info.plist "$DIST_DIR/$BUNDLE_NAME/Contents/"
if [ -f Resources/Icons/AppIcon.icns ]; then
    cp Resources/Icons/AppIcon.icns "$DIST_DIR/$BUNDLE_NAME/Contents/Resources/"
fi

echo "App bundle created at: $DIST_DIR/$BUNDLE_NAME"

if [[ "${1:-}" == "--install" ]]; then
    echo "Installing to $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"
    rm -rf "$INSTALL_DIR/$BUNDLE_NAME"
    cp -R "$DIST_DIR/$BUNDLE_NAME" "$INSTALL_DIR/"
    echo "Installed! Run with: open '$INSTALL_DIR/$BUNDLE_NAME'"
fi

echo "Done."
echo ""
echo "To run (debug):  swift build && .build/debug/CopilotNotify"
echo "To run (bundle): open $DIST_DIR/$BUNDLE_NAME"
echo "To install:      ./build.sh --install"
