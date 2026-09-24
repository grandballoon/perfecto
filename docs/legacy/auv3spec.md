> **Legacy document.** Written in July 2026, before the ongoing refactor; kept for reference only.
> It may not match the current code — check the source before relying on it.

# AUv3 & In-App Sound Sources — Spec

This document is the source of truth for how Perfecto produces and sources instrument sounds beyond its own bundled engine.
It captures the problem, the option space, and the chosen direction.

## Problem

Today it is possible to run GarageBand in the background on the same iPhone as Perfecto and use GarageBand's instruments to produce sound driven by the Perfecto UI, via Perfecto's virtual CoreMIDI source ("Perfecto").
This works but is awkward:

- GarageBand on iOS is complicated and hard to use.
- It forces a landscape mode that is hard to swipe out of.
- Selecting a new instrument takes several steps.
- The user must leave the Perfecto UI entirely to do any of this.

The goal is to let users play a wide range of instrument sounds without leaving the Perfecto UI, and to switch instruments quickly and simply.

## Option space

### Best architectural answer: host AUv3 instruments inside Perfecto

**Audio Unit v3 (AUv3)** is Apple's modern plugin format.
The key property: an AUv3 *instrument* plugin runs inside a host app's own process and UI.
If Perfecto becomes an AUv3 **host**, then:

- The user picks an instrument from a list **inside Perfecto** — no app switch, no landscape GarageBand, no CoreMIDI routing setup.
- Perfecto feeds its `ChordEvent`s straight to the plugin as MIDI.
  This slots cleanly under the existing `ChordEventSink` abstraction — it becomes a third sink (`AudioUnitSink`) alongside `AudioSink` and `MidiSink`, with no changes to the Music Theory Core.
- Instrument switching is just re-instantiating a different `AVAudioUnit` — a one-tap change in Perfecto's own UI.
- The plugin's own editor view can be presented as a SwiftUI sheet when the user wants to tweak the sound, or hidden entirely if we only want presets.

This is the clean, scalable path, and it fits the existing layering: event generation stays decoupled from consumption.
**AudioKit already supports AUv3 hosting** (`instantiate`, `AVAudioUnitComponentManager` to enumerate installed instrument components), so we are not starting from zero on the engine side.

There is a large ecosystem of AUv3 instruments the user can install once and then pick from inside Perfecto — Moog **Model 15 / Minimoog Model D**, **KORG Module**, **SynthMaster One**, **Zeeon**, **Ripplemaker**, AudioKit's own synths, plus many free ones.
GarageBand's own sounds are *not* exposed this way, but the AUv3 library dwarfs GarageBand's instrument set anyway.

The cost: we would be writing and maintaining a plugin host — component discovery UI, lifecycle, state save/restore, audio graph wiring, and handling misbehaving third-party plugins.
It is real work, but it is the industry-standard approach and the only one that keeps everything inside the Perfecto UI.

### Middle ground: expand Perfecto's own in-app engine

Perfecto already ships an `AudioSink` → AudioKit engine with a `SamplerVoice` and bundled SFZ instruments.
If the goal is "more/better sounds without app-switching," the simplest path is not hosting other apps at all — it is **adding more SFZ/SoundFont instruments to our own sampler** and exposing them in the Sound sheet.
This has zero inter-app complexity, is fully under our control, and works offline.
It is likely the highest quality-per-effort move for most of what users want, with AUv3 hosting layered on top as the "pro" tier.

### Fallback: keep CoreMIDI, but target a friendlier standalone synth

If we do not build hosting, the app-switching awkwardness is inherent to *any* standalone app — but GarageBand is one of the worst offenders.
Better standalone targets that receive the virtual "Perfecto" MIDI source and have simpler, portrait-friendly UIs:

- **AudioKit Synth One** — free, open-source, receives virtual MIDI cleanly.
  Good default recommendation.
- **Moog Minimoog Model D** — simple, portrait-capable.
- **KORG Module** — piano/keys/multi, straightforward preset picker.
- **NanoStudio 2**, **BeepStreet Zeeon**, **SynthMaster One** — all MIDI-receiving.

These still require the user to leave Perfecto to change instruments, so they are strictly worse than hosting for our stated pain points.

