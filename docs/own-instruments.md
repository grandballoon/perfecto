# Own AUv3 Instruments — Evaluation Notes

> **Status (2026-09-24): deferred.** Research only; nothing implemented.
> Sound sourcing for now: the back-tap GarageBand workflow (Perfecto drives GarageBand over the "Perfecto" virtual MIDI source).
> It works well enough that this is not blocking feature work.

## Idea

Build Perfecto's own instruments and ship them as AUv3 extensions instead of expanding the current `SynthVoice` bank.
Using AUv3 turns `AudioSink` into an AU host.
Hosting third-party AUv3s (the "strategic" item in [legacy/auv3spec.md](legacy/auv3spec.md)) then costs only ~800–1,200 more lines.
It also enables sample-accurate strum and timing instead of `Task.sleep` on the main actor.

Current baseline: the whole app is ~8.3K lines of Swift including tests.
The sound engine is ~330 lines: `SynthVoice`, `SynthPreset`, `AudioSink`.
The 8 presets are one waveform plus an ADSR envelope; "FM Bell"/"FM Bass" contain no FM.

## Size estimate (lines of code, not time)

| Component | Lines |
|---|---|
| Shared AU framework: `AUAudioUnit` subclass, C++ real-time core (voice allocation, events, smoothing), extension plumbing, SwiftUI parameter controls, `AudioUnitSink`, offline-render test harness | 3,200–4,800 |
| Analog-style synth (anti-aliased oscillators, filter, envelopes, LFO, unison, glide) | 2,000–3,000 |
| FM synth (4 operators) | 1,500–2,300 |
| Sampler with an SFZ subset (or ~600 lines wrapping sfizz) | 2,500–3,500 |
| Physical modeling (plucked string, modal bell) | 1,000–1,800 |
| Effects chain (reverb, chorus, delay, EQ, limiter) | 1,200–2,000 |
| Third-party AUv3 hosting on top | 800–1,200 |

- Minimum useful version (framework plus one analog/FM synth): ~5–7K lines.
- Full suite plus hosting: ~13–19K lines.

Bottlenecks that LLM coding speed doesn't shorten:
- listening time for sound design
- sourcing or recording sample content (the 250 MB bundle limit)
- real-time glitches that only show up on a device
- ongoing review of a large C++ DSP codebase

The target audience is non-musicians ([../strategy.md](../strategy.md)), who likely want piano and guitar more than synth sounds.
So the sampler and its content matter most.

## Open questions before implementing

### 1. Comparison with GarageBand, Logic and others, especially file size on mobile

Measure installed app size plus sound-library size for GarageBand iOS, Logic Pro for iPad and other popular iOS instruments and hosts (KORG Module, Moog Model D, AUM, Cubasis).
Also cover the desktop equivalents.
Rough starting guesses from model knowledge, **unverified**:
- GarageBand iOS: ~1.5–2 GB with the downloadable sound packs.
- Logic Pro for iPad: a similar-sized app plus a multi-GB optional sound library.
- Logic Pro Mac: a full library in the tens of GB (~70 GB+).

Verify these on a real device before relying on them.
Key question: what sound quality is achievable within Perfecto's ≤250 MB bundle, compared with on-demand downloads (Apple-hosted Background Assets or On-Demand Resources)?

### 2. Possible merge with Harmonicland into a desktop plus mobile suite

Harmonicland (`~/Code/harmonicland`, Vite/TS, already connected over ChordLink; see [../chordlink.md](../chordlink.md)) could share this instrument work.
That would move the decision from "iOS AUv3 only" toward a cross-platform DSP core with multiple plugin wrappers:
- AUv3 on iOS
- AU/VST3/CLAP on desktop
- WebAudio/WASM for Harmonicland in the browser

Unresolved: one shared C++ DSP core (JUCE, iPlug2 or hand-rolled) vs. separate per-platform engines, and whether the Music Theory Core also moves to a shared form.
This choice changes the language and framework for everything in the table above, so decide it before writing any instrument code.

### 3. Listening and testing pipeline for existing instruments (built outside coding sessions)

This is the user's own process: play the same chord progressions through GarageBand, Logic and other apps' instruments to study their UX and sound.
It also covers learning the mathematics behind them (oscillators, filters, FM, sampling, physical modeling, reverb).
Perfecto's MIDI output already makes it a consistent test driver across apps.

### 4. LLM-assisted formal proofs (watch this space)

Track progress in LLM-assisted formal verification (Lean and similar tools).
Possible uses:
- proving properties of the pure Music Theory Core (voicing rules, inversions, voice leading)
- proving DSP invariants: filter stability, no allocation on the render path, bounded output

This is not actionable yet; revisit when starting instrument work.
