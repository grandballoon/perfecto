# Feature Spec: Dissonance Lab (Perfecto view)

## Goal

Add a new view to Perfecto that helps beginners *hear* what makes an interval consonant or dissonant. It renders intervals with an additive synth whose acoustic cues can be exaggerated, isolated, and gradually faded back to a normal tone.

The two perceptual cues this view targets:

1. **Roughness / beating:** near-coincident partials beat at their difference frequency. Slow beats (~3–7 Hz) are heard as a wobble. Fast beats (~30–70 Hz) are heard as grit.
2. **Harmonicity:** consonant intervals' partials fit one harmonic series with a clear implied root. Dissonant ones don't.

## Before writing code

- Read the existing project structure, audio engine setup (AudioKit), CoreMIDI virtual port code, and existing SwiftUI navigation. Integrate with them; don't build a parallel engine.
- Reuse the existing MIDI input path. Note-on/off events from hardware or the virtual port should drive this view while it's active.
- When the view is active, this view's synth replaces Perfecto's normal chord voice. Restore the normal voice on exit.
- Propose a short plan (files to add/modify) before implementing.

## Architecture

### Audio: `DissonanceSynth`

- Use a custom additive synth with **per-partial control**, implemented as an `AVAudioSourceNode` render block, or an AudioKit-compatible custom node, attached to the existing AudioKit engine.
- Make it real-time safe:
  - no allocation, locks, or Swift class/ARC traffic in the render callback;
  - preallocate partial arrays;
  - pass parameter changes via atomics or a lock-free ring buffer;
  - smooth all gain and frequency changes (~10–20 ms) to avoid clicks.
- Voices: up to 2 notes, which is all this view needs. Maybe allow 3 later.
- Partials per voice: configurable, 1–16, default 10. Amplitude rolloff 1/n by default (sawtooth-like); expose a "brightness" exponent so the rolloff is 1/n^b.
- Envelope: organ-like (attack ~30 ms, full sustain while held, release ~150 ms). No decay. This is essential so beats have time to be heard.
- Tuning modes per interval:
  - **12-TET** (default);
  - **Just intonation**, which maps the interval to the nearest simple ratio: 16/15, 9/8, 6/5, 5/4, 4/3, 45/32, 3/2, 8/5, 5/3, 16/9, 15/8, 2/1.

### Analysis: `IntervalAnalyzer` (pure Swift, unit-tested)

Given two fundamentals and partial counts/amplitudes, compute:

- **Partial list** for each note: frequency f·n with inharmonicity 0 for now.
- **Colliding pairs:** every cross-voice pair (i, j) whose separation is under ~1 critical band. Use ERB(f) = 24.7 · (4.37·f/1000 + 1), with f the mean of the pair.
- **Per-pair roughness** using the Plomp–Levelt curve, in Sethares' parametrization:
  - s = 0.24 / (0.0207·f_min + 18.96)
  - d = min(a_i, a_j) · (e^(−3.5·s·Δf) − e^(−5.75·s·Δf))
- **Total roughness:** the sum over pairs. Use it for a meter and for sorting the "most guilty" pairs.
- **Beat rate** of each colliding pair: |f_i − f_j|.
- **Implied fundamental:** the approximate GCD of the two fundamentals via their nearest simple ratio p/q (limit denominators to ≤16). Root = f_low / q. Report "no clear root" if the ratio needs denominators above the limit, or the root falls below ~20 Hz.

## Enhancement controls

Each control is a toggle or slider. All are independently switchable for A/B comparison.

1. **Close voicing:** collapse the played interval into one octave, with the lower note placed in a target register (default ~200–400 Hz). An "Original register" toggle plays it as keyed.
2. **Spectral richness:** sliders for partial count and brightness.
3. **Spotlight:** boost the top-N roughest colliding pairs (default N = 1, gain +12 dB) and attenuate all other partials (default −18 dB). Toggle on/off to compare spotlight vs full tone.
4. **Beat-rate shaping:** micro-detune the spotlighted partial of the upper voice so its beat with the lower voice's partial hits a target rate.
   - Presets: **Wobble** (5 Hz), **Grit** (45 Hz), **Natural** (no shaping).
   - Only shift that one partial, not the whole note, so pitch identity is preserved.
5. **Tuning reference:** a 12-TET / Just toggle. Used to demonstrate the beatless target state for consonant intervals.
6. **Explicit modulation crutch:**
   - Option A: amplitude-modulate the spotlighted pair's sum at its beat rate, adjustable depth.
   - Option B: synthesize a quiet sine at the difference frequency.
   - Off by default at higher lesson stages.
7. **Implied-root tone:** a quiet sine at the implied fundamental, raised by octaves until it's ≥ 40 Hz. Silent when "no clear root."
8. **Dichotic mode:** low note hard-left, high note hard-right, and no spotlight/AM. Show a headphones-required notice.

## Scaffold presets (fading)

Add a "Level" picker that sets the controls above in bulk. The user can still override any single control.

| Level | Voicing | Partials | Spotlight | Beat shaping | Crutch | Root tone | Tuning |
|---|---|---|---|---|---|---|---|
| 1 | Close | 12 | On | Wobble | AM on | On | Just for consonant |
| 2 | Close | 12 | On | Grit | AM on | On | 12-TET |
| 3 | Close | 10 | On | Natural | Off | On | 12-TET |
| 4 | Close | 8 | Off | Natural | Off | Off | 12-TET |
| 5 | Original | Piano-like (8, b=1.5, add decay) | Off | Natural | Off | Off | 12-TET |

## UI (SwiftUI)

- **Interval display:** note names, interval name, semitones, and the JI ratio.
- **Roughness meter:** a horizontal bar from the analyzer's total roughness, normalized against the minor 2nd at the same register.
- **Partial ladder visualization:**
  - two columns of partials on a shared log-frequency axis;
  - lines connect colliding pairs, with line thickness for roughness and a label for the beat rate in Hz;
  - spotlighted pairs are highlighted;
  - an implied-root marker sits at the bottom.
- **Beat envelope strip:** a small scrolling amplitude trace of the spotlighted pair, so the wobble is visible.
- **Controls:** Level picker; a collapsible "Advanced" section with all the controls from the enhancement section.
- **Interval pads:** on-screen buttons for the 12 intervals above a chosen root, for use without a MIDI keyboard.
- **A/B button:** hold to temporarily bypass all enhancements (plain 12-TET, current partial settings).
- Use the existing design language, and keep it accessible: Dynamic Type, VoiceOver labels on meters.

## MIDI behavior

- Use the two most recent held notes. A third note replaces the oldest.
- Velocity scales the overall gain only. It doesn't affect the analysis.
- Single held note: play it normally, with no analysis.

## Testing

- **Unit tests for `IntervalAnalyzer`:**
  - P5 at A3 → strongest pair is partial 3 vs 2, ~0 Hz beat in JI, ~0.5 Hz beat in 12-TET;
  - m2 has higher total roughness than P5 at the same register;
  - tritone in JI → no clear root under the denominator limit, or a very low root;
  - ERB and roughness values match hand-computed references.
- **Render-block test:** offline-render 1 s of a 12-TET major third and confirm via FFT that the expected partials are present at the expected amplitudes.
- **Manual QA checklist:** no clicks on parameter changes; no xruns at 64-frame buffers on an older device; dichotic panning correct.

## Out of scope (for now)

- Piano inharmonicity modeling.
- Quiz/scoring mode. Design the view so a quiz layer can drive it later, by exposing an API to play an interval with a given Level.
- Web/desktop port. Keep `IntervalAnalyzer` platform-agnostic so it can be ported.
