# The desk in a game engine: audio options and a visualizer

> **Status (2026-10-29): exploration.** Nothing here is decided or built.
> It asks what it would take to move Perfecto Desk (`Desk/`) off SwiftPM and AppKit into a game engine that reaches Windows, Linux and the Steam Deck, and the Nintendo Switch and Switch 2, without giving up the sound.
> CPU figures are estimates scaled from the estimates in [audio-engine-spec.md](audio-engine-spec.md) section 5, not measurements; section 7 says what to measure first.

## 1. The short answer

The engine should not make our sound.
We already have the hard part: the kernel (`Perfecto/Sources/PerfectoKernel`) is about 2,700 lines of portable C++17 behind a C interface, with no Apple dependency, no allocation, lock or wait in its render call, and every event on its exact frame.
What an engine has to offer the audio is only two things: a real-time callback on a thread of its own that asks for the next block of samples, and a way onto each platform's audio device, including the consoles', whose APIs are under NDA.
Measured that way, the engines sort themselves quickly:

- **Godot 4, with the kernel in a GDExtension, is the recommendation.**
  It is MIT-licensed, it gives a C++ audio stream a real callback on its mixing thread, it has a working console route (W4 Games' ports, with Switch 2 in beta since October 2025, and a free Switch port for licensed developers), it handles controllers well, and its Movie Maker mode renders frames and audio offline, which is exactly what the visualizer's export needs.
- **LÖVE is possible but makes us write the hard platform work ourselves.**
  It has no audio callback, only buffers pushed from Lua (`QueueableSource`), so to keep the kernel's timing we would open the audio device ourselves from a native module, and on a console that means writing our own backend against Nintendo's audio API.
  Balatro shows LÖVE games can reach Switch, but through a porting partner, not through anything LÖVE provides.
- **Unity, Unreal, Defold and a hand-built SDL3 app** are each viable for some reason and second-best overall; section 4 says why.

The larger decision is not the engine but the language of the desk's logic.
`DeskCore` (about 4,100 lines) and `MusicTheoryCore` are Swift, and there is no Swift toolchain for the Switch.
Whatever engine we choose, the desk's functional core has to be rewritten in something every target compiles; section 5 recommends C++, beside the kernel.

## 2. What "high-quality audio" means here

Quality in this design is two separate things, and only one of them scales with the hardware.

**Per-voice quality does not have to drop anywhere.**
The kernel computes in 32-bit float at 48 kHz, with band-limited wavetables, smoothed controls, a real voice allocator and a look-ahead limiter.
A note on the Switch can be bit-for-bit the note on a Mac.
The output stages differ (the Switch's DAC and HDMI path, the Deck's headphone jack), but none of them is the bottleneck for a synth.

**Density is what scales**: how many voices, how many unison copies each, the oversampled ladder filter, the size of the reverb, the sampled instruments.
So the target is *the same sound everywhere, with fewer notes at once on the smallest machine*, and that is achievable.
"Studio quality on a Switch" is a fair aim for a single layer played live; six dense layers with seven-copy unison is not.

### 2.1 Quality tiers

| | Mac / Windows / Linux | Steam Deck | Switch 2 | Switch (original) |
|---|---|---|---|---|
| CPU for audio | one modern core | one Zen 2 core (of 4) | one Cortex-A78C core (of 8) | one Cortex-A57 core at about 1 GHz (of 3 for games) |
| Sample rate, block | 48 kHz, 256 or less | 48 kHz, 256 | 48 kHz, the system's | 48 kHz, the system's (about 5 ms) |
| Voices | 64 | 64 | 64 | 24 to 32 |
| Unison copies | up to 7 | up to 7 | up to 7 | up to 3 |
| Ladder filter (oversampled) | on where patches ask | on where patches ask | on, measured first | off: the state-variable filter stands in |
| Reverb | full | full | full | a shorter, cheaper network |
| Sampled instruments | streamed, full sets | streamed, full sets | streamed, trimmed sets | one small piano and guitar, in memory |
| Mic: sampling, vocoder | yes | yes (built-in mic) | where a mic is attached | no built-in mic; off |
| MIDI out | yes | yes | no | no |

The tier should be a property of the kernel, not of the patches: `perfecto_kernel_prepare` would take a tier, and the kernel would substitute the cheaper filter and caps voices and unison under it, so a preset is written once.
The phone could take the same tiers for its oldest devices.

### 2.2 The Switch 1 budget, roughly

The audio engine spec estimates 15 to 25 ns per voice per frame on an A12.
An A57 at about 1 GHz is perhaps four to six times slower per thread on this kind of code, so 60 to 150 ns per voice per frame.
At 48 kHz, 32 voices would take 10 to 23% of a core before the effects; 64 voices would take 20 to 45%, which leaves too little margin for a game that also draws.
The voice loop is plain float arithmetic over fixed arrays, so NEON vectorisation (four voices or four frames at a time) is where the Switch's headroom comes from, and is worth doing on every ARM target, the phone included.
These numbers are guesses until section 7's measurements replace them.

## 3. How an engine should host the kernel

Every option below is judged against one shape, which is the one the phone already has:

```
 game thread (engine frame)              audio thread (device callback)
 ───────────────────────────             ──────────────────────────────
 controllers → DeskCore (pure)            perfecto_kernel_render(block)
   → effects as data                           ▲            │
   → shell: perfecto_kernel_send ──events──────┘            ├──→ device out
                                                            └──→ analysis ring ──→ visualizer
```

- **Events cross by `perfecto_kernel_send`**, stamped with the kernel frame they take effect on.
  The engine's frame rate (60 Hz, or 30 on a struggling Switch) must never be what times a note: a press read at frame *n* is stamped "now plus the lead", exactly as `NotePlayer` stamps the phone's notes.
- **The render call runs on the engine's audio thread** with no script on that thread.
  This rules out every route where Lua, GDScript or C# fills audio buffers.
- **The kernel's clock is the master clock.**
  The arrangement, the arpeggiator and the visualizer all read musical time from the kernel's frame count (`perfecto_kernel_time`), corrected by the output latency, never from the engine's delta time.
- **One output ring** carries the rendered blocks out of the callback, lock-free and preallocated, for the visualizer's analysis and for recording (section 6.2).

## 4. The options

### 4.1 Godot 4 (recommended)

**Audio.** A GDExtension in C++ can define its own `AudioStream` whose playback's `_mix` is called on Godot's mixing thread with a buffer to fill.
That is a true callback, so the kernel renders there directly, with Godot's own mixer adding nothing but a final sum.
The spike found the catch (section 9): Godot mixes in fixed chunks of 512 frames, whatever the output latency is set to, so as shipped its latency floor is higher than the phone's; a three-line patch makes the chunk a setting, and at 128 frames it is lower.
On a console, Godot's port owns the device, so we write no platform audio code at all.
**Consoles.** W4 Games (founded by Godot's lead developers) sells console ports for Switch, PlayStation and Xbox, with Switch 2 in beta since October 2025; a free Switch port also exists for authorised Nintendo developers.
Either way the port is closed and under NDA, as every console layer is.
**Visuals.** A full 2D and 3D renderer with a shader language, a compositor, particles, and Movie Maker mode, which renders a fixed frame rate without real time passing and writes video and WAV: the export path of section 6 nearly for free.
**Input.** Good controller support across Xbox, PlayStation, Switch Pro and Joy-Con, and the Deck's own controls, with rumble.
**Open source.** MIT, so our own code can be published, with the console layer kept in a private repository as it must be anyway.
**Costs.** The UI is Godot's, not SwiftUI, so the desk's screens are redrawn; GDScript is fine for the shell, but logic belongs in the C++ core so it can be tested by equality.

### 4.2 LÖVE

**Audio.** LÖVE's audio is OpenAL Soft.
It offers sources and, since 11.0, a `QueueableSource` that plays buffers pushed from Lua; there is no callback.
Feeding the kernel that way puts the timing on the game loop: enough queued buffers to survive a slow frame is tens of milliseconds of latency, and garbage collection pauses become clicks.
The workable route is a native Lua module that opens the audio device itself (miniaudio or SDL3's audio stream, with a real callback) and runs the kernel there, with LÖVE left to draw and read input.
On Windows, Linux, the Deck and the Mac that is a small module.
**Consoles.** LÖVE has no console support of its own; console releases of LÖVE games go through porting houses that build their own platform layer.
Under the module above, that layer would also have to include our own audio backend on Nintendo's API.
LuaJIT's JIT is generally not permitted on consoles, so the Lua side runs interpreted there, and bindings should be plain Lua C modules, not LuaJIT FFI.
**Visuals.** A capable 2D renderer with GLSL shaders; 3D and offline rendering are ours to build.
LÖVE 12 (SDL3, Vulkan and Metal) is long in development and unreleased.
**Open source.** zlib, the most permissive here.
**Verdict.** The best fit for a small, hackable, open 2D instrument on PC and Deck; the most work of the open options for a Switch release, and the weakest for the visualizer's export.

### 4.3 Defold

Lua, a source-available licence (free, not OSI open source), native extensions in C++ that run on its consoles, and official Switch support for approved developers since 2020, with PlayStation too.
Its audio exposes no stream callback to extensions as Godot's does, so the kernel would again open its own device or depend on per-platform work.
Strong on small builds and console reach; weaker visuals and a smaller community for what we would ask of it.

### 4.4 Unity

Official Switch and Switch 2 support, a native audio plugin SDK whose DSP callback is a good home for the kernel, and FMOD or Wwise if wanted.
It meets every technical need, at the cost of a closed engine, a licence whose terms have shifted before, and C# between us and the core.
The choice if console certification risk outweighed everything else.

### 4.5 Unreal

MetaSounds is the most capable audio system of any engine here, and a custom MetaSound node or audio component can host the kernel.
It is heavy for a 2D instrument, slow to iterate on, and the original Switch is a hard target for it.
Not worth it for this project.

### 4.6 SDL3 with our own renderer

SDL3 gives a callback audio stream, controllers (it is where most engines' controller databases come from), and windows on every desktop and the Deck; its console ports are available to licensed developers.
With a small renderer (sokol or bgfx) it is the leanest and most controllable build, and the closest in spirit to the kernel.
Everything else, the UI, text, layout and video export, is ours to build.
The right choice if we later find the engine is mostly in the way.

### 4.7 Audio middleware: FMOD, Wwise

Both run on every console and are free under indie thresholds, and either can host the kernel as a plug-in (an FMOD DSP, a Wwise source plug-in).
They solve the console audio device and add mixing tools we do not need, since the kernel already is our mixer.
Worth keeping in mind only as a console device layer for an engine that lacks one (LÖVE, SDL3).

### 4.8 Comparison

| | Kernel on a real callback | Console route | Visualizer and export | Open source | Work for us |
|---|---|---|---|---|---|
| Godot 4 | yes, `AudioStream` in GDExtension | W4 Games; free Switch port | strong; Movie Maker | MIT | moderate |
| LÖVE | only by opening our own device | porting partner, plus our own audio backend | 2D only; export ours | zlib | high for consoles |
| Defold | by our own device | official Switch, PlayStation | moderate | source-available | moderate |
| Unity | yes, native audio plugin | official | strong | no | moderate |
| Unreal | yes, MetaSounds node | official, heavy on Switch 1 | strongest | source-available | high |
| SDL3 + renderer | yes | licensed ports of SDL | ours to build | zlib | highest |

## 5. Where the desk's logic goes

The desk's layouts are a functional core (`DeskCore`: controller frames in, effects as data out) over the theory core, in Swift.
Swift builds for macOS, Linux and Windows, but not for the Switch, so the core has to be moved to a language every target compiles:

- **C++, beside the kernel (recommended).**
  One portable core library: theory, `DeskCore`, the arrangement, the visualizer's mapping (section 6), with its tests run by plain equality as now.
  The engine's scripts become a thin shell that reads controllers, calls the core, plays its effects, and draws.
  It is also the only choice that could later be shared with the phone (Swift calls C++ directly), so that the theory is written once; whether to do that is a separate decision, since until then the theory lives in two languages and needs one shared set of test cases to keep them agreeing.
  The theory core has been ported this way, with the shared tests the paragraph above asks for: parity tests that run both cores side by side (`Perfecto/Sources/PerfectoTheory/README.md`).
- **The engine's language (GDScript, Lua, C#).**
  Faster to start, but the core is then tied to the engine, slower in the inner loops, and harder to keep pure.

The Mac desk stays as it is until the engine version reaches it.

## 6. The visualizer

The visualizer draws pictures from music in three situations: live while playing, over an arrangement the player has made, and over a tune dropped in.
All three are one component fed by one kind of input, so a set of visuals made for one works in the others.

### 6.1 One input: the music stream

A visual never reads audio devices or controllers.
It is a pure function of what it is given each frame and its own state:

```
(scene state, frame input, parameters, seed) → (new scene state, draw list)
```

The frame input is the **music stream** at one moment:

- **Musical events** since the last frame, each with its time in frames and beats: chords with their full context (key, degree, color, the mode's brightness, voicing, inversion, how hard they were struck, swell and brightness as played), the line's notes, which layer each came from, voice motion between chords, and the bar, beat and section.
  This is what Perfecto knows that no generic visualizer does, and what should make ours worth using: a scene can know that a chord moved to the relative minor, or that the music is getting brighter, or that one voice moved a semitone.
- **Audio features** from the rendered sound: level, a few spectrum bands, onsets, and per-layer levels where the kernel can give them.
- **Look-ahead**, where the source has it: the events of the next few beats.

The three sources fill the same stream differently:

| | Live (play) | An arrangement (sequencer run) | A dropped-in tune |
|---|---|---|---|
| Musical events | from `DeskCore`'s effects as they happen | compiled from the arrangement, all known ahead | a Perfecto file: the same as an arrangement; an audio file: estimated (6.3) |
| Audio features | analysed from the kernel's output ring in real time | analysed from an offline render, or live while it plays | analysed from the file, ahead of time |
| Look-ahead | none | the whole piece | the whole piece |
| Deterministic | no (it is a performance) | yes | yes |
| Exports to video | as a recording of the performance | yes, offline, at any size and frame rate | yes |

### 6.2 Time and sync

Visuals are timed by the kernel's clock, as notes are: the frame being drawn shows the music at the moment the listener hears it (the kernel's frame count less the output latency), interpolated between audio blocks.
On the phone a loop's notes are lit their lead before they sound; visuals must not be, or a flash lands 50 ms early.
Live, analysis runs on its own thread from the output ring, never on the audio thread.
Offline, the kernel renders with a stepped clock as `TimelineAudioRenderer` does now, and the engine draws each video frame at its exact time (Godot's Movie Maker), so the export is what was heard, frame for frame.

### 6.3 A dropped-in audio file

A tune made in Perfecto and saved as a Perfecto arrangement or MIDI file gives the full musical stream, the same as a sequencer run.
A tune made elsewhere and dropped in as audio gives only what analysis can find, computed once ahead of time on a background thread: a beat grid and tempo, onsets, the chroma of each beat, and from those an estimated key and chord per beat, each with a confidence.
The estimated events go into the same stream, marked as estimates, so scenes still work and the ones that lean on harmony fall back to energy where the confidence is low.
This analysis is plain DSP over a file and belongs in the C++ core; it is the one part with real research risk, and a scene set that looks good on energy alone is the safe first version.

### 6.4 Scenes and sets

- **A scene** is one visual idea: its pure step function, its parameters, and its cost tier (so the Switch gets the scenes it can draw at its frame rate).
- **A mapping** says which part of the music stream drives which parameter: brightness of the mode to light, consonance to smoothness, voice motion to the paths of particles, the bass to the camera.
  Mappings are data, so the same scene can be played by different features.
- **A set** is scenes, mappings and transitions, with sections of the music (a change of key, a new layer, a loop's start) as the places a set may move to its next scene.
- **A seed** fixes every random choice, so a set over the same arrangement gives the same video every time, and "generate different sets of visuals" is re-seeding a set or recombining sets, with the results kept by seed.

Assigning visuals to an arrangement is then just saving a set and a seed with it.
The desk's own screens (the color ring, the voices view after Tymoczko's geometry) are already pictures of the harmony, and are natural first scenes.

### 6.5 What the platforms change

The Switch's GPU is the tightest budget, shared with the desk's own screen; scenes declare a tier, and a set chooses scenes for the tier it runs on.
Consoles cannot write a video file for the player to take away; there the system's own capture is the export, and offline rendering is a desktop and Deck feature.
A dropped-in audio file needs a file system the player can reach, which is natural on PC and the Deck and awkward on the Switch, where a Perfecto arrangement made on the device is the realistic source.

## 7. A path, and what to measure first

1. **Spike: the kernel in Godot.**
   A GDExtension that hosts the kernel as an `AudioStream`, on the Mac and the Steam Deck: one controller, one chord, the existing presets.
   Measure the press-to-sound latency, the cost per voice per frame, and that the events land on their frames.
   This decides Godot before anything is ported; a failure points to SDL3.
   Done on the Mac (section 9); the Deck is still to do.
2. **Measure the kernel on ARM at Switch speeds** (a Cortex-A57 or A78 board, or a Raspberry Pi 4's Cortex-A72 at a lowered clock as a stand-in) and write the NEON voice loop if the numbers say so; this sets section 2.1's real tiers.
3. **Port the theory core and `DeskCore` to C++**, test for test.
   Done: the theory core (`Perfecto/Sources/PerfectoTheory`) and `DeskCore` (`Desk/Sources/PerfectoDeskCore`), each with every Swift test ported and parity tests against the Swift (their READMEs say how they are tested).
   The desk's parity tests play both cores with the same long runs of controller frames and compare every effect, legend and target they make.
4. **The desk in Godot on PC and the Deck**, Twin Rings first, the shell as thin as the Mac's.
   Begun on the Mac: every layout plays in `Desk/godot/`, which is now the canonical desk, on the C++ cores; what the screen shows is a value of the core's (`scene.hpp`), so the scripts only draw.
   Still to do: keeping the settings, the wired 360, MIDI on Linux, and the Deck.
5. **The visualizer, live**, with two or three scenes and the output ring's analysis.
6. **Arrangements: assigned sets and offline export.**
7. **Dropped-in audio files**: energy-only first, harmony estimates after.
8. **Consoles.**
   Register as a Nintendo developer, take a port (W4 or the free Switch port), Switch 2 first for its headroom, then the original Switch on its reduced tier.

## 8. Open questions

- Is Switch 1 worth it at all, given Switch 2's headroom and that the original's tier gives up unison and the ladder filter?
- Does the theory core move to C++ for the phone too, so it is written once, or stay in two languages with shared test cases?
- MIDI out from the Deck and Windows: a virtual port is easy on Linux (ALSA); on Windows it needs Windows MIDI Services' loopback or a third-party driver.
- The vocoder and mic sampling on platforms without a mic: hide them, or allow a USB mic where the system does?
- How much of the desk's UI is the game engine's own widgets, and how much is drawn as part of the visual language, as the rings are now?
- Licensing for publishing: our code open, the console layer private, the presets and samples under what licence?

## 9. Spike results: the kernel in Godot

> Measured 2026-10-29 on an M2 MacBook, Godot 4.7.2, with the spike then in `spikes/godot-kernel/`, now the desk's Godot app (`Desk/godot/`), where the spike is kept as its measurement scene (its README says how to build and run both).
> Not yet measured: the Steam Deck, the time a controller's press takes to reach a script, and the sound leaving the speaker (which needs a loopback recording).

### 9.1 What was built

A GDExtension compiles the kernel unchanged from `Perfecto/Sources/PerfectoKernel` and makes it a Godot `AudioStream`.
Godot's mixing thread calls the playback's `_mix`, which renders the kernel straight into Godot's buffer; no script runs on that thread.
Scripts send notes through the stream, which hands them to the kernel as timed events.
All 30 presets are loaded from a JSON file written by a small Swift tool from `SynthPreset` itself, so the sounds are defined once.
One screen plays I, IV, V and vi from a controller or the keyboard, changes the sound, and swells the held chord with RT; a headless script benchmarks every sound.
The only change outside the spike is that `SynthPatch.kernelPatch` is now public, for the dump tool.

### 9.2 What was found

**Hosting works as designed.**
The kernel renders on Godot's mixing thread, takes events from the game thread, and sounds as it does on the Mac desk.

**The kernel is cheap.**
Rendered offline inside Godot, 64 held voices cost 5 to 9% of one M2 core, depending on the sound.
One voice costs 17 to 29 ns a frame (median 19; Supersaw, with its seven copies, is the dearest).
The audio engine spec guessed 15 to 25 ns on an A12, which is slower than an M2, so that guess was optimistic, and section 2.2's Switch figures should be read at the top of their range.

**Live, there is ample headroom, but the load figure is noisy.**
The same light playing measured 5% of the deadline in one run and 17% in another, and 64 held Supersaw voices 8% in one and 24% in another; the worst single block was 44% of its deadline.
That spread, against the steady offline cost, suggests macOS runs the audio thread on an efficiency core or at a low clock until the load asks for more.
It is not a problem on a Mac, and it means live load figures on any platform should be read over several runs.

**Godot mixes in fixed chunks of 512 frames.**
Every `_mix` call asked for 512 frames, 11.6 ms apart at 44.1 kHz (the longest gap 11.8 ms), whether the output latency setting was 3 ms or 10 ms.
On macOS Godot also followed the device's rate (44.1 kHz) and not the project's 48 kHz, and reported its output latency as 0, so the block is the only measure of its buffer.

**So latency has a floor, and a choice.**
A strike sent "as soon as possible" (as the phone sends a key) waits for the next chunk: 0 to 11.6 ms, mean about 6.
With the chunk and the kernel's 1.5 ms after it, that is about 19 ms on average and 25 ms at worst from the script to the sound leaving Godot, before input and hardware.
A strike stamped a fixed lead ahead (one chunk and a millisecond, worked out from the latest render's start) arrived in time every time (0 of 79 late) and waited 12.60 ms, never more than 0.05 ms off: about 26 ms from script to Godot's output, but constant.
Constant latency is easier to play than latency that moves by 12 ms from strike to strike, so the stamped form is the better default; the phone's 256 frames at 48 kHz are still about twice as quick.
To that, Godot adds reading a controller once a frame (up to 17 ms at 60 frames a second), and the device adds its own buffer, neither measured here.

**Quitting while a player plays leaks it.**
Godot 4.7.2 does this with its own `AudioStreamGenerator` too; stopping the player and waiting two frames before quitting avoids it, and the spike does so.

### 9.3 A smaller chunk

Godot's source settles where the chunk comes from: `AudioServer::init` sets it to 512 frames, under a comment that it should become a project setting because it "limits audio latency to an absolute minimum of 11ms".
The one other thing its comments say depends on it is the ramp of a bus's or player's volume, which is spread over one chunk, so with a shorter chunk a change of volume is ramped faster and may click.
The spike's patch (`Desk/godot/engine/mix-buffer-frames.patch`, three lines) reads the chunk from a project setting, `audio/driver/mix_buffer_frames`, and leaves the ramp as it is.
Godot 4.7.2 built from source with it (the editor, Metal only, eight minutes on the M2) was measured as before, with the device buffer set to match through the output latency setting, which Godot's CoreAudio driver rounds to a power of two in frames.

| Chunk (frames, at 44.1 kHz) | 512 | 256 | 128 |
|---|---|---|---|
| Renders apart, longest | 11.7 ms | 5.9 ms | 3.0 to 3.1 ms |
| Strike to render, as soon as possible: mean, worst | 5.1, 11.4 ms | 3.0, 5.7 ms | 1.4, 2.8 ms |
| Strike to render, stamped a lead ahead | 12.60 ms | 6.79 ms | 3.89 ms |
| Late strikes, stamped | 0 of 82 | 0 of 76 | 0 of 77 |
| Script to Godot's output, stamped | about 26 ms | about 14 ms | about 8 ms |
| Render load, four-note chords struck | 18% | 8% | 6% |
| Render load, 64 Supersaw voices held; worst block | 31%; 40% | 16%; 21% | 11%; 22% |

At 128 frames, renders still came every chunk and never later than 3.1 ms apart, and every stamped strike was in time, with nothing else running on the machine.
A shorter chunk did not cost more per frame: the load fell as the chunk shrank, perhaps because the work came often enough to keep the audio thread on a fast core.
So a stamped strike leaves Godot in about 8 ms at 128 frames, against about 26 ms as shipped, and quicker than the phone's 256 frames at 48 kHz.
None of this was listened to, and a glitch that left the timing alone (a volume ramp's click) would not show in these numbers.

### 9.4 Verdict and next steps

Godot hosts the kernel correctly, at little cost, with the threading the kernel needs, and with the chunk made a setting it answers a press faster than the phone does; it remains the recommendation.
That means building Godot from source with our patch, which the console ports require anyway.
Notes go out stamped a lead ahead (one chunk and a millisecond), so their latency is constant.

Next:

1. **Listen at 128 and 256 frames**: play the spike with the patched editor and a controller, and change volumes while it plays, to hear whether the faster ramp clicks.
   If it does, ramp over a fixed time rather than one chunk, as Godot's own comment asks.
2. **Measure on the Steam Deck**, where the device buffer comes from PulseAudio or PipeWire and not CoreAudio, so the floor may be set by the system rather than by Godot.
3. **Offer the patch upstream**: Godot wants this setting (its own comment says so), specified in milliseconds rather than frames; a merged setting means no fork to carry.
4. **Measure the whole path** with a loopback recording, press to sound, and how long a controller's press takes to reach a script.

## Sources

- W4 Games, [W4 Consoles: beta support for the Nintendo Switch 2](https://www.w4games.com/blog/w4-games-news-1/w4-consoles-beta-support-for-the-nintendo-switch-2-87) (October 2025).
- GameFromScratch, [Godot gets free Nintendo Switch port](https://gamefromscratch.com/godot-gets-free-nintendo-switch-port/).
- Defold, [Nintendo Switch manual](https://defold.com/manuals/nintendo-switch) and [native extensions](https://defold.com/manuals/extensions).
- LÖVE wiki, [12.0](https://www.love2d.org/wiki/12.0) (unreleased); [LÖVE on Wikipedia](https://en.wikipedia.org/wiki/L%C3%B6ve_(game_framework)).
