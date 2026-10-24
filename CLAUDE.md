# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

**Perfecto** — an iOS chord performance instrument. The full v1 spec is in `spec.md`.

Stack: iOS 17+, iPhone (portrait + landscape), Swift 6, SwiftUI, an audio kernel of our own in C++ (no audio library), MVVM with `@Observable`, CoreMIDI.

**The same app runs on the Mac**, built with Mac Catalyst (the iPad's idiom, so every control looks as it does on the phone).
There its "Perfecto" MIDI source is on the machine the DAW runs on, so no network session is opened (`MidiNetwork`), and the MIDI button silences the app's own sound as on the phone (`AudioOutput.isExternalSynth`).
A mouse is one finger.
A window with room for it is laid out for the desk (`DeskLayout`): the keys' column as a phone upright shows it, the sequencer beside it, and the menu as a column of its own that covers nothing.
The sequencer has an arrangement of its own there (`SequencerView.besidePlay`): the steps twice as tall, above its controls and the keys and coloration that set a step's chord.
The keys are always played there, so there is no sequencer mode to be in.
The Tonnetz can take the sequencer's place there (`DeskPane`).
It is the phone's screens side by side behind one threshold, and is to be replaced when the layout as a whole is thought through again.

## Architecture

The codebase is split into strict layers with no upward dependencies:

```
SwiftUI Views
    ↓
ViewModels (@Observable): PerformanceState, SequencerState, QuickLoopState, PadsState
    ↓
Performance Engine: PerformanceMode protocol + 7 per-mode implementations
    ↓
Music Theory Core  ← PURE Swift only (Int/Array, no UIKit/AudioKit/Foundation)
    ↓
ChordEventSink protocol (receives ChordEvent)
    ├── Arpeggiator        →  one note at a time while it is on
    │     └── NotePlayer   →  chords become notes with ids; NoteSink protocol
    │           ├── KernelSink   →  KernelAudioUnit: the audio kernel (voices, chorus, delay, reverb, limiter), run by AudioOutput
    │           └── MidiSink     →  CoreMIDI ("Perfecto" note source)
    └── MidiAnnouncerSink  →  ChordLink SysEx ("Perfecto Link"; see chordlink.md)
```

**Music Theory Core purity is a hard constraint.** It is pure Swift (Int/Array only), testable in isolation as pure functions of its inputs. Never add UIKit, AudioKit, or Foundation imports to anything under `Perfecto/Sources/MusicTheoryCore/`.

**ChordEventSink decouples event generation from consumption.** Every sink receives the same `ChordEvent`s independently — neither knows about the others or reads app state. A `ChordEvent` carries the voicing, its `Articulation` (block or strum), and the `ChordContext` that produced it; the protocol's doc states the contract (`playChord` replaces what is sounding).

**Below the chords are notes.** `NotePlayer` is the one place a chord becomes note-ons and note-offs (and where a strum is spread out), so audio and MIDI are `NoteSink`s that know nothing of chords. Every note has a `NoteID` chosen by its sender, and a sink ends only the note it is told to: one `NotePlayer` is one line of chords, and several can sound at once through the same sinks. Every note also carries its `NoteSound` (preset, chorus, reverb, vocoder, and how far it is bent from its pitch and how loud), which is its player's: the keys' player follows the effects as played, and each layer's is given its chords' own, so a loop keeps the sound it was recorded with while the keys play another over it. The player also spreads a chord's notes a little from left to right (`NotePlayer.spread`). A change to a player's sound reaches the notes it holds (`noteChange`), which is how a slide is heard; a new chord's sound leaves the last chord's notes as they were (`startNotes(in:)`).

**The audio kernel makes every sound** (`docs/audio-engine-spec.md` has the design and what is still to build). It is portable C++ behind a C interface (`Perfecto/Sources/PerfectoKernel`): timed events in, samples out, and nothing in its render call allocates, locks or waits; its tests are built to stop on any allocation made while rendering. An event takes effect on exactly the frame it names, however rendering is divided into calls. A note names its sound, one of the patches the kernel was given (`perfecto_kernel_set_sound`, before playing: it builds the patch's wavetables), and has its own brightness, pan, and chorus and reverb sends, which a note change glides. It also has a bend, in semitones from its pitch, and a level, which a note change glides too (its filter and a capture's speed follow the bend): a note changed little and often is heard to slide, which is how the Trautonium's bars are played. A patch can have an LFO, a slow sine that starts with each note and moves its pitch, the width of its pulse waves and its filter (`PerfectoLfo`, `SynthPatch.LFO`). Its operators can be up to seven copies of themselves a little out of tune (`unison`), and can wander from their pitch differently for every note (`drift`), by a chance that starts from the same place each time the kernel is readied. A patch can be sine partials in place of its operators (`PerfectoPatch.additive`, `SynthPatch.partials`), each of which a note sets apart while it sounds (`PerfectoEventPartialChange`): how strong, how many Hz from its place in the series, and how it swings in strength, all glided over 15 ms; that is the Dissonance Lab's sound. A patch can also have noise beside its operators (swept, a breath; steady, air), a drive after its filter, and a glide: a note that follows another of its sound with no gap starts at that note's pitch (the nearest, of a chord's) and slides to its own. The kernel has the 64 voices and chooses which to give up. The voices are added into one chorus, one delay and one reverb (`MixBus.hpp`) and a look-ahead limiter, whose 1.5 ms is the kernel's latency. `KernelAudioUnit` hosts it as an Audio Unit, and the render block is Objective-C++ (`PerfectoKernelHost`) so the render thread never runs Swift. `KernelSink` is the `NoteSink` in front of it: it loads the presets as kernel sounds (`SynthPatch.kernelPatch`) and turns a `NoteSound` into the kernel's numbers. `AudioGraph` is the engine and what is connected in it: the unit has an input, and an engine in real time renders it only while something is connected there, so a silent source always is (`KernelLiveTests` runs the graph in real time). An engine that has opened the mic cannot start in a session that only plays, so the graph starts a new engine once the mic is let go, with the same unit in it (`AudioOutputLiveTests`, which only a phone makes fail). `AudioOutput` keeps it running across route changes, and `AudioSession` is the one place the session is configured.

**The kernel records, too.** It has four captures (30 seconds each, one channel), and a capture event starts or stops recording its input into one on an exact frame. A recording that ends is made ready to play (cut to its sound, brought to full level), and a patch can name a capture in place of its operators, played faster or slower by pitch: that is the mic sample (`SynthPreset.micSample`), a sound like any other, so it is played, sequenced and looped as notes. `SampleRecorder` asks for the recording, watches the kernel for its end, opens the mic only meanwhile (through `AudioOutput`), and keeps the sample on disk; `MicSampleState` is what the Sound panel shows of it. Whatever needs the mic asks `MicAccess`, which puts the system's question once through `PermissionGate`.

**The vocoder is an effect that hears.** A note's send to it (`VocoderSettings`, on `NoteSound` like the others) is the share of the note that is not heard itself but shaped by the voice at the kernel's input, through a bank of bands (`Vocoder.hpp`). `PerformanceState` opens the mic while the vocoder, or a key zone of it, is on (`EffectsState.hearsTheMic`, `AudioOutput.isVocoding`), or a pad that has it on can sound; on the speaker the device's echo cancelling is switched on with it. With the vocoder off or nothing to hear, notes sent to it are heard whole.

