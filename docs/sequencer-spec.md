# Sequencer spec: one timeline for sequences and loops

> **Status (2026-10-06): parts A to E of section 8 are built; E awaits review on a device, and F (entry from the keys, a note's own settings) is not built.**
> This is step 5 of [audio-engine-spec.md](audio-engine-spec.md), and it answers [../sequencer.md](../sequencer.md), which states what is wanted.
> It replaces sections 6.1, 6.2 and 6.2.1 of [../spec.md](../spec.md) as each part lands.

## 1. What changes

Today there are three things that repeat music, and none can become another.

| | What it holds | Where it lives |
|---|---|---|
| Sequencer | Sixteenth-note steps, each a chord with a gate | `SequencerState`, played by `SequencerMode` |
| Play-mode loop | Up to six layers of recorded audio | `QuickLoopState`, `Looper` |
| Looper mode | Two tracks of recorded audio | `LooperMode`, `LooperState`, `Looper` |

After this there is one: a **timeline** of notes in layers.
A sequence entered by hand is a layer, and so is a loop recorded in Play mode.
Either can be played under Play mode, and either can be opened and edited in the sequencer.
Looper mode is removed.

## 2. Decisions made

Decided on 2026-10-06:

1. **The editor stays a grid of chits.** A chord spans as many chits as it lasts, drawn as one wide chit. One layer is shown at a time, chosen from layer tabs. A note that does not sit on the grid is drawn at its nearest step with a mark.
   A note belongs to that nearest step for editing too, and is on every step it is drawn across, so selecting any step of a wide chit selects the note.
2. **The first loop sets the tempo.** A loop recorded with no sequence yet is taken to be a whole number of bars, choosing the count that puts the tempo nearest the current one, and the tempo is set to match. Nothing played is moved or cut. The bar count can be halved or doubled afterwards.
3. **Looper mode is removed**, with its screen and state. Mute and volume belong to layers.
4. **Time signatures are in the first version**: one for the whole timeline. Triplets, swing, and signatures that change mid-sequence are not.
5. **A slide played inside a held note is recorded** (from the audio engine decisions), as changes on the note.

## 3. The model

Pure data, in `Core/Timeline/`, with no clock, audio or UI in it.

### 3.1 Time

Time on a timeline is whole **ticks**, 480 to a quarter note, the same as the MIDI export.
A step, the grid's unit, is a sixteenth: 120 ticks.
A note may start on any tick and last any number, so a loosely played loop is kept exactly as it was played; the grid is how it is drawn and edited, not how it is stored.

```swift
struct TimeSignature { var beats: Int; var unit: Int }   // 4/4, 3/4, 6/8, 7/8…; unit is 4 or 8
```

A bar is `beats` notes of 1/`unit`: 1,920 ticks in 4/4, 1,440 in 6/8.
`MusicalTime` keeps stating steps per beat; "16 steps to a bar" stops being true anywhere, and bar lengths come from the signature.

### 3.2 Timeline, layers, notes

```swift
struct Timeline {
    var signature: TimeSignature
    var barCount: Int             // its length; every layer shares it
    var layers: [Layer]
    var loop: Range<Int>?         // ticks; nil repeats the whole timeline
}

struct Layer {
    let id: UUID
    var notes: [TimelineNote]     // in order of start
    var isMuted = false
    var volume: Float = 1
}

struct TimelineNote {
    var start: Int                // ticks from the start of the timeline
    var length: Int               // ticks, at least 1
    var chord: ChordSpec          // which chord: degree and color
    var pitch: NotePitch          // the whole chord, or one note of it (Lead mode)
    var articulation: Articulation
    var playing: NotePlaying      // key, octave, sound, effects: each either its own or the live one
    var changes: [SoundChange]    // a slide played while it was held
}
```

All layers share one length, as loop layers do today.
A layer is one line of chords, one at a time, so its notes never overlap; a take longer than the timeline becomes one layer for each time round.

### 3.3 A note's own settings, or the live ones

Today a sequencer step plays in whatever key, octave and sound are chosen now, and a recorded loop keeps the ones it was played with.
Both are right, so a note says which, setting by setting:

```swift
struct NotePlaying {
    var key: Key?                     // nil follows the live key
    var octave: Int?
    var preset: SynthPreset?
    var effects: NoteEffects?         // arpeggiator, filter, chorus, reverb, as set for this note
}
```

- A note entered in the sequencer starts with everything following: change the key and the sequence changes key, as now.
- A note recorded from playing has everything its own: the loop keeps its key, octave, sound and effects, as now.
- "Change its key without changing the chord number" is setting `key` on the selected notes. Setting it back to following is one tap.

What is recorded is the chord *before* the arpeggiator, with the arpeggiator's settings among its effects, so an arpeggiated loop is replayed by arpeggiating it again and its pattern and speed stay editable.

Until the kernel is in (audio engine step 8), the engine has one sound and one set of effects for everything.
A note's own preset and effects are stored and edited from the start but heard only then; key and octave are heard at once, and so is its arpeggiator, since each layer has one of its own.
[../sequencer.md](../sequencer.md) accepts this.

### 3.4 Editing, as functions on the model

Every edit is a pure function from a timeline to a timeline, so each is tested without a screen and Undo is a stack of values.

| Edit | What it does |
|---|---|
| Place | Puts a chord on the selected steps, one note per step, replacing what was there |
| Join / split | Makes each run of selected steps one long note (never a shorter one); cuts a note at the edges of the selected steps it is drawn across |
| Length | Lengthens or shortens a note by a step; the gate sets how much of its last step it sounds for |
| Snap | Moves starts and ends to the nearest step line, for a loosely played loop |
| Rest | Empties the selected steps; a note held across more steps than those keeps the rest of itself |
| Set playing | Sets or clears a note's own key, octave, sound or effects |
| Replace | Swaps a note's chord for one played on the keys, keeping its time |
| Bars | Adds a bar at the end; removes a bar, moving later notes up; trims empty bars from the end |
| Halve / double | Reinterprets the same notes as half or twice as many bars (for a loop whose bar count was guessed wrong) |
| Signature | Changes the time signature, keeping notes on their ticks |
| Layers | Adds, removes, mutes and duplicates layers |

### 3.5 From a timeline to sound

One pure function compiles a layer to what is played:

```swift
func compile(_ timeline: Timeline, layer: Layer.ID, live: LiveSettings) -> [TimedChord]
```

Each `TimedChord` is a start tick, an end tick, and the `ChordEvent` with its resolved key, octave, sound and effects.
Playback and the MIDI export both read this list, so they cannot disagree; the export stops re-implementing gate and tie.
A note that runs past the loop's end is cut there.

## 4. Playback

Playback is not a performance mode.
Like the arpeggiator, it is a layer under every mode: a `TimelinePlayer` runs the timeline against the clock while the chord keys go on playing over it.

- The clock gains a musical position (`beats`, which follows tempo changes), so "where is the playhead" is arithmetic, and the player asks the clock for a call at each chord's start and end (`after(beats:)`).
- Each layer plays through its own arpeggiator and `NotePlayer`, so layers overlap freely through the same note sinks (this is what the note seam was for).
- An edit while playing takes effect from the next chord: the player recompiles and carries on from the same position.
- `SequencerMode` goes. The sequencer becomes a screen that edits the timeline; PLAY/SEQ switches screens, not modes, and playback carries on across the switch.

Voices: the pool is 8 today and several layers of chords will ask for more.
It is raised to 16 for this step, and notes beyond that take over the oldest voice; the kernel's 64 arrive with step 8.

## 5. Recording

### 5.1 A loop, in Play mode

The LOOP button works as now: tap to start a take, tap to close it.
What is recorded is chord events with their clock positions, not audio.

- **No timeline yet** (no notes anywhere): the take sets the length and the tempo, by decision 2. Its notes are placed by proportion, so their timing relative to one another is exactly as played.
- **A timeline exists** (a sequence was entered, or a first loop made): the take becomes a new layer, folded onto the timeline's length at the point where it was played, as loop layers fold today.
- A key still held when the take closes ends there.
- A take with no notes, or shorter than half a second, is dropped, as now.
- Up to 6 layers, as now.

The loop bar's numbered chits are the layers: tap to mute or unmute, and the trash chit deletes, as now.

### 5.2 Into the sequencer

Two ways, both from the chord keys shown on the sequencer screen:

- **Step entry.** With a step selected and the keys armed, each chord played is placed on the selected step and the selection moves to the next, so a progression is entered by playing it in order with no regard to timing.
- **Replace.** With notes selected, a chord played replaces theirs and nothing moves.

Both take the chord as played, color and all.

## 6. The sequencer screen

- **Layer tabs** above the grid: one per layer, and a plus. The selected layer is the one shown and edited; the others play on.
- **The grid.** Rows of steps, grouped by beat, bar after bar, in the two layouts there are now (pages or one scrolling column). A note is one chit as wide as its steps, wrapping onto the next row if it crosses a beat. A note off the grid has a mark; a note with its own key, octave or sound has a small tag.
- **Selection** is by step, by tap and by drag, as now. An edit applies to the notes on the selected steps.
- **The step editor** keeps degree, color, rest and length (was gate), and gains Join, Split and Snap, and a row for the note's own key, octave, sound and effects, each showing "live" until set.
- **Bars**: add, remove, and now the time signature, halve/double, and trim.
- **The keys**: a strip of the chord keys for step entry and replace.

Rows per beat follow the signature: four steps a row in 4/4 and 3/4, six in 6/8, 9/8 and 12/8, and four with a short last row in 5/8 and 7/8.

The screen is reviewed in SwiftUI on the device, as every screen here is.

## 7. What is removed

| | Lines |
|---|---|
| `SequencerMode`, `LooperMode`, `LooperState`, `LooperView` | about 430 |
| `Looper`, `LoopCapture`, `LoopMath`, `LoopTracks`, and the looper's wiring in `AudioSink` | about 660 |
| `SequencerStep`, `SequencerPattern`, and the timing rules in `SequencerMidiRenderer` | about 120 |
| Their tests (`LooperTests`, `LoopMathTests`, and parts of the sequencer tests) | about 600 |

The mic sample is the one thing that loses looping until the kernel captures audio (audio engine step 11); its mode has no entry point in the UI today.

A saved pattern in today's format is read once and becomes the first layer.

## 8. Order of work

Each part leaves the app working.

| | Part | Done when |
|---|---|---|
| A | ~~The model: time, timeline, notes, the edits of 3.4, `compile`, and the clock's musical position~~ (done) | Model tests pass |
| B | ~~`TimelinePlayer`, and the sequencer's playback moved onto it behind today's screen~~ (done). The screen still edits one layer a step at a time, through `SequencerStep`, which reads a long note as tied steps. `SequencerMode` is only the screen now; it still stops playback on the way out, until Play mode has the loop bar to stop it from (part D). | The sequencer's tests pass against the timeline |
| C | ~~The MIDI export reads `compile`~~ (done): every unmuted layer is a track, in the timeline's signature | Export tests pass; the renderer's own timing rules are gone |
| D | ~~Loops as layers: the recorder, tempo from the first loop, the loop bar on layers. Audio loopers and Looper mode deleted~~ (done). A voice to each layer; the sequence plays on under Play mode, with a play/stop chit in the loop bar; a new sequence is empty | A loop recorded in Play mode plays as notes and appears in the sequencer |
| E | ~~The screen: stretched chits, layer tabs, join/split/length/snap, signatures, bars~~ (built, not yet seen on a device). Double and halve change the tempo to match, so the notes sound as they did. `SequencerStep` is left only as the old saved format and a way to write a pattern in a test | On-device review |
| F | Entry from the keys (step entry, replace), and a note's own key, octave, sound and effects | On-device review |

## 9. Open questions

1. **The loop inside a sequence.** Until part B any set of steps could be looped, even a scattered one, and exactly those steps played in order. With notes of any length that no longer has a clear meaning, so the loop is now one stretch of time (from the first selected step to the last). Say if the scattered loop matters.
4. ~~What a new sequence starts as.~~ Decided 2026-10-06: empty.
2. **Voice leading and inversion per note.** `ChordContext` carries them and every chord today is root position with voice leading off. The note model has no field for them until they are a setting somewhere.
3. **Per-layer volume.** In the model from the start, but heard only with the kernel, like a note's own sound.
