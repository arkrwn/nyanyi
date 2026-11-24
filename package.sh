#!/bin/bash
set -e

if [ "$(uname -s)" != "Darwin" ]; then
    echo "Error: Nyanyi is a native macOS application (SwiftUI + AppKit) and must be built on macOS."
    echo "Current OS detected: $(uname -s) ($(hostname))."
    echo "To build on Linux/server, push to GitHub Actions (macos-14 runner) or run ./package.sh on your Mac."
    exit 1
fi

if ! command -v swift >/dev/null 2>&1; then
    echo "Error: 'swift' toolchain not found. Install Xcode Command Line Tools with: xcode-select --install"
    exit 1
fi

APP_NAME="Nyanyi"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
DMG_NAME="${APP_NAME}.dmg"

echo "Building release binary..."
swift build -c release

echo "Creating app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Info.plist "${APP_BUNDLE}/Contents/Info.plist"
cp AppIcon.icns "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

# Ad-hoc code sign so macOS Gatekeeper works smoothly on local builds
codesign --force --sign - "${APP_BUNDLE}"

echo "App bundle created: ${APP_BUNDLE}"

# Create DMG if requested
if [ "$1" = "--dmg" ]; then
    echo "Creating DMG..."
    rm -f "${DMG_NAME}"

    STAGING_DIR=$(mktemp -d)
    cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"
    ln -s /Applications "${STAGING_DIR}/Applications"

    hdiutil create -volname "${APP_NAME}" \
        -srcfolder "${STAGING_DIR}" \
        -ov -format UDZO \
        "${DMG_NAME}"

    rm -rf "${STAGING_DIR}"
    echo "DMG created: ${DMG_NAME}"
fi

echo "Done! You can now:"
echo "  open ${APP_BUNDLE}              # Run directly"
echo "  cp -R ${APP_BUNDLE} /Applications/  # Install to Applications"
echo "  ./package.sh --dmg              # Also create a distributable DMG"
