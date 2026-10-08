Please take a look at the table of content for Open Music Theory, and tell me what parts of its curriculum are represented, and what are not represented, in this repo. Please break it down into four tiers:

1. Currently explicitly represented in some form in the UI
2. Not quite explicitly represented, but a short conceptual jump, or would otherwise be simple to edit our app to show.
3. Not currently represented, but conceptually related through indirect or multi-step process of conceptual linkage
4. Not at all represented

https://viva.pressbooks.pub/openmusictheory/




I compared the Open Music Theory (v2) contents against the theory core, the views and the docs. This is from reading the code, not from running the app.

Overall, Perfecto covers OMT's Fundamentals (minus notation), the chord-vocabulary half of Jazz and the modes chapter well. It has almost nothing of counterpoint, classical form, functional/chromatic harmony as analysis, or post-tonal theory.

## Tier 1: explicit in the UI

| OMT chapter | Where it shows |
|---|---|
| Half steps, accidentals, pitch names | ROOT chips in the Key panel (all 12, spelled with sharps only); note names on the solo strip cells |
| ASPN (octave numbers) | OCTAVE control; octave number on sequencer notes |
| Tempo (from "Other Aspects of Notation") | BPM control |
| Simple and compound meter, time signatures | Sequencer picker: 2/4, 3/4, 4/4, 5/4, 5/8, 6/8, 7/8, 9/8, 12/8; step grid drawn in beats and bars |
| Major scales, scale degrees | SCALE chips; seven degree keys |
| Minor scales | Natural, harmonic and melodic minor are all offered |
| Diatonic modes (Fundamentals and 20th-century parts) | Dorian, Mixolydian and Lydian as key scales; all 21 modes of major, melodic and harmonic minor named on the chord grid's rows |
| Triads | maj, min, dim, aug, by degree and on the joystick |
| Seventh chords | maj7, 7, min7, min7♭5, min(maj7), dim7 |
| Roman numerals | Chord keys labelled I, ii, vii° and so on, cased by quality per scale ([ChordKeysView.swift:54](Views/ChordKeysView.swift#L54)) |
| Chord symbols (Jazz) | Live chord readout such as "D min7"; lead-sheet names generated for every grid cell |
| Altered and extended chords (Chromaticism) | 9, 11, 13, add9, 6/9, 7♯9, 7♭9, 7alt, maj7♯11; grid columns Triad to 13th |
| Chord-scale theory (Jazz) | The chord grid is chord-scale theory: each row is a mode, each chord is thirds stacked through it. The solo strip derives its notes from the chord's scale and dims the passing tones |

## Tier 2: a short jump, or simple to show

- **Inversion.** Root, first and second inversion exist in the core and in every chord event, but I found no control for them in the views or view models.
- **Voice leading and jazz voicings.** A `voiceLeading` flag exists with no control; the 11th and 13th are already voiced by dropping the third or the eleventh.
- **Slash chords.** `Voicing.bassNote` exists but nothing produces it.
- **Pentatonic and blues scales** (Blues Melodies and the Blues Scale; Pentatonic Harmony). All three are in `ScaleType` but hidden; the solo strip already produces major and minor pentatonics without naming them.
- **Remaining modes as keys.** Phrygian, Locrian and the rest are in the catalog but not offered as key scales.
- **Enharmonic equivalence and flat spellings.** Names are sharps only, so F major shows A#; spelling by key is one pure function.
- **Circle of fifths.** The root chips are chromatic, and the "Circle" chord layout is degree order, not fifths.
- **Intervals; Pitch and pitch class; Integer notation.** The core is integer notation throughout, but none of it is shown.
- **Scale-degree names and solfège.** A label swap on the degree keys.
- **Modal mixture.** Choosing a grid row other than the degree's own mode is borrowing from a parallel mode, and the joystick's "Flip 3rd" is the simplest case; it is never called that.
- **ii–V–I, blues harmony, four-chord, blues-based and modal schemas.** All playable, and the sequencer stores progressions as degrees with Roman numerals; there are no named progressions or presets.
- **Syncopation, dots and ties.** Sixteenth steps, JOIN and SPLIT, and loops kept as played all do this without notation.
- **Swing rhythms.** The timeline is 480 ticks per quarter and `spec.md` lists a swing control, but the sequencer spec defers it.

## Tier 3: indirect or multi-step linkage

- **Phrase model, cadences, predominants, V⁷, prolongation** (most of the Diatonic Harmony part). The chords are there, but nothing knows function, phrase position or cadence type; the 6/4 and inverted-V⁷ chapters also wait on inversion.
- **Tonicization and modulation.** Dom 7 works on any diatonic degree, but roots are limited to the seven scale degrees. A sequencer note can carry its own key, which is the only route to a real secondary dominant or a key change.
- **Neapolitan, tritone substitution, mediants.** Same limit: they need chromatic roots, reachable only by a per-note key.
- **Neo-Riemannian progressions.** A standalone Tonnetz is item 3 in [next-phase-plan.md](docs/next-phase-plan.md) but not built; "Flip 3rd" is the P move.
- **Embellishing tones.** The solo strip's root / chord tone / passing roles are the same idea, without the types (neighbour, suspension and so on).
- **Borrowed divisions, hypermeter, metrical dissonance.** Ticks could hold triplets and loops fold onto the first loop's length, but the grid is sixteenths only.
- **Form in pop music, AABA, verse-chorus, ground bass.** Bars, duplicate and looping layers are the raw material (a loop is a ground bass); there are no sections.
- **Texture, texture in pop, melody and phrasing.** Layers, the arpeggiator, strum and solo-over-chord produce textures but nothing names them.
- **Drumbeats.** The drum module is specified and deferred.
- **Dynamics and articulations.** Block versus strum exists; velocity is fixed and an open item in `todo.md`.
- **Orchestration (core principles, subtle colour changes).** Related only through the 14 presets and the slide-played filter, chorus and reverb.
- **Pitch-class sets, collections, equal divisions of the octave.** Chord shapes are interval sets, and augmented, dim7 and the acoustic and altered scales exist; there is no normal order, prime form, whole-tone or octatonic collection.
- **The piano keyboard.** No keyboard is drawn; the solo strip is the nearest thing.

## Tier 4: not represented

- **Staff notation.** Notes, clefs, ledger lines, grand staff, key signatures as notation, beaming, rests, conducting patterns, graphic notation.
- **Figured bass and SATB style.**
- **Sight-singing and dictation.**
- **All of Counterpoint and Galant Schemas.** The five species, 16th-century style, fugal exposition, galant schemas, rule of the octave.
- **Classical form.** Phrase archetypes (sentence, period, hybrids), expansion and contraction, binary, ternary, sonata, rondo.
- **Chromatic harmony as technique.** Augmented sixths, common-tone chords, harmonic elision, chromatic modulation, chromatic sequences, the omnibus.
- **Pop chapters with no hook.** Classical schemas, puff schemas, fragile, absent and emergent tonics.
- **Post-tonal analysis.** Set class, interval-class vectors, 20th-century rhythmic techniques, all of Twelve-Tone Music.
- **Transcription from piano.**
- **Stylistic periods, the anthologies and the workbooks.**


Most of that comes from two design choices: chords are computed from scales and modes instead of looked up, and the sequencer stores degrees, not notes. Those two put the whole Fundamentals-to-chord-scale spine of the book on screen almost for free.

The gaps are just as structural. Everything in Tier 3 and 4 that is harmony (tonicization, Neapolitans, tritone subs, mediants) is blocked by the same thing: a chord's root can only be one of the seven scale degrees. Everything that is counterpoint, form or notation is outside what a chord instrument is for.