# Spike: the kernel in Godot

Does Godot 4 host Perfecto's audio kernel well enough to be the desk's engine?
That is the question of step 1 in [docs/desk-engine-and-audio.md](../../docs/desk-engine-and-audio.md), and what was found is written up there (section 9).

The kernel is compiled from where it lives (`Perfecto/Sources/PerfectoKernel`), into a GDExtension that makes it a Godot `AudioStream`.
Godot's mixing thread calls the stream's playback, which renders the kernel straight into Godot's buffer, so no script ever runs on that thread.
Scripts send notes through the stream (`note_on`, `note_off`, `note_change`), which passes them to the kernel as timed events.

- `extension/`: the GDExtension (`PerfectoStream`, `PerfectoPlayback`), built with SCons on godot-cpp.
- `project/`: a Godot project with one screen that plays chords from a controller or the keyboard and shows what the mixing thread is doing, and a headless benchmark (`bench.gd`).
- `tools/dump-presets/`: writes every `SynthPreset` as the kernel takes it to `project/presets.json`, so the sounds stay defined once, in `PerfectoSound`.

## Building

Godot 4.5 or later and SCons (`brew install --cask godot`, `brew install scons`), then, from this folder:

```bash
git clone --depth 1 --branch godot-4.5-stable https://github.com/godotengine/godot-cpp extension/godot-cpp
```

```bash
scons -C extension platform=macos arch=arm64 target=template_release
```

```bash
swift run --package-path tools/dump-presets -c release dump-presets project/presets.json
```

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path project --import
```

On the Steam Deck or another Linux machine the second step is `scons -C extension platform=linux target=template_release`; `presets.json` is copied over, since the dump needs a Mac.

## Running

```bash
./play.sh
```

plays it with the patched Godot (see "A smaller mix chunk" below), at the 128-frame chunk and 3 ms output latency the project sets.
Stock Godot (`Godot --path project`) also runs it, at its own 512 frames, and says so on the screen.

- A, B, X and Y strike the chords in C that `project/pad.json` gives them: to start with, A is I with LT or without it, B, X and Y are IV, V and vii° without it, and with LT held they are ii, iii and vi.
  Pulling or letting go of LT while a button holds a chord switches it to that button's chord in the other layer (A's I goes on sounding), and lifting the button ends the chord.
- Z, X, C, V, B, N, M strike all seven, I to vii°, in the scale's order.
- LB and RB (or Q and E) change the sound.
- RT swells the held chord.
- The d-pad's up and down (or the arrows) change the volume 6 dB a step: Godot ramps a change of volume over one chunk, so this is where a short chunk would click.
- Back (or S) switches between striking a lead ahead, so every strike is equally late (the default), and striking as soon as possible, sooner on average but varying by up to a chunk.
- Start (or T) strikes chords by itself for twenty seconds and measures how long each waited for a render.

`pad.json` has a layer `"plain"` and a layer `"LT"`, each naming a degree (I, ii, iii, IV, V, vi, vii° or vii) for any of A, B, X and Y; a button a layer leaves out strikes nothing there.
It is read when the spike starts, and `-- --pad <file>` reads another in its place.
A file with anything wrong in it leaves the face buttons silent and says why on the screen.

The screen shows the mix rate, Godot's output buffer, each render's cost, and the strike-to-render wait.

## Measuring

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path project --script res://bench.gd
```

renders every sound offline at 0 to 64 voices and prints its cost.

```bash
./measure.sh
```

runs the live measurement silently: four-note chords struck as soon as possible and a lead ahead, then 32 and 64 held Supersaw voices.
It runs stock Godot unless `GODOT` names another; with a chunk and a latency given, it sets them for the run (below).

## A smaller mix chunk

Godot as shipped mixes 512 frames at a time, and nothing in a project changes that, so its output latency setting (`audio/driver/output_latency`) can only make the device's buffer smaller, not what Godot hands it.
`engine/mix-buffer-frames.patch` makes the chunk a project setting, `audio/driver/mix_buffer_frames`.
To build Godot with it (about eight minutes on an M2):

```bash
git clone --depth 1 --branch 4.7.2-stable https://github.com/godotengine/godot engine/godot
```

```bash
git -C engine/godot apply ../mix-buffer-frames.patch
```

```bash
scons -C engine/godot platform=macos arch=arm64 target=editor metal=yes vulkan=no opengl3=no accesskit=no
```

Then measure with it, giving the chunk in frames and the output latency in ms (which the Mac's driver rounds to a power of two in frames, so 3 ms is 128 frames and 6 ms is 256 at 44.1 kHz):

```bash
GODOT=$PWD/engine/godot/bin/godot.macos.editor.arm64 ./measure.sh 128 3
```

`./play.sh` plays it with that Godot at the chunk and latency under `[audio]` in `project/project.godot`.