**MasterClock drives everything timed.** Repeat, the timeline (sequences and loops), the arpeggiator and strums all use it; nothing between a key and its notes sleeps or keeps a timer of its own. It is behind a `ClockTickable` protocol so test doubles can replace it without changing callers. Modes count its ticks (sixteenths); anything finer or off that grid asks it for a call: over and over (`every(beats:)`, as the arpeggiator does), or once (`after(beats:)` for a step's gate, `after(seconds:)` for a strum's notes and Repeat's gap). Both clocks keep their calls in a `ClockSchedule`, which makes them in the order they fall due (a tick first) and times a call asked for inside another from that call's due time, so the real clock and `ManualClock` follow the same rules and timing tests never wait on real time.

**Notes carry times.** Every note-on, note-off and change is stamped with the moment it takes effect (`ClockTickable.time`: inside a call of the clock's, the moment that call was due, however late the main thread got to it). `KernelSink` turns the moment into the kernel's frame (each render tells `PerfectoKernelHost` when it is for) and `MidiSink` into a MIDI timestamp. What the clock plays (a layer's `NotePlayer`) adds a short lead (`NotePlayer.sequencedLead`, 50 ms), so its notes are always sent ahead of their moment and sound on exactly their frame: the timeline is heard that much after the clock's position, all of it alike. The keys' player has no lead, since a key sounds at once; what the clock does on its behalf (a strum's later notes, a live arpeggio, Repeat) is stamped but has usually just passed, so it is as punctual as the main thread. A loop recorded over layers is placed where it was heard, the lead earlier than the clock had it (`QuickLoopState`).

**Effects are layers, not modes**, so they work under every mode. The arpeggiator is a note effect: a `ChordEventSink` in front of the note sinks, so audio and MIDI hear the same notes, while ChordLink still hears the whole chord. One pass over a chord takes one cycle (`ArpeggioCycle`) however many notes it has. The chorus, reverb, delay and vocoder are sound effects, and each note has its own of them (`NoteSound`): the kernel has one chorus, one reverb, one delay and one vocoder that notes send into, and a limiter that keeps layers from clipping. The arpeggiator has two patterns, offered as two effects: Arpeggio 1 goes up and Arpeggio 2 down (`ArpeggioPattern`). The chorus, the reverb and the delay are each one sound, on or off: how much of a note goes to them, the chorus's speed, the reverb's size and the delay's feedback are constants on their settings, and `KernelSink` sets the kernel's mix to them once. The delay's echoes are a dotted eighth note apart (`DelaySettings.beats`), from side to side, so `KernelSink` is told the tempo (`TempoControl`, by `PerformanceState.setBPM`); a change of tempo bends the echoes on their way, as a tape would. The delay is a send like the reverb, so switching it off leaves its echoes, and an export goes on until they have died away (`Timeline.hasEchoes`). There is no filter among the effects. A note has a brightness (`NoteSound.brightness`, the kernel's for each note), which is not an effect but can be played by the slide (see the key gestures). An effect's settings are plain data (`EffectSettings`: `ArpeggiatorSettings`, `ChorusSettings`, `ReverbSettings`, `DelaySettings`, `VocoderSettings`), edited through `EffectsState`, which can be read as set (`asSet`) or as played (`asPlayed`). Adding a sound effect = a settings struct, a field on `NoteSound` and its place in the kernel's mix, an `EffectChoice`, and a card in `EffectsPanel`.

**A loop's effects are its own.**
A recorded note keeps the effects it was played with (`NotePlaying.effects`), so nothing set or played for the keys afterwards reaches it.
They are edited by themselves on the Effects page, which shows the keys' effects or one loop's (`EffectsPanel.control`): an edit changes that setting on every note of the layer and every point of a slide recorded in it (`Layer.editEffects`, `SequencerState.editEffects(ofLayer:)`), and a run of edits is one undo.
The chord a layer is sounding takes an edit up at once without being struck again (`TimelineVoice.change`).
Two things are shared: the mic is open to the vocoder only while the keys' vocoder is on (or a pad's, see the pads), and over MIDI the effects' controllers are the keys' alone, on the one channel.

**Key gestures play effects.** What a finger does on a chord key beyond pressing it is a control, read in the same place fingers become keys (`ChordKeyTouches`) and reported by `ChordKeySurface` beside the key changes, so every layout gets it. The first is the slide: how far up its key the finger is (`ChordKeySlide`, 0 at the bottom to 1 at the top). A key has a shape (`KeyShape`: a rectangle, a disc, or a segment of a ring, by the `KeyOutline` its view is marked with), which is what a finger is read against, and on a segment of the circle layout's ring up is outwards. `PerformanceState` keeps one per held key and hands the active key's to `EffectsState.slide`, by the same rule as the chord (the most recent press). The arpeggiator's and the vocoder's settings are `SlidePlayed`: each has a `followsSlide` switch and names the one control the slide stands in for (the arpeggiator's cycle, the vocoder's amount), and lifting returns to the set value. The chorus, the reverb and the delay have nothing to play. The slide can also play how bright the chord is, dark at the bottom of a key and the whole sound at its top, by a switch in Setup (`EffectsState.slidePlaysBrightness`, off to start with): it is a value beside the effects (`NoteEffects.brightness`, `EffectsControl.setBrightness`) with no settings, field or zone, and a loop records it as it does a played effect.
By another switch there it plays the chord's inversion (`EffectsState.slidePlaysInversion`): the middle of a key is the inversion as set, and each of the four bands above it rolls the chord a step further up and each of the four below a step further down (`InversionSlide`, `EffectsState.slideRoll`), so where a key is struck is how its chord is voiced and a finger sliding on a held key rolls it.
The bands hold on to a finger at their edges as the key zones do (`SlideBands`). `EffectsState` keeps the set values and passes every effect on as played, so nothing downstream knows about the slide: the `Arpeggiator` gets its settings, and each `EffectsControl` gets the sound effects (the keys' `NotePlayer` makes them its notes' sound, `MidiSink` sends CC 93 and 91). A loop being recorded keeps the effects as played when each chord started, and a slide inside a held chord as changes on the note (`SoundChange`). Because a played value jumps back on lifting, a played control must not cut what is already sounding: the reverb is a send into the room, so a zone that switches it off leaves its tail, and a new arpeggiator cycle takes effect from the next note. Adding a gesture = a reading in `ChordKeyTouches` and a value on `EffectsState`; making a setting playable = conforming it to `SlidePlayed` and a switch on its card.

