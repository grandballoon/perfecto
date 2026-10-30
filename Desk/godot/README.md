# Perfecto Desk in Godot

The desk, played from a game controller, as a Godot 4 app: the canonical desktop desk, for the Mac now and the Steam Deck and consoles after (`docs/desk-engine-and-audio.md`).
It plays the same layouts as the Mac desk did (`../README.md` says how each is played) on the same cores: the C++ theory core (`Perfecto/Sources/PerfectoTheory`), the C++ desk core (`Desk/Sources/PerfectoDeskCore`) and the audio kernel (`Perfecto/Sources/PerfectoKernel`), each compiled from where it lives.

## How it is built

```
project/desk/desk.gd ── step() each frame ──→ PerfectoDesk (C++)
   draws scene() ←─────────────────────────────   │  reads the controller and the keyboard (Godot's Input)
   saves files, shows notices ←── what is left ──  │  steps perfecto::desk::Studio (the desk, the drums and the timeline): a frame in, effects out
                                                   ├─→ DeskVoices, DrumVoices → PerfectoStream → the kernel, on Godot's mixing thread
                                                   ├─→ TimelineVoices: the timeline's playback, each note on its own frame
                                                   ├─→ DeskMidi: the "Perfecto Desk" MIDI source
                                                   └─→ rumble on the controller's motors
```

- **Every decision is the core's.**
  What the screen shows is a value the desk core makes (`scene.hpp`: the layouts, each layout's stage as panels of items, the hand, the favorites, the menu), and what the mouse can do is an `Action` it performs, both tested by equality in `Desk/Tests/PerfectoDeskCoreTests/scene_tests.cpp`.
- **The extension** (`extension/src`) is the imperative shell in C++: `PerfectoDesk` holds the desk, the drums and the timeline (`Studio`) and plays their effects, `DeskVoices` keeps each line's notes on the kernel, `DrumVoices` strikes the drums there, `TimelineVoices` keeps each of the timeline's tracks, `DeskMidi` sends the desk's notes and the drums as MIDI, and `scene_variant` hands the scene to the scripts as Godot values.
- **The drums are recordings made in code** (`Desk/Sources/PerfectoDrumKit`), rendered when the desk is set up and loaded into the kernel's four captures before the stream plays, and each drum is a sampled patch playing one of them.
  The core gives every hit up to 50 ms ahead with the moment it sounds, and `DrumVoices` places it on that moment's frame, so the beat keeps time however unevenly the desk is stepped.
- **The scripts only draw** (`project/desk`): `desk.gd` steps the desk, draws everything around the stage and takes the mouse, `stage.gd` draws a stage's panels from their items, `timeline_view.gd` the timeline's bar, and `paint.gd` has the colors, light and dark, the fonts and the shapes.
- **Notes are struck a lead ahead** (the longest render seen and a millisecond), so every press is equally late.
- **The desk is stepped once a frame**, and the project runs at up to 250 frames a second with vsync off, as the Mac desk stepped at 250 Hz: a frame is how late a press can be read.

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
Stock Godot (`Godot --path project`) also runs it, at its own 512 frames.

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path project -- --quit-after-frames 300
```

starts it without a window and quits it after 300 frames, the way closing the window does, to check that it starts and quits cleanly.
Godot's own `--quit-after` ends the main loop before the audio server can let go of the playback, which then leaks at exit (`extension/src/perfecto_stream.h` says why).

It plays from the first controller Godot knows (an Xbox One or Series controller, over Bluetooth or USB, and most others) and from the computer keyboard, always, as `../README.md` lays it out.
It opens on Face Chords, whose face buttons play the chords `project/desk/face_chords.json` gives (`../README.md` says how).
Notes go to the kernel's sound, to MIDI from the source **Perfecto Desk**, or both (Menu › Output), and a saved arrangement goes to Music › Perfecto Desk.

Not yet as the Mac desk had it:

- The settings, the layout and the favorites are not kept between launches.
- A wired Xbox 360 controller is not read: macOS has no driver for it, and the Mac desk read its USB reports itself (`Xbox360USB.swift`), which the extension has still to do.
- MIDI goes out on the Mac only; on Linux it is still to write (ALSA).

## Measuring

The kernel spike that chose Godot is kept as a scene of its own, `project/measure`: chords from a controller or the keyboard on the kernel, and what the mixing thread is doing, measured as it plays.
Its face buttons are read from `project/measure/pad.json`, by the reader Face Chords uses (`project/desk/face_buttons.gd`): a degree for each of A, B, X and Y without LT and with it held; pulling or letting go of LT while a button holds a chord switches it to that button's chord in the other layer.

```bash
./play.sh res://measure/measure.tscn
```

plays it.

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path project --script res://measure/bench.gd
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
