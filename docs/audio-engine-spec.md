# Audio engine spec

> **Status (2026-10-06): proposed.** Nothing here is implemented.
> It follows the sequencer restructuring in [../sequencer.md](../sequencer.md), which comes first and may accept degraded sound.
> The options behind each choice, and the data structures this lets us simplify, are in [audio-engine-findings.md](audio-engine-findings.md).

## 1. Purpose

Perfecto's sound is made by a graph of AudioKit nodes driven from the main thread.
That was the right way to get to a playable instrument, and it is the wrong shape for what comes next: several layers sounding at once, per-note sound, sample-accurate sequences and loops, sampled instruments, and sound that comes in through the mic (sampling and the vocoder).
This spec describes the engine the best iPhone synths converge on, says where ours differs, and proposes one engine that closes the gap.

Two limits on the evidence.
The practices in section 2 are the common, publicly documented ones (Apple's Audio Unit guidance, open-source engines such as AudioKit Synth One and sfizz, and what vendors have said about their apps); closed-source internals are not public, and nothing was looked up on the web for this document.
Every CPU and memory figure is an estimate from reading the code and from typical costs, not a measurement; section 5 says which to measure first.

## 2. The standard

The engines behind the best-regarded iPhone instruments (Moog's Model D and Animoog, KORG Gadget and Module, AudioKit Synth One, Pianoteq, GarageBand's own instruments) differ in sound and agree on structure.

| Practice | Why it matters | Perfecto today |
|---|---|---|
| One render function makes all the sound: voices are plain structs in a fixed pool, mixed in a block loop. | No per-node overhead, no graph changes, and the whole signal path is testable offline. | Every voice is six audio units (two oscillators, an FM pair, a mixer, a ladder filter, an envelope): 48 units for 8 voices. |
| Nothing on the render thread allocates, locks, or calls into Swift/Objective-C runtime machinery. | One late render cycle is an audible click. | The render thread only runs AudioKit's kernels, so this holds, but only because all our logic is elsewhere. |
| Events carry a sample time, and the render function applies each one at its exact frame. | Timing is as steady as the audio clock, whatever the UI is doing. | Notes are started from the main thread: clock ticks are run-loop `Timer`s, and strums, gates and Repeat's gap are `Task.sleep`. |
| Musical time is derived from the count of rendered frames. | Sequences, loops, arpeggios and effects cannot drift apart. | Two clocks: the looper's sample grid and the `Timer` clock, joined by scheduling "a moment from now". |
| A voice allocator with release tails and stealing: a new note takes a free voice, else the quietest releasing one, faded out over a few milliseconds. | Chord changes overlap the way they do on a real instrument, with no clicks. | `playChord` closes every gate and restarts voice *i* at a new pitch at once, so the old chord's release is cut and the oscillator jumps pitch while still audible. |
| Band-limited oscillators (one wavetable per octave or so, or PolyBLEP). | Saws, squares and pulses have no aliasing in the top octaves. | One 4,096-sample table per wave for every pitch, as far as the AudioKit source shows; `.pulse` and the raw sawtooth have hard edges. |
| Every continuous control is smoothed per block or per sample. | No zipper noise when a control is played. | The brightness filter glides (30 ms); chorus amount, reverb send and oscillator levels step. |
| Effects are shared buses with per-source send levels. | One good reverb costs the same for one note or sixty. | Nine `EffectsChain`s (live, 2 looper tracks, 6 play-mode loops), each with a chorus and a Zita reverb that run even when off. |
| Gain staging with headroom, and a limiter on the master bus. | Dense chords and layers get louder gracefully rather than clipping. | Voices and loop tracks are summed straight to the output; a seven-note chord at `level` 0.25 can already pass full scale before any loop is added. |
| Per-note expression: velocity, stereo placement, slight detune and timing spread. | It is most of the difference between "synth demo" and "instrument". | Velocity is fixed, every voice is centred and mono until the chorus. |
| Sampled instruments stream from disk, with velocity layers and release samples. | Piano and guitar are what a non-musician expects to hear. | Not built (build-order step 13). |
| The engine is an Audio Unit, so it can be hosted, bounced offline, and shipped as an AUv3. | Export, tests and plug-in distribution come from the same code. | Offline tests exist for effects and loops; voices are not rendered in tests. |

## 3. Proposed engine

### 3.1 Shape

One render kernel makes every sound the app produces itself.
`AVAudioEngine` shrinks to three nodes: the mic input, that one unit, and the output.

```
 main actor                         scheduler queue                render thread
 ───────────                        ────────────────               ─────────────
 modes, arpeggiator, timeline  ──→  timed notes, a short     ──→   kernel
 (what to play, in beats)           way ahead (sample times)
                                         │
                                         └──→ MIDI (host times)

 inside the kernel:

   mic in ──┬─→ capture buffers (become sampled sounds)
            └─→ vocoder modulator ─┐
   voices ──┬─→ vocoder send ──────┴─→ vocoder ─┐
            │                                   ▼
            ├─────────────────────────────────→ dry ──────────────┐
            ├─→ chorus send ─→ chorus ────────────────────────────┤
            └─→ reverb send ─→ reverb ────────────────────────────┴─→ limiter ─→ out
```

The vocoder's output is itself sent to the chorus and reverb, by the sends of the notes that feed it.

Everything left of the kernel is ordinary Swift with no real-time constraint.
The kernel is the only code with one, and it is small enough to hold to it by review and by test.

### 3.2 Notes and time

The kernel's whole input, beside the mic's audio, is five timed events.

| Event | Carries |
|---|---|
| note on | a note id, MIDI note, velocity, and the note's sound (3.3) |
| note change | a note id and a new sound, for a control that is played while the note is held |
| note off | a note id |
| settings | the shared effects' own controls (chorus rate, reverb size), tempo |
| capture | start or stop recording into a numbered buffer, from the mic or from the vocoder's output |

Each has a sample time, or none, meaning "the next render cycle" (a finger on a key).
A note id is chosen by the sender, so ending a note never depends on what else is sounding, and several layers can play the same pitch.

There is one clock: the kernel's count of rendered frames.
A `Transport` maps beats to frames at the current tempo; it is a pure value, so every "when" in the app is arithmetic on it.
A scheduler turns whatever is due in the next window into timed events, for the kernel in sample time and for MIDI in host time, so the two sinks hear the same performance.
The window is short for what a finger is driving (about two render cycles, so a release is obeyed at once) and long for a running sequence or loop (100 to 200 ms, so a stalled main thread is not heard).

Strums, gates, Repeat's gap and arpeggio steps become times on notes, computed by the pure functions that already describe them (`Articulation.onset`, `ArpeggioPattern.pass`, `SequencerStep.gate`).
No `Task.sleep` and no `Timer` remains in the path from intent to sound.

### 3.3 A note's sound

A note carries its own sound, fixed when it starts unless a note change arrives:

- which patch (an index into the patches the kernel was given),
- brightness (the played low-pass, per voice),
- chorus send and reverb send,
- vocoder send: how much of the note is carrier for the vocoder and not heard directly.

This one decision does most of the work.
Layers, loops and sequence steps need no engine concept of their own: a layer is notes that happen to share a sound.
A finished loop keeps its sound because its notes carry it, not because it has a private effects chain.
A sequencer step can have its own key, octave, patch and effect amounts, which is what [../sequencer.md](../sequencer.md) asks for.

### 3.4 Voices

- A fixed pool of 64 voices, each a struct of plain numbers; no voice is ever created or destroyed.
- Allocation: a free voice, else the quietest voice in release, else the oldest; a stolen voice fades over about 3 ms before it is reused.
- A note off starts the release; the voice frees itself when its envelope reaches silence.
- Each voice has a pan position. A chord's notes are spread a little across the stereo field by the sender.
- Voice state is laid out for the block loop (arrays of each field, not an array of voices), so the hot loops vectorize.

### 3.5 Sources, filter, envelopes

- **Oscillators.** Wavetables with one table per octave, built once per wave when a patch is loaded, each holding only the partials that fit under Nyquist at the top of its octave. `SynthPatch.Wave.harmonics` already describes waves this way, so the standard waves become harmonic lists too.
- **FM.** Phase modulation between the voice's two oscillators (findings, D5), with the index swept as `SynthPatch.Sweep` does today.
- **Sample playback.** A third source kind: a buffer read at a pitch ratio with interpolation. It serves what the kernel has captured (3.7) first and bundled instruments later (3.9).
- **Patch filter.** A zero-delay-feedback state-variable low-pass per voice: stable when swept fast, cheap, and resonant. The ladder model stays available for patches that want its character, at about four times the cost.
- **Brightness.** A second, plain low-pass per voice, so a note keeps the brightness it was played with while later notes are brighter or darker.
- **Envelopes.** Exponential segments; attack and release never shorter than about 2 ms so nothing clicks. Velocity scales level and, per patch, filter opening.

### 3.6 Mix bus

- One chorus and one reverb, each fed by the voices' send levels. The reverb's size and the chorus's rate are the only effect controls that are not per note.
- Sends, not wet/dry mixes, as today: a played or switched-off effect never cuts a tail.
- The reverb keeps the algorithm we have (Zita's eight-line feedback delay network is a good one), with pre-delay and high damping exposed.
- Master: a DC blocker, 12 dB of headroom into a look-ahead limiter (about 1.5 ms), then the output. Level per voice is not scaled by the number of voices; the limiter does that job only when it must.
- Flush-to-zero is set on the render thread so decaying filters and reverb tails cannot fall into denormal arithmetic.

### 3.7 Audio in: sampling and the vocoder

The kernel has an audio input, fed by the mic, from its first version.
An Audio Unit with an input is a different type of unit from one without, so adding it later would mean re-hosting the kernel.

- **Capture.** A capture event records the input, or the vocoder's output, into one of a fixed set of buffers allocated before the engine starts. It starts and stops at an exact frame, with no tap, no file and no lock. A finished buffer is a sampled sound: it is played by notes, with the sends and timing of any other note.
- **The mic sample** is a captured buffer played at each key's pitch. `MicSampler` becomes a capture event and an entry in the list of sounds.
- **The vocoder.** The mic is the modulator, and the notes sent to the vocoder are the carrier. Each passes through a bank of 16 to 24 band-pass filters; the level of each mic band, followed over a few milliseconds, sets the gain of the same carrier band. Any patch can be the carrier, and bright, harmonically full ones (a sawtooth) speak most clearly, which is one more reason for band-limited oscillators.
- **Audio loops, for mic-derived sound only.** A vocoded phrase or a sung line is not notes, so it cannot be a loop of notes. It is looped by capturing it and playing the buffer with one note as long as the loop. This is the only audio looping left, and it needs no looper: the scheduler already repeats notes on the sample grid.

The mic hears the phone's own speaker.
With headphones the vocoder runs at full quality.
On the speaker it runs with the session's voice processing (echo cancellation) switched on, which dulls everything the app plays while it is on, so it is switched on only then.
A Bluetooth mic forces the call-quality profile for input and output alike, so the app should use the built-in mic even when Bluetooth headphones are the output.

### 3.8 Hosting

- The kernel is wrapped as an `AUAudioUnit` subclass with one input bus and one output bus (a music effect), registered in-process and attached to `AVAudioEngine` between the mic input and the output. That gives a sample-accurate event queue (`scheduleMIDIEventBlock` and parameter events) that Apple maintains, offline rendering through the engine's manual mode, and a direct route to an AUv3 later.
- An `AudioSession` type owns the session: category, buffer size, input choice, route changes, interruptions, and External Synth mode. Nothing else touches `AVAudioSession`. The engine is not restarted on a route change while External Synth is on (the open bug in the phase plan).
- AudioKit, SoundpipeAudioKit, DunneAudioKit and their transitive packages are removed.

### 3.9 Sampled instruments

Sampled piano and guitar matter more to the intended player than more synth patches.
The kernel's sample source covers one-shot and simply mapped instruments.
For full SFZ instruments, the kernel hosts sfizz as one more source that renders into the same sends and limiter, streaming from disk.
Apple's `AVAudioUnitSampler` is the fallback if sfizz proves too heavy: no DSP of ours, but it is a separate unit outside the kernel's sends and reads SF2/EXS, not SFZ.

### 3.10 Language

The kernel is written in C++ behind a C-shaped interface, and everything else stays Swift.
C++ is where real-time audio code is proven, sfizz is C++, and the same kernel compiles to WebAssembly for Harmonicland.
The alternative is Swift with unsafe pointers, which keeps one language but leaves "no allocation, no reference counting, no locks" unenforced; see findings E3.
This choice was made on 2026-10-06 (section 7); it keeps the Harmonicland suite in [own-instruments.md](own-instruments.md) (question 2) open as an option without deciding it.

### 3.11 Testing

- The kernel renders offline with no engine at all: give it events, input samples and a frame count, read back samples.
- Timing: a note scheduled at frame *n* has its first non-zero sample at frame *n*, at every buffer size.
- Aliasing: the spectrum of a high sawtooth has no partial above a set level that is not a harmonic.
- Voices: more notes than voices never clicks (no sample-to-sample jump above a set size); a released note is silent after its release.
- Level: 64 voices at full velocity never exceed full scale at the output.
- Parity while porting: each of the 14 presets is compared by ear against the current engine, since the oscillators will not match sample for sample.
- Capture: a buffer captured from frame *a* to frame *b* holds exactly the input's frames *a* to *b*.
- Vocoder: a carrier with a silent modulator is silent; a modulator that is a sine in one band passes the carrier in that band and little elsewhere.
- A render-time test: worst-case polyphony must render a 256-frame block within the budget in section 5 on the oldest supported phone.

## 4. Tradeoffs accepted

| We give up | For | Why it is acceptable |
|---|---|---|
| AudioKit's ready-made nodes | One kernel we own | We use nine node types; each is a well-known algorithm of tens to a few hundred lines. |
| A reverb size and chorus rate per loop | One reverb and one chorus | Amounts stay per note, which is most of what "this loop is wetter" means; nine reverbs do not scale to sequencer layers. |
| Loops of the synth as recorded audio | Loops as notes, re-rendered | Editable, tiny, and they follow tempo; the cost moves from memory to voices (section 5). A loop no longer captures exactly what was heard; a slide played mid-note is kept, recorded as note changes. Mic-derived sound is still looped as audio (3.7). |
| Single-language codebase | A C++ kernel | See 3.10; contained behind one interface of five events. |
| Duration-preserving pitch shift for the mic sample (`TimePitch`) | Sample playback at a pitch ratio | Lower latency and CPU, and the classic sampler sound; higher notes are shorter. Keeping `TimePitch` would leave the mic sample outside notes, sends and loops. |
| Full sound quality while vocoding on the speaker | A vocoder that works without headphones | Voice processing is on only while the vocoder is on and no headphones are connected. |
| Instant response for sequenced notes | A scheduling window | Only sequenced material is delayed, by a constant, and its own playhead is drawn from the same clock. |

## 5. Budgets and expected bottlenecks

**Latency.** A render cycle is 256 frames, 5.3 ms at 48 kHz.
Touch-to-sound is dominated by things outside the engine: touch delivery (8 to 17 ms depending on the phone), one main-thread hop, one render cycle, and the output hardware.
The engine's own contribution should stay at one cycle plus the limiter's 1.5 ms.
Mic to output, for the vocoder, is an input cycle and an output cycle plus hardware at both ends, around 15 ms: unnoticeable for a vocoder, too much for monitoring a dry voice, which the app does not do.
Bluetooth output adds well over 100 ms that nothing here can remove; the app should say so rather than try.

**CPU.** Target: the worst case renders in under a quarter of a cycle (1.3 ms per 256 frames) on the oldest phone iOS 17 runs on (A12).
Estimated per-voice cost is 15 to 25 ns per frame (two table oscillators, two filters, envelope, pan and sends), so 64 voices are about 1 to 1.6 µs per frame, or 5 to 8% of one core.
The shared chorus, reverb and limiter add well under 1%, and so does the vocoder (about 100 filter sections per frame for 24 bands).

**Memory.** Wavetables are about 80 KB per wave.
Loops as notes are kilobytes; today one two-minute stereo take is 46 MB as `[[Float]]`, and eight tracks could hold 370 MB.
Capture buffers are the audio that remains: 23 MB per stereo minute, allocated up front, so their number and length are a fixed budget (four buffers of 30 seconds is 46 MB).
Sampled instruments are the real memory cost and must stream.

Bottlenecks to expect, most likely first:

1. **Main-thread stalls reaching the sound.** SwiftUI layout during a panel animation can hold the main actor for tens of milliseconds. The scheduler therefore runs on its own queue from an immutable snapshot of what is playing, and only live touches depend on the main thread.
2. **Voice count under dense layers.** Six layers of seven-note chords with release tails can ask for more than 64 voices. Stealing makes that graceful; the pool size is the tuning knob, and the render-time test sets its ceiling.
3. **The ladder filter.** Its nonlinear, oversampled model costs several times the state-variable filter. Sixty-four of them could take the whole budget, so patches opt in and the default is the cheap filter.
4. **A real-time violation in our own code.** One allocation or lock in the kernel is a rare, unreproducible click. The kernel takes only preallocated memory, and a debug build traps on allocation inside the render call.
5. **Sample streaming.** Disk reads must happen off the render thread with enough preloaded at each sample's head; first notes after loading an instrument are where this shows.
6. **Thermal and low-power throttling.** A phone that is hot or in Low Power Mode renders the same block more slowly. The quarter-cycle target is the margin for this.
7. **Limiter pumping.** If dense material leans on the limiter constantly, it will be heard. Per-patch levels should be set so that typical playing leaves it idle.
8. **Mic feedback and input quality.** See 3.7; these are limits of the phone, and the vocoder's page should state them.
9. **Parameter storms.** A slide sends a note change per touch move per held note. Changes are coalesced per render cycle and smoothed in the kernel.

## 6. Implementation sequence

The sequencer restructuring ([../sequencer.md](../sequencer.md)) comes before the kernel, so the sequence is arranged so that the pieces the two share are built once, first, and the sequencer work lands on them.
Every step leaves the app working and has its own tests.
D and E numbers refer to [audio-engine-findings.md](audio-engine-findings.md).

| # | Step | What is built | Needs | Done when |
|---|---|---|---|---|
| 1 | ~~Level and shared effects, in the current engine~~ (done 2026-10-06: `MasterBus`, `SharedReverb`) | A limiter on the output; one reverb fed by a send from the live mix and from each loop track. | — | Offline test: every voice and loop track at once stays under full scale; one reverb node in the graph. |
| 2 | Sound as data | `Sound` list in place of the `SynthPreset` switches (D6); two-operator `SynthPatch` (D5). Moved to step 8 on 2026-10-06: the AudioKit voice cannot realize a general two-operator patch, and the list earns its keep only once a sound can be something other than a synth patch. | 7 | The 14 presets render in the kernel. |
| 3 | The note seam | The note-level sink (`NoteSink`, `NoteID`) and `NotePlayer` expanding chords into notes with ids (D1). MIDI and the AudioKit voices sit behind it; the voices get an allocator, so release tails stop being cut now. Done 2026-10-06, except `NoteSound` (D2): the current engine has one filter and one chorus for everything, so a per-note sound arrives with the kernel (step 8). `gateTask` and `retriggerTask` go in step 4, with the other timers. | — | Both `strumTask`s and `startNotes` are gone; mode tests pass unchanged; `NotePlayerTests`, `VoiceAllocatorTests`. |
| 4 | Musical time as a value | `Transport`, the scheduler, and the pure "notes due in this beat range" functions for strum, gate, Repeat and the arpeggiator (D4, E4). Until the kernel exists the audio sink starts each note when its time arrives; MIDI already gets host-time stamps. | 3 | `MasterClock`'s timers, `ClockRepeat` and `Task.sleep` are gone from the note path; timing rules are tested as functions with no fake clock. |
| 5 | The sequencer restructuring | The timeline, loops as layers of notes, one compile function for playback and export (D3, D10). Both audio loopers are deleted. The voice pool is raised for layers and sound is accepted as degraded, as [../sequencer.md](../sequencer.md) allows. | 3, 4 | Its own spec; from the engine's side, everything that sounds arrives as timed notes. |
| 6 | ~~Decide the kernel's language~~ | E3. | — | Done: C++ (section 7). |
| 7 | Kernel skeleton | The `AUAudioUnit` with input and output buses, the five events, one sine voice, the offline test harness, the allocation trap. | 6 | A note scheduled at frame *n* starts at frame *n* at every buffer size, in an offline test. |
| 8 | Kernel at parity | Voice pool and allocator, operators, both filters, envelopes, sends, chorus, reverb, limiter; the sounds ported. `AudioSession` takes over the session (D8). AudioKit and its packages are removed. | 2, 3, 7 | The app plays through the kernel only; the level, voice and render-time tests of 3.11 pass on a device. |
| 9 | Sample-accurate time | The scheduler passes sample times to the kernel; the "start it when its time arrives" bridge from step 4 is deleted. | 4, 8 | A sequence rendered offline has every note on its exact frame; a loop of notes does not drift over ten minutes. |
| 10 | Quality | Band-limited tables, velocity, stereo spread, exponential envelopes, reverb pre-delay and damping, per-patch levels against the limiter. | 8 | The aliasing test passes; the rest is listening, preset by preset. |
| 11 | Capture and sampled sounds | Capture buffers, the sample source, the mic sample as a sound, audio loops of captured sound. `MicSampler` is deleted. | 8, 9 | The capture test passes; a recorded sample can be played, sequenced and looped like a patch. |
| 12 | Vocoder | The filter bank, the vocoder send, its page in the menu, input choice in `AudioSession`. | 11 | The vocoder tests pass; a vocoded phrase can be captured and looped. |
| 13 | Bundled instruments | sfizz as a source, streaming, the first sampled instruments. | 8 | An SFZ piano plays through the same sends and limiter within the render budget. |

Step 1 is independent of everything.
Steps 10, 11 and 13 can be done in any order after 8 and 9; 12 follows 11 because the vocoder is only loopable once capture exists.

Rough size for steps 1 to 4 and 7 to 13 (the sequencer restructuring is estimated separately): 4,000 to 6,000 lines written, about a third of it tests, and about 1,800 lines of the current audio layer and its tests removed.

## 7. Decisions

Decided on 2026-10-06:

1. **Kernel language: C++** behind a C-shaped interface (3.10). Step 6 of the sequence is done.
2. **Slides inside recorded notes are recorded**, as note changes on the note in the timeline, so a loop plays back as it was performed. The sequencer editor must at least preserve them (step 5).
3. **The mic sample is pitched by playback rate.** It becomes an ordinary sampled sound, and `TimePitch` goes (step 11).
4. **The vocoder offers voice processing.** It works on the speaker with the session's echo cancellation on, and at full quality with headphones, where voice processing is left off. `AudioSession` switches it with the route (step 12).

Still open:

1. **Reverb per layer.** If one room for everything proves too limiting, the next step is two fixed reverbs (short and long) with a send to each, not a reverb per layer.
2. **Capture budget:** how many buffers and how long (section 5). Four buffers of 30 seconds is the working assumption until step 11.