**Key zones play effects by where a key is struck.**
They are a second use of the slide, not a second gesture: `KeyZoneSettings` divides the slide into 1 to 4 equal zones, and each `KeyZone` names one effect (or none; an `EffectChoice`, so Arpeggio 1 and Arpeggio 2 are two) and the place on the slide its played control, if it has one, is held at.
A finger in a zone switches that effect on at that value, whatever it is set to (`EffectSettings.held(at:)`); out of the zone, or lifted, the effect is as set, and still played by the slide if it follows it.
Zones are independent, so a key can mix effects or play one effect at several values (an arpeggio at three speeds).
A chord key can have zones of its own in place of every key's (`EffectsState.keyZones`, `zones(of:)`), 1 to 4 of them, and one zone is the whole key: that is how an effect is put on one key, or on one part of one key.
The key zones have one switch (`zones.isOn`), which the keys' own zones go on and off with.
The Key zones card draws the seven keys in small, each divided as it is (`KeyZonesMap`), and a key tapped there is the one whose own zones the card sets.
`PerformanceState` tells `EffectsState` the key that is played with its slide as one step (`hold(_:at:)`), and a key with no place on it (the computer keyboard) is in its whole-key zone.
A zone can also have a key, an octave and an inversion of its own (`KeyZone.key`, `octave`, `inversion`; nil follows the ones chosen), so one chord key plays D# major low down in one zone and C minor in another.
`PerformanceState.homeKey` is the key the keys are in, by the zone under the finger (`EffectsState.heldZone`), and `playedKey`, `playedOctave` and `playedInversion` are the key, octave and inversion as played; every chord the keys start is built from them, so the modes, the sinks and a loop being recorded get the chord's own key in its `ChordContext` and know nothing of zones.
A finger that slides into a zone with another key, octave or inversion changes the chord it holds, which reaches the mode as a change of color does (`onColorChange`); a finger lifting changes nothing, so a drone stays in the key it was struck in.
`EffectsState` works out the zone the finger is in (`zone`, which sticks a little at its edges so a resting finger cannot flicker between two) and passes the effects on as played, so nothing downstream knows about zones either.
Because a zone switches an effect on and off, the last key up ends its chord before its slide ends (`PerformanceState.release`), or the arpeggiator switching off would sound the chord once more.
`ChordKeySurface` marks the zone edges on every key, at the places `ChordKeySlide.share(at:)` gives, so the marks and the reading cannot disagree.
A zone's value is a place on the slide for every effect that has a played control, so a new effect can be zoned with no more than an `EffectChoice` and a row in the Key zones card.

