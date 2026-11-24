#!/bin/bash
set -e

REPO="https://github.com/arkrwn/nyanyi.git"
APP_NAME="Nyanyi"
INSTALL_DIR="/Applications"
TMP_DIR=$(mktemp -d)

cleanup() { rm -rf "${TMP_DIR}"; }
trap cleanup EXIT

echo "Installing ${APP_NAME}..."

# Check for Swift toolchain
if ! command -v swift &> /dev/null; then
    echo "Xcode Command Line Tools are required. Installing..."
    xcode-select --install
    echo "Please re-run this script after installation completes."
    exit 1
fi

echo "Downloading source..."
git clone --depth 1 "${REPO}" "${TMP_DIR}/${APP_NAME}" 2>/dev/null

echo "Building (this may take a moment)..."
cd "${TMP_DIR}/${APP_NAME}"
swift build -c release 2>&1 | tail -1

echo "Creating app bundle..."
APP_BUNDLE="${TMP_DIR}/${APP_NAME}.app"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
cp ".build/release/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp Info.plist "${APP_BUNDLE}/Contents/Info.plist"
cp AppIcon.icns "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
codesign --force --sign - "${APP_BUNDLE}" 2>/dev/null

# Kill existing instance if running
killall "${APP_NAME}" 2>/dev/null || true

# Move to /Applications
echo "Installing to ${INSTALL_DIR}..."
rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
cp -R "${APP_BUNDLE}" "${INSTALL_DIR}/${APP_NAME}.app"

echo "Launching ${APP_NAME}..."
open "${INSTALL_DIR}/${APP_NAME}.app"

echo "Done! ${APP_NAME} is now in your Applications folder and running in the menu bar."
