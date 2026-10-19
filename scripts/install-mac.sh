#!/bin/bash
# Builds the Mac app (Mac Catalyst) as the code is now, for release, and
# puts it in /Applications, in place of the copy there. That copy is the
# one to keep in the Dock: it stays as it is until this is run again.
#
#   scripts/install-mac.sh
#
# scripts/run-mac.sh is the one for trying a change; it leaves this copy alone
# on disk, though it closes it if it is running.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p build
log="build/install-mac.log"

# Its own derived data: a build that shares Xcode's waits on an open Xcode.
echo "Building…"
if ! xcodebuild build \
    -project Perfecto.xcodeproj -scheme Perfecto -configuration Release \
    -destination 'platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath build/DerivedDataMac > "$log" 2>&1; then
    grep -E "error:" "$log" >&2 || true
    echo "The build failed; see $log" >&2
    exit 1
fi

# The copy that is running has to be gone before it can be replaced.
if pkill -x Perfecto; then
    while pgrep -x Perfecto > /dev/null; do sleep 0.1; done
fi

built=build/DerivedDataMac/Build/Products/Release-maccatalyst/Perfecto.app
installed=/Applications/Perfecto.app
rm -rf "$installed"
ditto "$built" "$installed"
echo "Installed $installed"
