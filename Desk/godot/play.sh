#!/bin/sh
# Plays the desk with the patched Godot, at the mix chunk and output
# latency set under [audio] in project/project.godot (128 frames and 3 ms).
# Anything given is passed on, so `./play.sh res://measure/measure.tscn` plays the measuring scene.
set -e
cd "$(dirname "$0")"
godot="${GODOT:-$PWD/engine/godot/bin/godot.macos.editor.arm64}"
if [ ! -x "$godot" ]; then
    echo "No patched Godot at $godot: build it as the README's \"A smaller mix chunk\" says." >&2
    exit 1
fi
exec "$godot" --path project "$@"
