#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
BUILD_ROOT="$HOME/Library/Caches/KeiraPrompter/build"
APP="$BUILD_ROOT/Keira Prompter.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
ARCH="$(uname -m)"
swiftc -target "$ARCH-apple-macosx14.0" -parse-as-library -swift-version 5 -O -framework AppKit -framework SwiftUI -framework AVFoundation -framework Speech KeiraPrompter.swift -o "$APP/Contents/MacOS/KeiraPrompter"
cp Info.plist "$APP/Contents/Info.plist"
swift Icon.swift "$BUILD_ROOT/AppIcon.iconset"
iconutil -c icns "$BUILD_ROOT/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier ai.mizi.keira-prompter "$APP"
printf 'Built: %s\n' "$APP"
