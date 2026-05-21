#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building Keyboard Switcher..."
swift build

# Kill running instance
pkill -f KeyboardSwitcher 2>/dev/null && sleep 1 || true

APP_DIR="Keyboard Switcher.app"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp .build/debug/KeyboardSwitcher "$APP_DIR/Contents/MacOS/KeyboardSwitcher"
cp Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/english_words.txt "$APP_DIR/Contents/Resources/"
cp Resources/ukrainian_words.txt "$APP_DIR/Contents/Resources/"

# Install to /Applications (clean first)
rm -rf "/Applications/Keyboard Switcher.app"
cp -R "$APP_DIR" "/Applications/Keyboard Switcher.app"

# Remove quarantine and ad-hoc sign
xattr -cr "/Applications/Keyboard Switcher.app"
codesign --force --deep --sign - "/Applications/Keyboard Switcher.app"

echo "Installed to /Applications/Keyboard Switcher.app"
echo "Launching..."
open "/Applications/Keyboard Switcher.app"
