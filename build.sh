#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="build/Splash Local.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns telemetry.js "$APP/Contents/Resources/"
xcrun swiftc main.swift -o "$APP/Contents/MacOS/SplashLocal" -framework Cocoa -framework WebKit
codesign --force --sign - "$APP"
echo "Built: $PWD/$APP"