**The octave plays a chord from its root.**
It is one more chord layout (`ChordGridLayout.octave`): a piano's twelve keys from C to B, each the root of a chord, where the other layouts have a key for each of the seven degrees.
The key still says what each chord is (`KeyDegree.init(root:in:)`, in the music theory core).
A note of the key plays its degree's chord there, so it is the chord that degree's key plays.
A note outside the key plays a chord borrowed from a parallel mode: of the modes of the major scale on the key's tonic that have the note, the one that changes the fewest of the key's notes (the brighter of two as near).
So C major has B♭, E♭, A♭ and D♭ major, and F♯ diminished.
The borrowed chord is a degree of another key, on the same tonic where a scale has the mode (C Mixolydian) and the relative major where none has (C Phrygian is A♭ major), so it is colored, named, recorded and announced as any chord is.
A chord key is a `ChordKey`, a degree's or a root's, and that is what `ChordKeySurface`, `PerformanceState` (`heldKeys`) and the modes hear of.
A mode gives the key back to be played (`startChord`), and `PerformanceState` works out its chord in the key the keys are in then (`ChordKey.chord(in:)`, `homeKey`), so nothing past it knows which layout was played, and a root is read in its zone's key if the zone has one.
`playedKey` is the borrowed key while such a root is the active press.
The octave's chords go up from C to B as its keys do (`ChordKey.octaveShift`), so the tonic's chord is where its degree's key has it, and a root the key would build past B is an octave down.
A root of the key is divided by its degree's own zones, and a root outside it by every key's (`PerformanceState.zonedDegree`).
The black keys lie over the white ones, so of keys that overlap a finger plays the smaller (`KeyTouches`), and a zone's edge is marked on what shows of a key.
Where a degree is chosen (the sequencer's step editor, the pad editor), only the octave's notes of the key are keys (`ChordKeysView.degreesOnly`).
The computer keyboard and a game controller play the degrees' keys whatever the layout, and a key lights with any that plays its chord.

**The key strip changes the key and the voicing while playing.**
It is a row on the play screen, under the loop bar (`KeyStrip`): the key, changed by a swipe along it, and the voicing, which is the octave and the inversion as one field.
The key is one field that shows the key the keys are in (`KeyField`), and a swipe changes its root, the Key page's root, within reach: every step of travel to the right is a semitone up and to the left a semitone down (`SwipeSteps`), so one long swipe crosses several, and the twelve notes go round, so B is followed by C.
So is the sound, from a field beside the note display (`SoundField`), through the sounds in the Sound page's order.
Both are a `SwipeField`, which is what a setting changed by a swipe is drawn and read by.
A tap on a swipe field, or a finger that rests on it, opens every value it has as a list, to choose one by a tap (`SwipeList`); the sound field's is under the Sound page's categories (`SwipeSection`).
The voicing is a `VoicingField`: a chit that shows the octave and the inversion (`KeyVoicing`) and is changed by pressing it.
While a finger is on it, every voicing there is is laid out around it (`VoicingPad`, a column to each inversion and a row to each octave, where `VoicingSpan` puts them), with the voicing it has now under the finger as nearly as the screen's edges allow.
The finger moves the place lit there, a cell of the pad to a step (`VoicingSwipe`): along is the inversion, where a step to the right takes a chord's lowest note up an octave and a step to the left its highest note down one (`Inversion`; the notes a ninth or more above the root are not inverted and stay on top, so a turn of the notes under them is an octave for every chord), and across is the octave, up being higher, so a finger that only goes up or down changes only the octave.
The pad is drawn by the screen, over everything (`showingFieldPad`, as the hotkey tips are), and takes no touches.
The field, the pad's place and the finger's reading are a `PadField` over a `PadMap` (`PadSpan`, `PadSwipe`), so another setting of two parts is a map and a drawing of its pad.
Beside the field is the switch that says whether it keeps what it is set to (`PerformanceState.keepsVoicing`, on to start with).
While it does, the finger sets the voicing (`PerformanceState.voicing`: the Key page's octave, and the inversion).
While it does not, the field is played like a whammy bar: the finger holds the chords a `VoicingBend` from the voicing as set (`holdVoicing(at:)`, `heldVoicing`), and they go back when it lifts (`releaseVoicing`).
A bend is on top of whatever octave and inversion a chord would have, a key zone's own among them, and reaches only the keys: the timeline's notes follow the voicing as set.
With the effect strip these are the only settings with a place outside the menu, because a change of key, octave, inversion or sound is played; Setup can take the strip off the screen (`PerformanceState.showsKeyStrip`).
On a phone on its side the circle layout has an arrangement of its own (`PerformanceView.ringLandscapeLayout`): the compass has the leading half to itself, and the note display, the sound and the key strip are over the ring of chord keys in the trailing half.
A chord being held stays in the key and sound it was struck in, and the next one is in the new ones.
A change of voicing is the exception: it reaches the chord being held at once (it reaches the mode as a change of color does), tied to the chord sounding (`Articulation.tied`, `ChordContext.isRevoiced`), so only the notes that move are struck; a chord taken up an octave has none in common with itself, and is struck whole.
A timeline's note follows the inversion chosen unless it has its own (`NotePlaying.inversion`), and a loop keeps the one each chord was played in.
ChordLink v1 has root position and two inversions, so a chord rolled further is announced as the one of them with the same notes, or released if there is none (`ChordWire.stated`).

**The step compass colors the chord held by one step at a time.**
It is the play screen's one color surface (`StepCompassSurface`), and `docs/chord-dependent-coloration.md` has the design.
The joystick bar, the chord grid and the color ring with its tone marks were surfaces beside it, and the key strip had a color field; they are parked on the `color-ring` branch for v0.1.0 (`docs/color-ring.md` has the ring's design), and their colors stay in the music theory core, since saved loops and pads hold them.
Its places are kinds of step, not chords (`CompassPlace`): up adds a tone, right raises one a semitone, left lowers one, down takes one away, each kind's first choice beside the middle and its second beyond it (`StepCompassGrid`).
What a place plays is worked out from the chord, in the music theory core (`StepCompass`): every chord one step from it (`colorSteps`), fitted to the key (`ColorFit`: in key, an avoid note, borrowed) and put in order (`ColorStepRanking`, chosen in Setup: theory, the degree's own next tone first; or common, the chords played most first).
So a place means the same before a chord is struck as after, and can come down with the chord: with none held the places are named by what they do, with one held by the chord each plays.
A finger slides from place to place: the compass is read as one surface against the frames it is drawn in (`StepCompassGrid.target`), a place moved onto is pressed as a tap there would be, and a gap, a corner or a place with no chord leaves the finger on what it was on.
A step's chord is its tones above the root (`ChordTones`, `ChordColor.tones`), named as the app names chords and voiced with its tensions on top; a chord that is another over its bass is named so ("C/E").
`PerformanceState` works the color out when a chord starts (`color(for:)`), so the modes, loops and sinks get the chord as played and know nothing of the compass; ChordLink v1 has no field for it and announces a release.
Its pin (`keepsCompassColor`, off to start with) says whether a place is played, a step from the plain chord while a finger is on it, or kept: then each tap is a step from the last (`compassWalk`, `StepCompass.walk`), which every degree takes as its own (two adds are G9 on V and Dm9 on ii), until the middle clears it.
The sequencer's step editor and the pad editor color a chord from the chord grid (`ChordGridPad`), since the compass is for playing.

**The effect strip switches the effects while playing.**
It is a row on the play screen, under the key strip, and on the Tonnetz's screen on a phone (`EffectStrip`): a field for each effect that is on, changed by a swipe (`SwipeField`) through the effects no other field has, from off: Arpeggio 1, Arpeggio 2, the chorus, the reverb, the delay and the vocoder (`EffectChoice`).
There is one field to start with, and the + at the end of the row adds another, so the row is as short as what is on and several effects can still be on together.
An arpeggio's field has its cycle beside it, a swipe field through ½, 1, 2 and Bar.
`EffectSlots` is the row: each effect that is on in its place, or an empty field, and never two fields with one effect.
`EffectsState` keeps it (`slots`), and a field is changed through it (`setSlot`), which switches the effect the field had off and the chosen one on in the settings as set.
So the fields and the Effects page are the same switches: an effect switched on the page gets a field (`EffectSlots.follow`), and nothing downstream knows of either.
A field keeps its place while it is being swiped, also through off, so it stays under the finger; the row closes up over empty fields when the finger lifts, or the field's list closes (`SwipeField.onEnd`, `settleSlots`).
An effect a key zone holds on is played, not set, so it has no field.

**The solo strip plays runs over the chord, with no wrong notes.**
It is a line of cells beside the chord keys, each a note that fits the chord being played, switched on by the SOLO button and placed by Setup (`SoloPlacement`): under the keys, which give up some of their height across a handle, upright beside them, or in the chord colors' place.
The notes are worked out, not looked up (`soloIntervals`, in the music theory core): the triad the chord is built on, and each note of the chord's scale that is not a semitone from it, so a major chord gets the major pentatonic, a minor chord the minor one, and no two notes are a semitone apart.
The cells ascend from the key's tonic whatever the chord (`soloNotes`), so a cell stays about where it was when the chord changes.
`SoloState` is the strip: one voice, sounded through a `NotePlayer` of its own beside the keys' chord, by the keys' own contract (the most recent press sounds; lifting it hands the note back to the cell beneath), in the keys' preset with the effects as set.
The chord it plays over is the one sounding, or the last one played once the keys are let go (`PerformanceState.soloChord`); a note being held rings on when the chord changes.
`SoloStripView` draws the cells where `SoloStripCells` puts them and reads its fingers against the same frames, with the chord keys' own tracking (`KeyTouches`), so it is played with several fingers and by sliding.
A loop does not record what the strip plays yet, and `docs/solo-strip.md` has what else is undecided.

**The Tonnetz plays triads in no key, from the net of notes.**
It is a net where a step along one line is a fifth, along the next a major third and along the third a minor third, so every triangle is a major or a minor triad (`TonnetzCell`, in the music theory core), and two triangles that share a side share two notes.
A move (`TonnetzMove`: P, L, R) is a flip of the triangle over one side, worked out from where the triangle is; the tests hold it to the same move on the triad (`Triad.applying`).
`TonnetzState` is the Tonnetz: it is at one triangle at a time, a triangle pressed sounds while it is held, and a move is a press of the triangle across a side.
It is a line of its own, like the solo strip: a `NotePlayer` beside the keys', in the keys' preset, and no mode knows of it.
It is played with the keys' effects as set (`TonnetzHost.tonnetzEffects`), the arpeggiator among them: each of its lines is a `LayerVoice`, as a pad's is, so it has an arpeggiator of its own and the keys' is not touched.
An effect set while a triad or a note sounds reaches it at once without striking it again (`TonnetzState.effectsChanged`), which matters most while it holds.
The effect strip is on its screen, so the effects are switched from there; a slide or a zone of a chord key plays the keys' chord and not the Tonnetz.
A triad is sent as the tonic of its own key (C major, A minor), which is how the sinks read a chord, and is voiced as near the last as it can be, so a move is heard as the one note that changes.
A note of the net is played by itself by pressing its disc (`TonnetzTarget`, read by `TonnetzNet.target`), whatever triangle the Tonnetz is at: a triad taken apart, or a note outside it.
The notes are a second line (`TonnetzLine`) through a `NotePlayer` of their own, so they sound over the triad and neither ends the other.
What that line sounds is sent as one chord tied to the last (`Articulation.tied`), which `NotePlayer` plays by holding over the notes already sounding, so a note that comes or goes is the only one heard to.
A pointer plays what it came down on: one on a triangle slides from triad to triad, and one on a note plays a run of notes.
HOLD (`TonnetzState.holds`) keeps what is pressed sounding after the pointer lifts, until it is pressed again, so one pointer can leave a triad on and add notes to it, or set several notes sounding that make no triangle.
A loop records both lines (`LoopLine`), each as a layer of its own with the effects it was played with, as the notes that were heard (`NotePitch.notes`) since no key says them and a triad is voice-led; the sequencer names such a note by its triad or its notes (`netLabel`), and a chord chosen for it there takes the notes' place.
It has two views, drawn from one geometry and read against it (`TonnetzNet`): the net from above (`TonnetzNetView`, zoomed by `netEdge`), where sliding across a side is a move, and one triad at a time (`TonnetzTriadView`), the same net seen close, with the three triangles it can be flipped into named by their moves.
On the phone it has the whole screen, upright or on its side, chosen by the toggle that also chooses the keys and the sequencer (`PhoneScreen`, `PhoneScreenToggle`); it is not a mode, so it lies over whichever is on and nothing playing under it is stopped.
At the desk it is in the sequencer's place (`DeskPane`, chosen where the phone has that toggle).
`PerformanceState.deskPane` is the one fact of whether it is on screen, in either place, and sets `TonnetzState.isShown`.
Its controls and its board are views of their own (`TonnetzControls`, `TonnetzBoard`), so a phone on its side puts the controls in the row of the screen's own.
It is played by one finger or pointer, or the computer keyboard.

**The Trautonium is two bars whose pitch is anywhere.**
It is the instrument of that name, as the app can have it: two bars (`TrautoniumBar`), each one voice, played by where a finger is on them.
Along a bar is pitch, two octaves from the key's tonic (`BarRange`), the low bar's in the octave the chords are built in and the high bar's an octave up.
Across a bar is how loud (`TrautoniumState.level(across:)`), in place of the pressure a real one is played by, which a phone cannot sense.
A finger that comes down sounds the note of the key nearest it, exactly (`Key.note(nearest:)`, in the music theory core), so a bar is in tune however roughly it is struck.
From there the pitch follows the finger as far as it moves, so a slide is a slide and a finger that rocks is a vibrato around the note.
A finger that has been still for a moment (`TrautoniumState.rest`, a call of the clock's) is brought onto the note of the key nearest it again.
`TrautoniumState` is the bars: each is a line of its own, like the solo strip, a `NotePlayer` beside the keys' in the keys' preset with the effects as set, and no mode knows of it.
A bar's note is started once and then bent and made louder or softer where it sounds (`NoteSound.bend`, `level`), so nothing between the bar and the kernel knows of slides: the player passes the change of sound on as it does a played effect's.
A second finger on a bar takes its note to where it is without striking it again, and lifting it hands the bar back to the finger beneath (`BarTouches`).
The bars are heard and not sent: MIDI as the app sends it has one channel and no pitch bend, so their players have no `MidiSink`, and with the MIDI button on they are silent.
`TrautoniumView` draws the bars where `TrautoniumBars` puts them and reads its fingers against the same frames; they lie along the longer side of what they are given, so they are upright on a phone held upright.
The notes of the key are marked across each bar and named at its quiet edge.
Like the Tonnetz and the pads they are not a mode: they take the phone's screen from the toggle (`PhoneScreen`, where they are BARS) or the sequencer's place at the desk (`DeskPane`), under the key strip and the effect strip, and `PerformanceState.deskPane` sets `TrautoniumState.isShown`.
A loop does not record the bars yet, and the Mixtur-Trautonium's subharmonic sound is still to build.

**The chord–scale tree is played from chord to chord, through the scales each is at home in.**
It is at one chord (`ChordScaleTreeState.position`), and can go at once to any chord of any scale that chord is the home chord of (the chord stacked in thirds on a scale's first note), with no scale to choose: those are `TreeChord.next`, each a `TreeStep` with its Roman numeral and the scales that have it.
The scales are the 21 modes of the major, harmonic minor and melodic minor scales (`HeptatonicMode`, by `ScaleFamily`), and the chords triads or seventh chords (`ChordSize`, `ChordQuality`); the theory is in the music theory core (`ChordScaleTree.swift`).
Its notes are written, not only pitch classes (`NoteName`, a letter and an accidental), so a scale has each letter once and a chord every other one.
A chord pressed sounds while it is held and is where the tree is from then on, so a way through it is played as it is found; of the chords held the last pressed sounds, as on the chord keys.
The way is kept as tiers (`ChordScaleTreeState.tiers`), each a chord and every chord on from it, the next growing from the chord pressed on the one before, side by side and scrolled between (`TreeTiers`): a phone shows one at a time and a desk more.
The tree can be at any tier (`tier`), and going to one changes nothing of the way; only pressing another chord than the one the next tier grows from takes a new way on from there.
A chord on the board is a `TreeSpot`, its tier and the step it is from the chord that tier grows from, so the same chord on two tiers is two places.
`TreeBranches` is a tier: the chord it grows from on top, and under it a branch for each letter a next chord's root can be above its own, its chords side by side from the lowest root; the board draws them there and reads its fingers against the same frames, and a finger plays the chord it came down on however the board moves under it.
A finger that comes down off the chords scrolls the board, as do a trackpad and a wheel, and the trail of tiers above it goes to one by a tap.
A chord sounds in root position from C3 through a line of its own like the solo strip: a `NotePlayer` beside the keys', in the keys' preset with the effects as set, on the audio, MIDI and the piano.
It starts on the tonic chord of the keys' key, which HOME goes back to.
`docs/chord-scale-tree.md` was its first design, a tree of notes, chords and scales chosen in turn, with its prototype in `docs/prototypes`.
Like the Tonnetz and the pads it is not a mode: it takes the phone's screen from the toggle (`PhoneScreen`, where it is TREE) or the sequencer's place at the desk (`DeskPane`), and `PerformanceState.deskPane` sets `ChordScaleTreeState.isShown`.

**The Dissonance Lab makes plain why two notes sound smooth or rough.**
It is two notes played together through a sound made of partials, with the two cues to consonance exaggerated, picked out and faded back by stages: partials that beat or grate, and partials that fit one harmonic series (`dissonance-lab-spec.md` was its design).
The analysis is in a target of its own, plain Swift on numbers with nothing of the app's audio or UI (`Perfecto/Sources/Acoustics`, `IntervalAnalyzer`, tested by `swift test`): every pair of the two notes' partials closer than a critical band (`CollidingPair`), how rough each is by Plomp and Levelt's curve, how fast it beats, and the root the two imply (`ImpliedRoot`, the simplest ratio within 20 cents with a denominator up to 16).
It is not in the music theory core because it needs `exp` and `log`; the intervals, their names and their just ratios are (`Interval`, `Ratio`).
The meter is the roughness summed, beside a minor second's over the same note.
The spotlight is not the roughest pair but the one most heard as two partials meeting (`CollidingPair.prominence`: the weaker strength, the more the nearer within the band), since Plomp and Levelt count a slow beat as hardly rough, and that slow beat is the very one a fifth settles by in just intonation.
`LabSounding` is what two keyed notes become under the settings (`LabSettings`), worked out from them alone: the voicing (close, the lower note between 200 and 400 Hz, or as keyed), the tuning, each partial's strength with the spotlight's boost and cut, the spotlighted upper partial moved alone so its pair beats at a wobble or a grit (`BeatShaping`), the crutches (the pair swung at its beat, or a difference tone), the root tone and dichotic panning.
A pair already in tune is not made to beat.
A level sets them all at once (`LabLevel`, five of them, from every crutch on to the piano's sound with none), and any one can be changed after (`isAdjusted`); the A/B button plays the notes in equal temperament with no enhancement, the partials and the voicing as set.
`DissonanceLabState` holds the two most recent notes (a third takes the oldest's place), from a MIDI keyboard or its pads, and one note alone is played plainly.
`DissonanceSynth` makes what is worked out heard through a `PartialSink` (`KernelSink`), changing only what differs, so a change of a setting is glided to and never struck again, and a note that moves more than a semitone is struck afresh; its keyed notes are shown on the piano.
Like the Trautonium it is heard and not sent, since MIDI has no way to say a partial or a tuning.
While it is on screen it is what a MIDI keyboard plays: `PerformanceState` is the controller's player, and hands the keys to the lab or the Orchid (`ControllerPlayer`), letting go of the Orchid's notes as the lab takes over.
`play(_:above:level:)` is the way in for whatever drives it later, such as a quiz.
Like the Tonnetz and the pads it is not a mode: it takes the phone's screen from the toggle (`PhoneScreen`, where it is LAB) or the sequencer's place at the desk (`DeskPane`), and `PerformanceState.deskPane` sets `DissonanceLabState.isShown`.
`DissonanceLabView` draws the readout, the meter, the partials as two ladders on one axis of pitch (`PartialLadderView`) and the spotlighted pair's beat as it goes by (`BeatEnvelopeStrip`), with the levels, the A/B button, the interval pads and every control under them, or beside them where there is room.

**The pads are a grid of sounds, played by themselves or in sequence.**
The grid has 4 to 8 rows and 4 to 8 columns, set apart from one another in Setup (`PadGrid`).
A pad's sound is a chord as the keys would play it, with a key, octave, sound and effects that are all its own (`PadSound`), so nothing chosen for the keys afterwards reaches it.
It stands in for any sound the app can make; a pad that holds something other than a chord is still to be designed.
`PadsState` is the pads.
A pad pressed sounds while it is held, and every pad has a voice of its own (a `LayerVoice`: an arpeggiator and a `NotePlayer`, as a layer has), so any number sound together.
The sequence (`isRunning`) plays the grid one pad to a step, along each row from the top and round again, on the clock (`every(beats:)`, at `PadGrid.rate`), through one more voice whose `NotePlayer` has the layers' lead; a pad with no sound is a rest, and the pads are played over it.
The sequence goes on under the other screens, and is not part of the timeline: it is not exported, and a loop does not record the pads yet.
While the pads are edited (`isEditing`), a press also chooses the pad that `PadEditor` changes: the chord keys and the chord colors set its chord, as in the sequencer's step editor, and it is given the key, octave or effects chosen for the keys now, or all of them with the chord the keys played last (`PadsHost.padSound`), or any sound, from a list of them all.
The Effects page sets the edited pad's effects by themselves, and the editor's FX button opens it at them (`SidePanelState.showEffects(of:)`, `EffectsTarget`); the button is lit while the pad has an effect on.
A change is heard at once in a pad that is held.
The mic is open to the vocoder while a pad that has it on can sound (`PadsState.hearsTheMic`).
`PadsBoard` draws the pads where `PadCells` puts them and reads its fingers against the same frames, with the chord keys' own tracking (`KeyTouches`).
The pads are not a mode: like the Tonnetz they take the phone's screen from the toggle (`PhoneScreen`) or the sequencer's place at the desk (`DeskPane`), and `PerformanceState.deskPane` sets `PadsState.isShown`.
The grid is saved.

**The computer keyboard is one more finger.**
Its keys are chord keys, the compass's places and the solo strip's cells, by a map that is changed key by key in Setup and remembered (`KeyboardMap`: the home row, the arrows for the compass's first choices and the number row to start with).
A key can also tap one of the screen's buttons (`KeyboardButton`: loop on Return, play and stop on Space, solo on O, MIDI on M, the sequencer on Q, the Tonnetz on Z, and the Tonnetz's net, triad and hold on N, T and K while it is on screen), through `KeyboardHost.tap`, which does what the button does.
Each of those buttons shows the key that taps it in a small chit while a pointer is over it (`hotkeyTip`, drawn over the whole screen by `showingHotkeyTips`).
A map saved before an action existed is given that action's standard key when it is read, unless the key is taken or the action was left with no key on purpose (`KeyboardMap.cleared`).
The Tonnetz's moves are on their own letters (P, L, R) while it is on screen (`TonnetzState.isShown`): a move's triad sounds until the last move's key is up, and the net is drawn again around a move that leads off its edge.
`KeyboardInput` is the window's first responder and hands each key to `KeyboardState`, which presses and releases through `PerformanceState`'s and `SoloState`'s own calls (`KeyboardHost`), so modes, loops and effects know nothing of it.
A compass key plays its place while it is held, as a finger on it does (`KeyboardAction.compass`), a key has no place on its chord key and so plays no slide, and every key is let go when the app stops being in front.
A key that plays nothing is passed on to the system, as is any key pressed with Command, Control or Option.

**A game controller is one more finger, too.**
Its buttons are keys: `GamepadState` has a `KeyboardState` of its own for them (`buttons`), so they play, tap and are held by the keyboard's rules, by a map of their own that is saved apart from the keyboard's (`KeyboardMap.gamepad`: the chords on A, B, X and Y and the d-pad's up, right and down, loop on R1, solo on L1, play and stop on Menu).
A button is named by where it is (`GamepadButton`), so a controller of another make plays the same way under other names.
The left stick plays the compass's first choices, the kind of step it is nearest (`GamepadStick`: up adds, right raises, left lowers, down takes away), which sticks a little at its middle and between two kinds; it plays the compass only as it changes place, pressing the new place before it lifts the old, so a stick at rest leaves it to the keyboard or a finger and a stick turned never passes through the plain chord.
`GamepadInput` hears the controllers (Apple's `GameController`, on the phone and the Mac alike) and tells `GamepadState`, which lets everything go when the controller goes or the app stops being in front.
Setup shows the buttons' map while a controller is connected (`KeyboardMapEditor`, the keyboard's own editor).
The triggers and the right stick are read only as buttons, or not at all, for now.

**A MIDI controller is drawn at the desk with what it is doing.**
It is one more pane in the sequencer's place (`DeskPane.controller`, CTRL), and only there, since a controller is played at a desk.
MIDI says nothing of what a device looks like: CoreMIDI gives its name and ports, and a controller of MIDI 1.0 has no way to say what controls it has, so each device is a `ControllerLayout` written for it and recognized by its name (`ControllerLayout.alesisV61`, the first V61, measured in centimetres on its panel).
A control has a kind, a frame and the message it sends from the factory (`MidiAddress`), or none (the V61's octave buttons send nothing).
`MidiInput` hears every MIDI source but the app's own and hands `ControllerState` what they send (`MidiMessage`, parsed on CoreMIDI's thread and passed to the main thread in order).
`ControllerState` reads a message against each control's binding, and a note no control has is a key; the keys' octave shift is worked out from the notes (`ControllerKeys`).
While learning, a control chosen on the drawing takes the next message heard as its own, and no other control keeps it; the learned bindings are saved by layout.
At the desk it is played as an Orchid is, without its sounds (`OrchidState`, by `OrchidMap`, which names each control's part by its id): every one of its keys is a root, its chord's root on that key (`PerformanceState.press(_:inOctave:)`), so the keyboard's width is the octave as the voicing knob is the inversion, the V61's top row of pads the chord types (Dim, Min, Maj, Sus) and its bottom row the extensions (6, m7, M7, 9), its first button the key button, its second a key change button (`OrchidMap.keyChange`: pressed, the next key struck is the key), and any of its knobs or wheels plays the voicing (the first knob to start with) or the arpeggio (`OrchidPart`).
What the buttons build is a chord color of its own (`ChordColor.built`, a `ChordBuild` in the music theory core: a type, or the degree's own triad, and extensions), and `PerformanceState.chordButtons` makes it the color of every chord the keys play while it builds one.
In key mode a root with no type plays its chord in the key, as the octave layout's key does; out of it the root alone.
The arpeggio, which the Orchid has not, goes up from its control's middle from the lowest note up, down from it from the highest down, and the further from the middle the faster, stepped through the arpeggiator's cycles; it is held on as a zone holds an effect (`EffectsState.holdArpeggio`), so nothing set is changed.
The velocity a key is struck with can play the arpeggio's order, by a switch on the pane (`OrchidState.velocityPlaysArpeggio`): every chord is arpeggiated, up from a key struck soft and down from one struck hard, held on in the same way.
A root presses through `PerformanceState`'s own calls, as the computer keyboard's keys do, so nothing downstream knows of the controller (`docs/midi-controller.md`).

**The piano shows what is sounding, as a pianist would play it.**
It is a piano's 88 keys along the bottom of the window, under whatever screen is there, switched on in Setup; the screen is laid out in what it leaves (`PerformanceView`).
It is a display, not an instrument: `PianoState` hears notes as the audio and MIDI do, through one more `NoteSink` on each line of notes (`PianoState.line`), so it knows nothing of chords, modes or effects and shows the notes actually sounded (an arpeggio one at a time, a strum as it spreads, a note that slides on the key it has slid to).
Each line is a `PianoSource` with a color of its own (the chord keys, the timeline's layers, the solo strip, the Tonnetz, the pads, the Trautonium, the chord–scale tree, the Dissonance Lab), and Setup says which are lit.
A key several sources are sounding is divided between their colors.
`PianoView` draws the keys where `PianoKeys` puts them.
A pinch brings it closer, to as few as an octave's keys, or farther, to all 88, and a drag moves it along (`PianoSpan`, read by `PianoTouches`); a lit key out of view is marked at the end it lies beyond.
The span is on `PianoState`, so the strip and the whole screen show the same keys.
Its corner button or a double tap gives it the whole screen (`PianoState.isExpanded`), over the screen, which stays laid out as it was under the strip, so nothing there changes size or stops.
There its keys keep a piano's proportions, standing on the bottom of the screen (`PianoKeys.standing`), so they grow longer as they are brought closer and reach past the top when they are longer than the screen is high.
The strip reaches under a phone's notch on its side.
A note is lit when it is sent, so the timeline's are seen their lead before they are heard, and notes outside the 88 are not shown.
A new line of notes is seen on it by a `PianoSource` case and a sink where its `NotePlayer` is made (`PerfectoApp`).

**Sequences and loops are one timeline** (`docs/sequencer-spec.md` has the design and what is still to build). A `Timeline` is notes in layers, in ticks (480 to a quarter note), so anything played loosely is kept as played; a note is a chord at a time, with its own key, octave, sound and effects or the live ones, setting by setting. Edits are changes to that value (`TimelineEdits`), and `compile` turns a layer into the chords to play, for playback and the MIDI export alike. `TimelinePlayer` runs the timeline against the clock under whatever mode is on (it is not a mode), each layer through a `LayerVoice` of its own: an arpeggiator and a `NotePlayer`, so layers overlap one another and the keys. `SequencerState` owns the timeline (undo, saving) and says which layer is on screen; its edits apply to the notes on the selected steps. A note belongs to the step whose line its start is nearest and is on every step it is drawn across (`TimelineNote.step`, `steps`), so a chord played a little early is on its beat and what an edit changes is what the grid shows selected. `StepGridShape` arranges the steps in rows of a beat by the time signature, and `Layer.chits` cuts the notes into the pieces drawn, so the grid, its touches and the edits cannot disagree. Join and Split are one button, named for what it would do (`SequencerState.joinEdit`: Join while anything selected could be joined, Split only where each run of selected steps is one held note already), and it is also offered in a tip by the selection (`StepSelectionTip`), placed by `StepGridGeometry.frame(ofTip:by:)`. The step editor has a key strip of its own (`StepPlayingFields`): the selected notes' key, set by a swipe, and their voicing, set by the same field as the keys' (`VoicingField`, with no switch: an edit is kept), each as the note's own (`NotePlaying`, marked ◆), whatever is chosen for the keys. The step editor's coloration is lit at the selected step's own (`ChordColor.direction(in:)`, `ChordGrid.position(of:)`), and a press on what is lit takes it off, back to the plain chord. `SequencerStep` is only the old saved format now. Play mode's LOOP button (`QuickLoopState`) records what the keys play as a `LoopTake` and adds it as a layer, and what each line of the Tonnetz plays as another (`LoopLine`): the first loop sets the length and the tempo (`Timeline.fit`), later ones fold onto it. A loop is notes played again, not recorded audio, so it can be opened and edited in the sequencer.

**A timeline is exported as it plays.** The sequencer's share button offers it as notes (a MIDI file, `SequencerMidiRenderer`) or as sound: `TimelineAudioRenderer` plays it once through a `TimelinePlayer`, the layers' own voices and a kernel in an engine that renders offline, with a `SteppedClock` in place of the real one, and writes a 24-bit WAV file with the last notes left to ring out. It is the app's own playback with no real time passing, so the file is what was heard, each note on its frame. `SteppedClock` is also what tests know as `ManualClock`.

**Adding a performance mode = one file plus one `ModeKind` case.** Each mode implements `PerformanceMode`; its `ModeKind` gives the display name and the `ModeSurface` (screen) it uses, and `PerformanceState.makeMode` builds it. Views decide by kind or surface, never by display name. `PerformanceState` enforces the button contract documented on `PerformanceMode` (the most recent press is active; lifting it hands the chord back to the press held beneath it), and every chord layout is played through `ChordKeySurface`, which tracks each finger (`ChordKeyTouches`) so all layouts get several fingers and sliding; layouts only draw keys and mark them with `chordKey(_:)`.
A mode hears which key is down (`ChordKey`) and never works out its chord.
`KeyTouches` is generic over what a key is, so the solo strip's cells are tracked by the same rules.
The keys are drawn in one place (`ChordKeysView`), in the arrangement the chord layout chosen in Setup gives the screen (`ChordGridLayout.arrangement`), so the sequencer's step editor chooses a degree from the same keys in the same layout (`DegreeSelector`).

**Every setting lives in the menu, a side panel, not in sheets.** `SidePanel` slides over the leading edge of `PerformanceView`, covers only its own width (`SidePanelLayout`) and takes only the touches that land on it, so the keys still showing beside it play as usual and a setting can be heard while it is changed. `SidePanelButton`, in the top leading corner, is the one way in; `SidePanelState` says which page is open and reopens the menu where it was left. A new setting goes on a page (`KeyPanel`, `SoundPanel`, `EffectsPanel`, `SetupPanel`), not behind its own button or sheet.

**The UI spec is drawn from the app itself.**
`scripts/export-ui-spec.sh` draws every screen as shapes and text (PDF, and SVG for a design tool) from the real views on a simulator: `UISpecExportTests` shows each screen listed in `Tests/UISpec/SpecScreen.swift` in a window and `LayerDrawing` draws the window's layers.
A new screen, layout or state worth showing gets an entry in `SpecScreen`; `Tests/README.md` says what the drawings leave out.

**Musical time is stated once** in `MusicalTime` (steps per beat, beats per bar, tempo range); nothing restates "16" or "4".

## Key data types

```swift
// Music Theory Core
PitchClass, ScaleType (10 scales; the Key panel offers the 7 heptatonic ones), Key, Degree (I–vii°)
ChordSpec { degree, color: ChordColor }   // which chord, independent of key and voicing
KeyDegree { key, degree }                 // a degree of a key; init(root:in:) is the chord on any note, borrowed if outside the key
ChordColor .joystick(JoystickMode, JoystickDirection)  — 3 modes × 9 directions; shapes live in JoystickMap
           .grid(StackHeight, HeptatonicMode?)          — thirds stacked through a mode; nil = the degree's own
           .built(ChordBuild)                           — a type (nil = the degree's own triad) and extensions, by buttons
HeptatonicMode  // the 21 modes of major / melodic minor / harmonic minor; byBrightness orders the grid's rows
ChordGrid, GridPosition  // a finger's cell → ChordColor, resolved against the degree that plays
Voicing { notes: [Int], bassNote: Int? }  // MIDI notes: sorted, unique, always within 0...127
Inversion { steps: Int }                  // steps rolled from root position: up, the lowest note an octave up; below 0, the highest down; the 9th, 11th and 13th stay on top

// The central function
func computeVoicing(key:spec:inversion:octave:voiceLeading:previousVoicing:) -> Voicing

// App layer
ChordContext { key, spec, octave, inversion, voiceLeading }  // built by performanceContext(...)
ChordEvent { voicing, articulation, context }             // what every sink receives
ChordKey .degree(Degree) | .root(PitchClass)              // a key on screen; chord(in:) is the KeyDegree it plays
```

## Build order

Implement in this sequence — each step is independently testable:

1. Music Theory Core + unit tests (foundation; no UI/audio)
2. A sine wave on device
3. A synth voice + audio sink + minimal PerformanceView (press button → hear chord)
4. JoystickView wiring
5. Key sheet + Sound sheet
6. Non-clock modes: Play, Strum, Lead, Drone
7. MasterClock + Repeat mode + the arpeggiator
8. MidiSink (test with GarageBand)
9. Sequencer mode + screen
10. Loops (first built as a sample-accurate audio looper; now layers of the timeline)
11. Mic Sample (first a mode on AudioKit; now a sound, a recording the kernel plays at each note's pitch)
12. Effects chain + controls
13. SamplerVoice + bundled SFZ instruments
14. Haptics, polish, edge cases

## Testing

The `JoystickMap` table, the chord grid (`stackThirds`, `tertianChordName`, `ChordGrid`) and `computeVoicing` are the core testable surfaces. Every entry in the joystick transformation table becomes a test assertion on `Voicing.notes`. Full combinatorial space is ~68K; test structural rules + representative samples, not exhaustive coverage.

Swift Testing (`@Test`, `#expect`) is the default for all new test files.

```swift
#expect(
    computeVoicing(key: Key(root: .C, scale: .major),
                   spec: ChordSpec(degree: .I, color: .joystick(.default, .right)),
                   inversion: .root, octave: 4, voiceLeading: false, previousVoicing: nil).notes
    == [60, 64, 67, 71]  // Cmaj7
)
```

Core tests live in `Perfecto/Tests/MusicTheoryCoreTests/` and the kernel's in `Perfecto/Tests/PerfectoKernelTests/` (both run on the Mac with `swift test` in `Perfecto/`); app tests live in `Tests/` (run with `xcodebuild … test` on a simulator or on the Mac as a Catalyst app; see `Tests/README.md`).

## Audio session

- 48kHz, 256-sample buffer (~5.3ms latency)
- `AVAudioSession` category: `.playback` with `mixWithOthers` — app must coexist with DAWs. While the mic sample is being recorded or the vocoder is on it is `.playAndRecord` (to the speaker, built-in mic), and goes back after
- Loops playing in the background need background audio: `.playback` mode + `UIBackgroundModes` entitlement

## MIDI

App registers as a virtual MIDI source named "Perfecto". Channel 1, velocity 100 fixed in v1. The chorus and the reverb are sent as CC 93 and 91 while each is on; no other CC messages (the delay sends none). No program change or clock sync in v1. MIDI input is heard from every source but the app's own, drawn on the MIDI controller pane and played there as an Orchid.

## V1 scope

- Modes: Play, Strum, Lead, Drone, Repeat, Sequencer; loops (up to 6 layers) are recorded in Play mode and under every mode
- The octave: a chord layout of a piano's twelve keys, each the root of a chord, with the notes outside the key borrowed from its parallel modes
- The key strip: the key on the play screen, changed by a swipe, and the octave and the inversion as one field, set or played by a finger that moves along it and across it
- The sound field: the keys' sound beside the note display, changed by a swipe
- The step compass: the one color surface, the colors one step from the chord held (a tone added, raised, lowered or taken away), its places the same before a chord is struck as after, and a finger sliding between them
- The solo strip: runs over the chord from the notes that fit it
- The Tonnetz: triads from the net of notes and the moves between them, its notes played by themselves, and loops of both
- The pads: a grid of 4 to 8 rows and columns, each pad a chord in a sound of its own, played together or in sequence
- The Trautonium: two bars, each a voice whose pitch follows the finger along it and whose loudness follows it across, landing on the notes of the key
- The chord–scale tree: from a chord, every chord of the scales it is at home in, played by pressing it, and on from there
- The Dissonance Lab: two notes through a sound of partials, with the beating and the harmonic fit that make them smooth or rough measured, drawn, exaggerated and faded back by five levels
- The piano: 88 keys along the bottom of the screen, lit with the notes each part of the app is sounding
- A MIDI controller at the desk: the Alesis V61 drawn and lit with what it sends, its controls taught what they send by learning, and played as an Orchid: every key a root in its own octave, chord type and extension buttons, the voicing and an arpeggio on whichever knobs or wheels are chosen, and key mode
- The computer keyboard and a game controller: each plays the chord keys, the compass and the screen's buttons by a map that Setup changes
- Effects: two arpeggios (up and down), chorus, reverb, delay, vocoder; each is switched from the effect strip on the play screen or from a zone of the chord keys, and the arpeggio's cycle and the vocoder's amount can be played by sliding on a key, as can a chord's inversion
- The effect strip: a field for each effect that is on, on the play screen, each changed by a swipe
- Drum module deferred
- The 7 heptatonic scales (pentatonic and blues hidden for now), all 12 keys, all 3 joystick modes (28 chord types), every inversion, up and down
- Synth engine (29 presets; each a `SynthPatch` in `SynthPreset`) + sample engine (SFZ, ≤250MB bundle)
- MIDI out
- Light + dark mode

## Logging

When adding a feature, identify its load-bearing events and emit `LogEvent` cases for them. Event types live in `Perfecto/Sources/Logging/LogEvent.swift`. Pass `Logger` via constructor injection; production uses `FileLogger`, tests use `RecordingLogger`.

## Known risks (watch for)

- **Virtual joystick zone detection** — 8 zones by thumb-drag is harder than physical; may need visual zone-highlighting or wider deadbands. Prototype early.
- **Loop timing** — the timeline's notes are sent 50 ms ahead and sounded on their exact frames. A main thread held up for longer than that makes a note late (it then sounds at once); `TimelineTimingTests` checks the frames with a clock that is always late. What the keys set going on the clock (a live arpeggio, Repeat) is still only as punctual as the main thread.
- **Inversion + voice leading + chord lock interactions** — subtle; write explicit test cases for combinations before shipping.
