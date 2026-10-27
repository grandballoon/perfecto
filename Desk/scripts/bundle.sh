#!/bin/sh
# Builds Perfecto Desk and wraps it as an app: Desk/build/Perfecto Desk.app.
# A bundle is what the system gives game controllers and a Dock icon to;
# `swift run PerfectoDesk` runs the same app without one.
set -eu
cd "$(dirname "$0")/.."

configuration="${1:-release}"
swift build -c "$configuration" --product PerfectoDesk
binary="$(swift build -c "$configuration" --show-bin-path)/PerfectoDesk"

app="build/Perfecto Desk.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/PerfectoDesk"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Perfecto Desk</string>
    <key>CFBundleDisplayName</key><string>Perfecto Desk</string>
    <key>CFBundleIdentifier</key><string>com.perfecto.desk</string>
    <key>CFBundleExecutable</key><string>PerfectoDesk</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
    <key>GCSupportsControllerUserInteraction</key><true/>
    <key>GCSupportedGameControllers</key>
    <array><dict><key>ProfileName</key><string>ExtendedGamepad</string></dict></array>
</dict>
</plist>
PLIST
codesign --force --sign - "$app"
echo "$app"
