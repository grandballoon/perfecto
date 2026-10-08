#!/bin/bash
# Exports the UI spec: every screen of the app, drawn from its own views as
# shapes and text (not screenshots), as PDF and as SVG for a design tool.
#
#   scripts/export-ui-spec.sh [folder]        default: build/ui-spec
#
# The screens and states drawn are listed in Tests/UISpec/SpecScreen.swift.
# The drawing is done by the app's tests on a simulator (UI_SPEC_DEVICE, by
# default "iPhone 17"), and the SVG files are made from the PDFs by MuPDF
# (brew install mupdf-tools).
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p "${1:-build/ui-spec}"
out="$(cd "${1:-build/ui-spec}" && pwd)"
device="${UI_SPEC_DEVICE:-iPhone 17}"

command -v mutool >/dev/null || { echo "mutool not found: brew install mupdf-tools" >&2; exit 1; }

# Its own derived data: a build that shares Xcode's waits on an open Xcode.
echo "Drawing the screens on ${device}…"
if ! TEST_RUNNER_UI_SPEC_DIR="$out" xcodebuild test \
    -project Perfecto.xcodeproj -scheme Perfecto \
    -destination "platform=iOS Simulator,name=$device" \
    -derivedDataPath build/DerivedData \
    -only-testing:PerfectoTests/UISpecExportTests > "$out/xcodebuild.log" 2>&1; then
    echo "The drawing failed; see $out/xcodebuild.log" >&2
    exit 1
fi

# A PDF names its fonts as it embeds them (AAAAAB+.SFUIMono-Semibold, or
# .SFUI-Regular_wdth_opsz… for the system font, and every weight above
# regular as "bold"); a design tool wants the family as installed and the
# weight as a number.
rm -rf "$out/svg"
mkdir -p "$out/svg"
for pdf in "$out"/pdf/*.pdf; do
    name="$(basename "$pdf" .pdf)"
    mutool convert -F svg -O text=text -o "$out/svg/$name-.svg" "$pdf"
    sed -E \
        -e 's/ font-weight="bold"//g' \
        -e 's/font-family="[A-Z]{6}\+\.?([A-Za-z]+)-([A-Za-z]+)[^"]*"/font-family="\1" font-weight="\2"/g' \
        -e 's/font-family="SFUIMono"/font-family="SF Mono"/g' \
        -e 's/font-family="SFUI"/font-family="SF Pro"/g' \
        -e 's/font-weight="Light"/font-weight="300"/g' \
        -e 's/font-weight="Regular"/font-weight="400"/g' \
        -e 's/font-weight="Medium"/font-weight="500"/g' \
        -e 's/font-weight="Semibold"/font-weight="600"/g' \
        -e 's/font-weight="Bold"/font-weight="700"/g' \
        -e 's/font-weight="Heavy"/font-weight="800"/g' \
        "$out/svg/$name-1.svg" > "$out/svg/$name.svg"
    rm "$out/svg/$name-1.svg"
done

echo "$(ls "$out/svg" | wc -l | tr -d ' ') drawings in $out (svg/, pdf/, index.md)"
