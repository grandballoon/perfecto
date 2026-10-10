#!/bin/bash
# Builds the Mac app (Mac Catalyst) as the code is now and opens it, in
# place of any copy already running.
#
#   scripts/run-mac.sh
#
# Only what changed is rebuilt, so after the first time it takes seconds.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p build
log="build/run-mac.log"

# Its own derived data: a build that shares Xcode's waits on an open Xcode.
echo "Building…"
if ! xcodebuild build \
    -project Perfecto.xcodeproj -scheme Perfecto \
    -destination 'platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath build/DerivedDataMac > "$log" 2>&1; then
    grep -E "error:" "$log" >&2 || true
    echo "The build failed; see $log" >&2
    exit 1
fi

# The copy that is running has to be gone before the new one can open.
if pkill -x Perfecto; then
    while pgrep -x Perfecto > /dev/null; do sleep 0.1; done
fi
# The system can take a moment more to notice it has gone.
app=build/DerivedDataMac/Build/Products/Debug-maccatalyst/Perfecto.app
for attempt in 1 2 3 4 5; do
    if open "$app" 2> /dev/null; then exit 0; fi
    sleep 0.5
done
open "$app"
