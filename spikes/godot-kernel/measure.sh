#!/bin/sh
# Runs the spike's live measurements, silently, one after another, and
# prints what each found: chords struck as soon as possible, chords struck a
# lead ahead (the default), and 32 and 64 held Supersaw voices.
#   measure.sh [chunk_frames latency_ms]
# sets Godot's mix chunk (`audio/driver/mix_buffer_frames`, which only the
# patched engine in engine/ reads) and output latency for the run, and puts
# them back after. GODOT names the Godot to run.
set -e
cd "$(dirname "$0")/project"
godot="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
cp project.godot project.godot.orig
trap 'mv project.godot.orig project.godot' EXIT
if [ -n "$1" ]; then
    sed -i '' '/^driver\/mix_buffer_frames=/d; /^driver\/output_latency=/d' project.godot
    printf '%s\n' "/^\[audio\]/a" "driver/mix_buffer_frames=$1" "driver/output_latency=$2" . w q | ed -s project.godot
    echo "== chunk $1 frames, output latency $2 ms"
fi
for args in "--asap" "" "--sound superSaw --voices 32 --hold" "--sound superSaw --voices 64 --hold"; do
    echo "== ${args:-four-note chords struck a lead ahead}"
    # shellcheck disable=SC2086
    "$godot" --path . -- --measure $args 2>&1 | grep -E "Mix rate|Since|Strike|ERROR|leak"
done
