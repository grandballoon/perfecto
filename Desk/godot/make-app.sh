#!/bin/sh
# Builds Perfecto Desk.app: the patched Godot and a copy of the project in one
# bundle, so the app keeps playing this version whatever the checkout does next.
# Goes to ~/Applications, or the directory given.
set -eu
cd "$(dirname "$0")"

destination="${1:-$HOME/Applications}"
godot="$PWD/engine/godot/bin/godot.macos.editor.arm64"
if [ ! -x "$godot" ]; then
    echo "No patched Godot at $godot: build it as the README's \"A smaller mix chunk\" says." >&2
    exit 1
fi

scons -C extension platform=macos arch=arm64 target=template_release -j8

work="$(mktemp -d "${TMPDIR:-/tmp}/perfecto-desk-app.XXXXXX")"
trap 'rm -rf "$work"' EXIT
app="$work/Perfecto Desk.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

cp "$godot" "$app/Contents/MacOS/godot"
cp -R project "$app/Contents/Resources/project"
# The measuring scenes and the editor's own state are not part of the app.
rm -rf "$app/Contents/Resources/project/measure" "$app/Contents/Resources/project/.godot/editor"
install_name_tool -id @loader_path/libperfecto.macos.template_release.arm64.dylib \
    "$app/Contents/Resources/project/bin/libperfecto.macos.template_release.arm64.dylib"

cat > "$app/Contents/MacOS/Perfecto Desk" <<'LAUNCH'
#!/bin/sh
here="$(cd "$(dirname "$0")" && pwd)"
exec "$here/godot" --path "$here/../Resources/project" "$@"
LAUNCH
chmod +x "$app/Contents/MacOS/Perfecto Desk"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Perfecto Desk</string>
    <key>CFBundleDisplayName</key><string>Perfecto Desk</string>
    <key>CFBundleIdentifier</key><string>app.perfecto.desk</string>
    <key>CFBundleExecutable</key><string>Perfecto Desk</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>GCSupportsControllerUserInteraction</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$app/Contents/Resources/project/bin/libperfecto.macos.template_release.arm64.dylib"
codesign --force --sign - "$app/Contents/MacOS/godot"
codesign --force --sign - "$app"

mkdir -p "$destination"
rm -rf "$destination/Perfecto Desk.app"
mv "$app" "$destination/"
echo "$destination/Perfecto Desk.app"