### What to avoid

- **Inter-App Audio (IAA)** — Apple deprecated it; do not build on it.
- **Audiobus** — third-party and still alive, but it is another dependency and still involves leaving the app to configure routing.
  AUv3 hosting supersedes it.

## Chosen direction

Two-part, matching the project's simplicity and long-term maintainability bar:

1. **Near term:** enrich our own SFZ/sampler instrument set and Sound sheet — no inter-app anything, best quality per unit of complexity.
2. **Strategic:** add an `AudioUnitSink` that hosts AUv3 instruments in-app.
   It is the only option that fully eliminates the GarageBand awkwardness, it extends the instrument ecosystem essentially infinitely, and it drops in under the existing `ChordEventSink` boundary without touching the pure Music Theory Core.


## Questions

### What are the actual players in this ecosystem?

Three groups matter.

**Hosts** (apps like the one Perfecto would become): AUM (Kymatica), Loopy Pro, Drambo, Cubasis, BeatMaker 3, NanoStudio 2, GarageBand for iOS, and Logic Pro for iPad.
AUM is the reference host — a minimal mixer whose entire purpose is loading AUv3s; it is worth studying for host UX.

**Instrument developers**: Moog (Model D, Model 15, Animoog Z), KORG (Module, Gadget, iM1), KV331 Audio (SynthMaster One / SynthMaster 3), BeepStreet (Zeeon, Sunrizer, Drambo), Bram Bos (Ripplemaker, Troublemaker), Audio Modeling (SWAM acoustic instruments), iceGear, Yonac, Klevgrand, 4Pockets, Numerical Audio, and AudioKit Pro (Synth One, FM Player).
It is a long tail: a few brand names plus hundreds of one-person indie shops.

**Infrastructure**: Apple (the AudioToolbox/AVFoundation APIs), AudioKit (open-source Swift audio framework — what Perfecto already uses), and JUCE (the C++ framework most cross-platform developers use to build AUv3 alongside VST3).

### Which of these instrument plugins are free? Which are paid?

The ecosystem norm is cheap one-time purchases ($5–$40), far below desktop plugin pricing, plus a healthy free tier.

**Free**: AudioKit Synth One and FM Player, SynthMaster 3 Player, KORG Module's base tier, Vagabond, and a steady stream of indie freebies (Synth Anatomy tracks these).
**Freemium**: Animoog Z (free with IAP unlock), KORG Module (free player, paid sound packs).
**Paid**: Moog Model D (~$15), Moog Model 15 (~$30), Zeeon (~$15), SynthMaster One (~$20), KORG Gadget (~$40), SWAM instruments ($10–$40 each), Pure Strings ($30).
Prices are approximate and sales are frequent.

The practical takeaway for Perfecto: a user who installs two or three free AUv3s already has a meaningfully better palette than GarageBand routing, at zero cost.

### What are the data types in this format? How are instruments composed?

AUv3 is not a data format — it is executable code packaged as an iOS App Extension.
There is no "instrument file" to parse; an AUv3 instrument is an app you install from the App Store, whose extension the host discovers and loads.

The key types a host (Perfecto) touches:

- `AudioComponentDescription` — the identity triple (type/subtype/manufacturer); instruments have type `aumu` ("music device").
- `AVAudioUnitComponentManager` — enumerates installed components; this powers the in-Perfecto instrument picker.
- `AVAudioUnit.instantiate(with:)` — async instantiation into our `AVAudioEngine` graph.
- `AUAudioUnit` — the plugin object itself: busses, parameters, render block.
- `AUParameterTree` / `AUParameter` — the plugin's automatable knobs.
- `scheduleMIDIEventBlock` / `AURenderEvent` — how we deliver MIDI (our `ChordEvent`s) into it.
- `fullState` / `fullStateForDocument` (a `[String: Any]` dictionary) and `AUAudioUnitPreset` — opaque state blobs for save/restore of the user's patch.
- `AUViewController` — the plugin's own UI, presentable in a sheet.

Internally an instrument is composed of a realtime DSP kernel (almost always C/C++), a parameter tree, factory presets, optional sample content, and a UI view controller.
From the host side all of that is opaque; we see busses, parameters, MIDI input, and rendered audio.

### How technically complex is any given instrument plugin? Give 3–5 open source code examples if possible.

The spread is enormous — a sine-wave instrument is a weekend project; a commercial synth is years of realtime C++ DSP work.
Hosting (our job) does not inherit that complexity, but these show what we would be loading:

1. [NickCulbertson/AUv3-Instrument](https://github.com/NickCulbertson/AUv3-Instrument) — a minimal AUv3 instrument using AudioKit 5; a few hundred lines. The best "smallest possible instrument" reference.
2. [AudioKit/AUv3-Example-App](https://github.com/AudioKit/AUv3-Example-App) — a full standalone-app-plus-AUv3-plugin template with knobs, presets, and UI; the shape of a real shipping product.
3. [AudioKit/AudioKitSynthOne](https://github.com/AudioKit/AudioKitSynthOne) — a complete open-source production synth (C++ DSP core, tens of thousands of lines); shows the ceiling.
4. [BuiltInParris/auv3-plugin](https://github.com/BuiltInParris/auv3-plugin) — an iOS/macOS example showing the Swift + C++ split.
5. Apple's own "Creating an audio unit extension" sample code — the canonical minimal skeleton straight from the API owner.

JUCE's `AudioPluginDemo` also exports to AUv3 and is what most cross-platform commercial instruments are structurally like.

### What is the range for the file size of a given instrument plugin?

- Pure-DSP synths: roughly 5–50 MB installed (code plus UI assets plus presets). Zeeon, Ripplemaker, and Model D are in this band.
- Sample-based instruments: hundreds of MB to multiple GB. KORG Module with expansion packs exceeds 4 GB; SWAM and piano ROMplers sit in the 100 MB–1 GB range.

For Perfecto-as-host, disk size is the user's concern.
What we inherit is the **runtime memory footprint**, which matters because of the extension memory limit (see gotchas).

### Can it be minified or optimized in some way?

Not by the host — the plugin is a signed, sandboxed black box; we cannot strip or recompress someone else's extension.
Plugin authors optimize by compressing sample content, downloading sounds on demand, and streaming samples from disk instead of preloading.

What Perfecto *can* optimize is hosting behavior: instantiate lazily, release unused `AVAudioUnit`s promptly, persist `fullState` instead of keeping idle instances alive, and load out-of-process so a heavy plugin's memory is charged to its own process rather than ours.

### How old is this format? What's its history?

Audio Units date to Core Audio in the original Mac OS X (~2001); AUv2 was the Mac desktop standard for two decades.
AUv3 was introduced at WWDC 2015 (iOS 9 / OS X El Capitan), rebuilt on the App Extension model so plugins are sandboxed, App Store-distributed, and can run out-of-process.
Adoption was slow until GarageBand for iOS added AUv3 hosting (2017) and AUM proved the host model; by ~2019 AUv3 had displaced Inter-App Audio and Audiobus as the way iOS music apps connect, and Apple formally deprecated IAA in iOS 13.
Today it is a mature, decade-old format and the only sanctioned plugin architecture on iOS.
On the Mac, AUv2 and VST3 still dominate; AUv3 adoption there remains partial.

### Are there online communities focused on making instrument plugins like this?

Yes, and they are unusually concentrated:

- **Audiobus Forum** (forum.audiob.us) — *the* hub for iOS music apps; every AUv3 developer announces and gets feedback there. If Perfecto ships AUv3 hosting, this is where its users already are.
- Subreddits: r/iosmusicproduction, r/ipadmusic.
- YouTubers: The Sound Test Room (Doug Woods), haQ attaQ (Jakob Haq), Gavinski's Tutorials, SoundForMore — all review AUv3s and demonstrate host workflows.
- Developer-side: The Audio Programmer community/Discord, the JUCE forum, the AudioKit GitHub/Discord, and Audio Developer Conference (ADC) talks.
- News sites: Synthtopia and Synth Anatomy cover AUv3 releases, including free ones.

### What kind of technical gotchas are common?

- **Extension memory limit**: an AUv3 extension gets a hard cap (~360 MB on many devices); the OS kills it silently when exceeded. As a host we must handle a plugin dying mid-performance and surface it gracefully.
- **Async instantiation**: `instantiate` is asynchronous and can be slow; the picker UI needs loading states.
- **Out-of-process vs in-process**: out-of-process isolates crashes (a misbehaving plugin cannot take down Perfecto's audio) at a small IPC latency cost; prefer it.
- **State save/restore inconsistency**: plugins vary in how faithfully `fullState` round-trips; test per-plugin, persist defensively.
- **UI sizing**: plugin view controllers get whatever size the host gives them; some handle resizing badly. Present in a fixed-size sheet.
- **Render-thread discipline on our side**: feeding MIDI and pulling audio happens on the realtime thread — no locks or allocation, the same rule our `AudioSink` already lives by.
- **Sample rate / buffer mismatches**: the plugin must be (re)configured when our session changes; handle route changes.
- **Host musical context**: tempo-synced plugins ask the host for tempo/transport via `musicalContextBlock` — we should wire `MasterClock` into that.

### What is this format BAD at?

- Very large sampled instruments — the memory cap makes multi-GB orchestral libraries impractical; that world stays on desktop.
- Cross-platform reach — an AUv3 runs nowhere outside Apple platforms.
- Host-independence — routing, tempo, and state behavior varies by host, so plugins misbehave in hosts they weren't tested in (we will be a new, untested host).
- Copy protection and pro licensing (no iLok), which keeps some flagship desktop instruments away.
- Discoverability and pricing power — App Store race-to-the-bottom economics.
- Predictable QoS — nothing stops a user loading a CPU-hungry patch that glitches on an old phone.

### What is the equivalent format outside the Apple ecosystem?

- **VST3** (Steinberg) — the cross-platform desktop standard (Windows/macOS/Linux); the closest peer.
- **CLAP** — a newer open-source standard (u-he/Bitwig) gaining desktop traction.
- **LV2** — the Linux-native format.
- **AAX** — Pro Tools only.
- **Android has no viable equivalent** — this is precisely why iOS owns mobile music-making, and why AUv3 hosting is a durable bet for an iOS-only app.

### What Apple-owned or third-party plugins make heavy use of this format? What are the most popular examples?

Apple's role is mainly as a **host**: GarageBand for iOS and Logic Pro for iPad both host AUv3s (Logic for iPad also exposes some of its own effects/instruments as AUv3-style plugins within Apple's apps).
The popular third-party instruments: Moog Model D and Model 15, Animoog Z, KORG Module and Gadget, SynthMaster One/3, Zeeon, Sunrizer, Drambo, SWAM instruments, Ravenscroft 275 (piano), AudioKit Synth One.
Popular effects: FabFilter's suite, Eventide Blackhole, Klevgrand, Baby Audio.
Popular hosts besides Apple's: AUM, Loopy Pro, Cubasis, BeatMaker 3.

### Brands like Moog and KORG are third-party; are their instruments free or paid?

Mostly paid, but cheap by desktop standards.
Moog: Model D ~$15, Model 15 ~$30, Animoog Z freemium (free tier, ~$10 unlock); Moog has run free-giveaway promotions (Model D was free for a period in 2020).
KORG: Module is a free player with paid sound expansions (Module Pro ~$40 tier), Gadget ~$40, iM1 ~$30; KORG discounts heavily and often.
So "install once, pick from inside Perfecto" costs a motivated user roughly $15–$40 total for brand-name sounds, or $0 staying on the free tier.

### What's the difference between SFZ/SoundFont and AUv3?

They are different layers of the stack.

**SFZ and SoundFont (.sf2) are passive data formats**: sample files plus text/binary metadata describing key mapping, velocity layers, loops, and envelopes.
They make no sound by themselves — an engine (like Perfecto's `SamplerVoice`) must load and render them.
We control the engine, the memory strategy, and the UX; content is just files we bundle or download.

**AUv3 is executable code**: a complete third-party instrument — DSP engine, presets, UI — running as a plugin inside our process/graph.
We control nothing inside it; we only route MIDI in and audio out.

An AUv3 can *itself* be a sampler that loads SFZ (some are).
This is exactly the two-part chosen direction above: SFZ expansion grows **content** inside our own engine (cheap, controlled, offline); AUv3 hosting grows **engines** (unbounded palette, third-party complexity).