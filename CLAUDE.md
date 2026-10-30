# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

**Perfecto** — an iOS chord performance instrument. The full v1 spec is in `spec.md`.

Stack: iOS 17+, iPhone (portrait + landscape), Swift 6, SwiftUI, an audio kernel of our own in C++ (no audio library), MVVM with `@Observable`, CoreMIDI.

**The same app runs on the Mac**, built with Mac Catalyst (the iPad's idiom, so every control looks as it does on the phone).
There its "Perfecto" MIDI source is on the machine the DAW runs on, so no network session is opened (`MidiNetwork`), and the MIDI button silences the app's own sound as on the phone (`AudioOutput.isExternalSynth`).
A mouse is one finger.
A window is laid out as a phone is, upright or on its side by its shape.

**The desk is an app of its own** (`Desk/`, Perfecto Desk), played from a game controller, the Xbox 360 its design reference (`docs/gamepad-desk-ui.md`; `Desk/README.md` says how it is played).
It is not the Catalyst app.
The canonical desk is the Godot app (`Desk/godot/`, whose README says how it is built), for the Mac now and the Steam Deck and consoles after (`docs/desk-engine-and-audio.md`).
Its layouts are a pure core in C++ (`Desk/Sources/PerfectoDeskCore`, on the C++ theory core: controller frames in, effects as data out), which also says what the screen shows (`scene.hpp`, a value the scripts only draw), and a thin shell: a GDExtension in C++ (`Desk/godot/extension`) that reads the controllers, steps the core and plays its effects on the kernel (as a Godot `AudioStream`) and MIDI.
New desk work goes there.
Face Chords has drums, a beat and pads, which are the Godot desk's alone: a core of their own beside the desk (`drums.hpp`, composed with it by `studio.hpp`, so the parity-tested desk is unchanged) and eight kits synthesized in code (`Desk/Sources/PerfectoDrumKit`: Analog, Punch, Glue, Harsh, Lo-fi, FM, Room and Tight), all loaded into the kernel as loaded samples when the desk is set up.
Its left stick colors the chords, by the Orchid's chord buttons or the phone's joystick table (Menu › Face Chords stick), and LB pins the colors to the chords' favorites: a core of its own beside the desk too (`face_colors.hpp`, composed by `studio.hpp`), which hands Face Chords a color for each degree (`setColors`, the one hook the Swift core shares).
The Mac desk it grew from, a SwiftUI app built with SwiftPM on the Swift cores (`DeskCore`, `PerfectoDesk`), is to be retired once the Godot desk has all it had (it still lacks kept settings and the wired 360); with it go the Swift `DeskCore` and `DeskCoreParityTests`, which play the two cores frame for frame, and the C++ core becomes the only one. Until then a change to one core is a change to the other in the same commit.

**v0.1.0 is Play mode alone.**
The app is being stripped to a solid first release: the play screen with the chord keys, the step compass, the key strip, the effect strip, loops and the piano.
Everything else built so far is parked, kept on the `color-ring` branch (and most of it on `main`) to come back after the release: the sequencer's screen and its mode, Strum, Lead, Drone and Repeat, the Tonnetz, the pads, the Trautonium, the chord–scale tree, the Dissonance Lab, the MIDI controller and the Orchid, the desk layout and the screen toggle, the solo strip, and the joystick, the chord grid and the color ring.
Their colors and notes stay in the music theory core and the timeline, since saved loops hold them; the design docs in `docs/` describe them.

## Architecture

The codebase is split into strict layers with no upward dependencies:

```
SwiftUI Views
    ↓
ViewModels (@Observable): PerformanceState, SequencerState (the timeline's owner), QuickLoopState
    ↓
Performance Engine: PerformanceMode protocol + Play mode
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

**The theory core is also in C++** (`Perfecto/Sources/PerfectoTheory`, for the desk on game engines and consoles; its README has the rules it keeps). It is a port of the Swift core, which stays the reference: a change to one is a change to the other in the same commit, and `PerfectoTheoryParityTests` compares the two over whole spaces of inputs.

**Music Theory Core purity is a hard constraint.** It is pure Swift (Int/Array only), testable in isolation as pure functions of its inputs. Never add UIKit, AudioKit, or Foundation imports to anything under `Perfecto/Sources/MusicTheoryCore/`.

**ChordEventSink decouples event generation from consumption.** Every sink receives the same `ChordEvent`s independently — neither knows about the others or reads app state. A `ChordEvent` carries the voicing, its `Articulation` (block or strum), and the `ChordContext` that produced it; the protocol's doc states the contract (`playChord` replaces what is sounding).

**Below the chords are notes.** `NotePlayer` is the one place a chord becomes note-ons and note-offs (and where a strum is spread out), so audio and MIDI are `NoteSink`s that know nothing of chords. Every note has a `NoteID` chosen by its sender, and a sink ends only the note it is told to: one `NotePlayer` is one line of chords, and several can sound at once through the same sinks. Every note also carries its `NoteSound` (preset, chorus, reverb, vocoder, and how far it is bent from its pitch and how loud), which is its player's: the keys' player follows the effects as played, and each layer's is given its chords' own, so a loop keeps the sound it was recorded with while the keys play another over it. The player also spreads a chord's notes a little from left to right (`NotePlayer.spread`). A change to a player's sound reaches the notes it holds (`noteChange`), which is how a slide is heard; a new chord's sound leaves the last chord's notes as they were (`startNotes(in:)`).

**The audio kernel makes every sound** (`docs/audio-engine-spec.md` has the design and what is still to build). It is portable C++ behind a C interface (`Perfecto/Sources/PerfectoKernel`): timed events in, samples out, and nothing in its render call allocates, locks or waits; its tests are built to stop on any allocation made while rendering. An event takes effect on exactly the frame it names, however rendering is divided into calls. A note names its sound, one of the patches the kernel was given (`perfecto_kernel_set_sound`, before playing: it builds the patch's wavetables), and has its own brightness, pan, and chorus and reverb sends, which a note change glides. It also has a bend, in semitones from its pitch, and a level, which a note change glides too (its filter and a capture's speed follow the bend): a note changed little and often is heard to slide, which is how the Trautonium's bars are played. A patch can have an LFO, a slow sine that starts with each note and moves its pitch, the width of its pulse waves and its filter (`PerfectoLfo`, `SynthPatch.LFO`). Its operators can be up to seven copies of themselves a little out of tune (`unison`), and can wander from their pitch differently for every note (`drift`), by a chance that starts from the same place each time the kernel is readied. A patch can be sine partials in place of its operators (`PerfectoPatch.additive`, `SynthPatch.partials`), each of which a note sets apart while it sounds (`PerfectoEventPartialChange`): how strong, how many Hz from its place in the series, and how it swings in strength, all glided over 15 ms; that is the Dissonance Lab's sound. A patch can also have noise beside its operators (swept, a breath; steady, air), a drive after its filter, and a glide: a note that follows another of its sound with no gap starts at that note's pitch (the nearest, of a chord's) and slides to its own. The kernel has the 64 voices and chooses which to give up. The voices are added into one chorus, one delay and one reverb (`MixBus.hpp`) and a look-ahead limiter, whose 1.5 ms is the kernel's latency. `KernelAudioUnit` hosts it as an Audio Unit, and the render block is Objective-C++ (`PerfectoKernelHost`) so the render thread never runs Swift. `KernelSink` is the `NoteSink` in front of it: it loads the presets as kernel sounds (`SynthPatch.kernelPatch`) and turns a `NoteSound` into the kernel's numbers. `AudioGraph` is the engine and what is connected in it: the unit has an input, and an engine in real time renders it only while something is connected there, so a silent source always is (`KernelLiveTests` runs the graph in real time). An engine that has opened the mic cannot start in a session that only plays, so the graph starts a new engine once the mic is let go, with the same unit in it (`AudioOutputLiveTests`, which only a phone makes fail). `AudioOutput` keeps it running across route changes, and `AudioSession` is the one place the session is configured.

**The kernel records, too.** It has four captures (30 seconds each, one channel), and a capture event starts or stops recording its input into one on an exact frame. A recording that ends is made ready to play (cut to its sound, brought to full level), and a patch can name a capture in place of its operators, played faster or slower by pitch: that is the mic sample (`SynthPreset.micSample`), a sound like any other, so it is played, sequenced and looped as notes. `SampleRecorder` asks for the recording, watches the kernel for its end, opens the mic only meanwhile (through `AudioOutput`), and keeps the sample on disk; `MicSampleState` is what the Sound panel shows of it. Recordings made beforehand (the Godot desk's drum kits) are given to the kernel apart from the captures, as loaded samples (128 of them, `perfecto_kernel_sample_load`, only while nothing renders), and a patch with `loaded` plays one as it plays a capture. Whatever needs the mic asks `MicAccess`, which puts the system's question once through `PermissionGate`.

**The vocoder is an effect that hears.** A note's send to it (`VocoderSettings`, on `NoteSound` like the others) is the share of the note that is not heard itself but shaped by the voice at the kernel's input, through a bank of bands (`Vocoder.hpp`). `PerformanceState` opens the mic while the vocoder, or a key zone of it, is on (`EffectsState.hearsTheMic`, `AudioOutput.isVocoding`); on the speaker the device's echo cancelling is switched on with it. With the vocoder off or nothing to hear, notes sent to it are heard whole.

**MasterClock drives everything timed.** The timeline (the loops), the arpeggiator and strums all use it; nothing between a key and its notes sleeps or keeps a timer of its own. It is behind a `ClockTickable` protocol so test doubles can replace it without changing callers. Modes count its ticks (sixteenths); anything finer or off that grid asks it for a call: over and over (`every(beats:)`, as the arpeggiator does), or once (`after(beats:)` for the end of a timeline's note, `after(seconds:)` for a strum's notes). Both clocks keep their calls in a `ClockSchedule`, which makes them in the order they fall due (a tick first) and times a call asked for inside another from that call's due time, so the real clock and `ManualClock` follow the same rules and timing tests never wait on real time.

**Notes carry times.** Every note-on, note-off and change is stamped with the moment it takes effect (`ClockTickable.time`: inside a call of the clock's, the moment that call was due, however late the main thread got to it). `KernelSink` turns the moment into the kernel's frame (each render tells `PerfectoKernelHost` when it is for) and `MidiSink` into a MIDI timestamp. What the clock plays (a layer's `NotePlayer`) adds a short lead (`NotePlayer.sequencedLead`, 50 ms), so its notes are always sent ahead of their moment and sound on exactly their frame: the timeline is heard that much after the clock's position, all of it alike. The keys' player has no lead, since a key sounds at once; what the clock does on its behalf (a strum's later notes, a live arpeggio) is stamped but has usually just passed, so it is as punctual as the main thread. A loop recorded over layers is placed where it was heard, the lead earlier than the clock had it (`QuickLoopState`).

**Effects are layers, not modes**, so they work under every mode. The arpeggiator is a note effect: a `ChordEventSink` in front of the note sinks, so audio and MIDI hear the same notes, while ChordLink still hears the whole chord. One pass over a chord takes one cycle (`ArpeggioCycle`) however many notes it has. The chorus, reverb, delay and vocoder are sound effects, and each note has its own of them (`NoteSound`): the kernel has one chorus, one reverb, one delay and one vocoder that notes send into, and a limiter that keeps layers from clipping. The arpeggiator has two patterns, offered as two effects: Arpeggio 1 goes up and Arpeggio 2 down (`ArpeggioPattern`). The chorus, the reverb and the delay are each one sound, on or off: how much of a note goes to them, the chorus's speed, the reverb's size and the delay's feedback are constants on their settings, and `KernelSink` sets the kernel's mix to them once. The delay's echoes are a dotted eighth note apart (`DelaySettings.beats`), from side to side, so `KernelSink` is told the tempo (`TempoControl`, by `PerformanceState.setBPM`); a change of tempo bends the echoes on their way, as a tape would. The delay is a send like the reverb, so switching it off leaves its echoes, and an export goes on until they have died away (`Timeline.hasEchoes`). There is no filter among the effects. A note has a brightness (`NoteSound.brightness`, the kernel's for each note), which is not an effect but can be played by the slide (see the key gestures). An effect's settings are plain data (`EffectSettings`: `ArpeggiatorSettings`, `ChorusSettings`, `ReverbSettings`, `DelaySettings`, `VocoderSettings`), edited through `EffectsState`, which can be read as set (`asSet`) or as played (`asPlayed`). Adding a sound effect = a settings struct, a field on `NoteSound` and its place in the kernel's mix, an `EffectChoice`, and a card in `EffectsPanel`.

**A loop's effects are its own.**
A recorded note keeps the effects it was played with (`NotePlaying.effects`), so nothing set or played for the keys afterwards reaches it.
They are edited by themselves on the Effects page, which shows the keys' effects or one loop's (`EffectsPanel.control`): an edit changes that setting on every note of the layer and every point of a slide recorded in it (`Layer.editEffects`, `SequencerState.editEffects(ofLayer:)`), and a run of edits is one undo.
The chord a layer is sounding takes an edit up at once without being struck again (`TimelineVoice.change`).
Two things are shared: the mic is open to the vocoder only while the keys' vocoder is on, and over MIDI the effects' controllers are the keys' alone, on the one channel.

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

**The effect strip switches the effects while playing.**
It is a row on the play screen, under the key strip (`EffectStrip`): a field for each effect that is on, changed by a swipe (`SwipeField`) through the effects no other field has, from off: Arpeggio 1, Arpeggio 2, the chorus, the reverb, the delay and the vocoder (`EffectChoice`).
There is one field to start with, and the + at the end of the row adds another, so the row is as short as what is on and several effects can still be on together.
An arpeggio's field has its cycle beside it, a swipe field through ½, 1, 2 and Bar.
`EffectSlots` is the row: each effect that is on in its place, or an empty field, and never two fields with one effect.
`EffectsState` keeps it (`slots`), and a field is changed through it (`setSlot`), which switches the effect the field had off and the chosen one on in the settings as set.
So the fields and the Effects page are the same switches: an effect switched on the page gets a field (`EffectSlots.follow`), and nothing downstream knows of either.
A field keeps its place while it is being swiped, also through off, so it stays under the finger; the row closes up over empty fields when the finger lifts, or the field's list closes (`SwipeField.onEnd`, `settleSlots`).
An effect a key zone holds on is played, not set, so it has no field.

**The computer keyboard is one more finger.**
Its keys are chord keys and the compass's places, by a map that is changed key by key in Setup and remembered (`KeyboardMap`: the home row, and the arrows for the compass's first choices to start with).
A key can also tap one of the screen's buttons (`KeyboardButton`: loop on Return, play and stop on Space, MIDI on M), through `KeyboardHost.tap`, which does what the button does.
Each of those buttons shows the key that taps it in a small chit while a pointer is over it (`hotkeyTip`, drawn over the whole screen by `showingHotkeyTips`).
A map saved before an action existed is given that action's standard key when it is read, unless the key is taken or the action was left with no key on purpose (`KeyboardMap.cleared`).
`KeyboardInput` is the window's first responder and hands each key to `KeyboardState`, which presses and releases through `PerformanceState`'s own calls (`KeyboardHost`), so modes, loops and effects know nothing of it.
A compass key plays its place while it is held, as a finger on it does (`KeyboardAction.compass`), a key has no place on its chord key and so plays no slide, and every key is let go when the app stops being in front.
A key that plays nothing is passed on to the system, as is any key pressed with Command, Control or Option.

**A game controller is one more finger, too.**
Its buttons are keys: `GamepadState` has a `KeyboardState` of its own for them (`buttons`), so they play, tap and are held by the keyboard's rules, by a map of their own that is saved apart from the keyboard's (`KeyboardMap.gamepad`: the chords on A, B, X and Y and the d-pad's up, right and down, loop on R1, play and stop on Menu).
A button is named by where it is (`GamepadButton`), so a controller of another make plays the same way under other names.
The left stick plays the compass's first choices, the kind of step it is nearest (`GamepadStick`: up adds, right raises, left lowers, down takes away), which sticks a little at its middle and between two kinds; it plays the compass only as it changes place, pressing the new place before it lifts the old, so a stick at rest leaves it to the keyboard or a finger and a stick turned never passes through the plain chord.
`GamepadInput` hears the controllers (Apple's `GameController`, on the phone and the Mac alike) and tells `GamepadState`, which lets everything go when the controller goes or the app stops being in front.
Setup shows the buttons' map while a controller is connected (`KeyboardMapEditor`, the keyboard's own editor).
The triggers and the right stick are read only as buttons, or not at all, for now.

**The piano shows what is sounding, as a pianist would play it.**
It is a piano's 88 keys along the bottom of the window, under whatever screen is there, switched on in Setup; the screen is laid out in what it leaves (`PerformanceView`).
It is a display, not an instrument: `PianoState` hears notes as the audio and MIDI do, through one more `NoteSink` on each line of notes (`PianoState.line`), so it knows nothing of chords, modes or effects and shows the notes actually sounded (an arpeggio one at a time, a strum as it spreads, a note that slides on the key it has slid to).
Each line is a `PianoSource` with a color of its own (the chord keys, the timeline's layers), and Setup says which are lit.
A key several sources are sounding is divided between their colors.
`PianoView` draws the keys where `PianoKeys` puts them.
A pinch brings it closer, to as few as an octave's keys, or farther, to all 88, and a drag moves it along (`PianoSpan`, read by `PianoTouches`); a lit key out of view is marked at the end it lies beyond.
The span is on `PianoState`, so the strip and the whole screen show the same keys.
Its corner button or a double tap gives it the whole screen (`PianoState.isExpanded`), over the screen, which stays laid out as it was under the strip, so nothing there changes size or stops.
There its keys keep a piano's proportions, standing on the bottom of the screen (`PianoKeys.standing`), so they grow longer as they are brought closer and reach past the top when they are longer than the screen is high.
The strip reaches under a phone's notch on its side.
A note is lit when it is sent, so the timeline's are seen their lead before they are heard, and notes outside the 88 are not shown.
A new line of notes is seen on it by a `PianoSource` case and a sink where its `NotePlayer` is made (`PerfectoApp`).

**Loops are layers of one timeline** (`docs/sequencer-spec.md` has the design of the sequencer that edited it, which is parked). A `Timeline` is notes in layers, in ticks (480 to a quarter note), so anything played loosely is kept as played; a note is a chord at a time, with its own key, octave, sound and effects or the live ones, setting by setting. Edits are changes to that value (`TimelineEdits`), and `compile` turns a layer into the chords to play, for playback and the MIDI export alike. `TimelinePlayer` runs the timeline against the clock under whatever mode is on (it is not a mode), each layer through a `LayerVoice` of its own: an arpeggiator and a `NotePlayer`, so layers overlap one another and the keys. `SequencerState` owns the timeline (undo, saving, playing); it still has the step editing the sequencer's screen used, which the loop work is to trim. `SequencerStep` is only the old saved format now. A loop is notes played again, not recorded audio, so its effects and its notes can be changed after.
Play mode's LOOP button (`QuickLoopState`, drawn by `LoopBar`) offers the lengths a loop can be, 1, 2, 4 or 8 bars at the tempo set (`QuickLoopState.lengths`).
Choosing one counts in for three seconds and then records what the keys play for that many bars as a `LoopTake`, all of it timed by the clock (`after(seconds:)`, `after(beats:)`); a chord sounding as recording begins is the take's first.
The take ends by itself and plays from that moment, as a layer (`LoopLine`).
The first loop sets the timeline's length; a later one is laid where in the loop it was played, and the timeline and the take are each repeated to the least length that holds both (`Timeline.layering`), so a loop of one bar plays four times over one of four.
The moments of a take are felt (`LoopCue`: each second of the count-in, the start, the end), and the button pulses with them and drains while it records.
A loop's chit pauses it and resumes it in time; the trash switches the chits to deleting, and a touch anywhere else on the screen switches it off (`closingLoopBar`).

**A timeline is exported as it plays.** It can be made into notes (a MIDI file, `SequencerMidiRenderer`) or sound, though nothing on screen offers it since the sequencer's share button was parked: `TimelineAudioRenderer` plays it once through a `TimelinePlayer`, the layers' own voices and a kernel in an engine that renders offline, with a `SteppedClock` in place of the real one, and writes a 24-bit WAV file with the last notes left to ring out. It is the app's own playback with no real time passing, so the file is what was heard, each note on its frame. `SteppedClock` is also what tests know as `ManualClock`.

**Adding a performance mode = one file plus one `ModeKind` case**, and a way to choose it (Play is the only mode now, so there is none). Each mode implements `PerformanceMode`, and `PerformanceState.setMode` makes it the one played. Views decide by kind, never by display name. `PerformanceState` enforces the button contract documented on `PerformanceMode` (the most recent press is active; lifting it hands the chord back to the press held beneath it), and every chord layout is played through `ChordKeySurface`, which tracks each finger (`ChordKeyTouches`) so all layouts get several fingers and sliding; layouts only draw keys and mark them with `chordKey(_:)`.
A mode hears which key is down (`ChordKey`) and never works out its chord.
`KeyTouches` is generic over what a key is.
The keys are drawn in one place (`ChordKeysView`), in the arrangement the chord layout chosen in Setup gives the screen (`ChordGridLayout.arrangement`).

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

The C++ core's tests are ported one for one into `Perfecto/Tests/PerfectoTheoryTests/` (doctest, built by `Perfecto/CMakeLists.txt`), and its parity with the Swift core is `swift test`'s `PerfectoTheoryParityTests` (whole spaces with `-c release`). Core tests live in `Perfecto/Tests/MusicTheoryCoreTests/` and the kernel's in `Perfecto/Tests/PerfectoKernelTests/` (both run on the Mac with `swift test` in `Perfecto/`); app tests live in `Tests/` (run with `xcodebuild … test` on a simulator or on the Mac as a Catalyst app; see `Tests/README.md`).

## Audio session

- 48kHz, 256-sample buffer (~5.3ms latency)
- `AVAudioSession` category: `.playback` with `mixWithOthers` — app must coexist with DAWs. While the mic sample is being recorded or the vocoder is on it is `.playAndRecord` (to the speaker, built-in mic), and goes back after
- Nothing sounds while the app is off the screen (the phone locked, another app in front): `PerformanceState.enterBackground` lets go of every key, place and voicing held, calls off a take, stops the loops and stops the engine (`AudioOutput.isInBackground`), and the app has no background audio mode; coming back starts the engine, and the loops wait to be started

## MIDI

App registers as a virtual MIDI source named "Perfecto". Channel 1, velocity 100 fixed in v1. The chorus and the reverb are sent as CC 93 and 91 while each is on; no other CC messages (the delay sends none). No program change or clock sync in v1. No MIDI input in v0.1.0.

## V1 scope

- Play mode; loops (up to 6 layers) are recorded from it
- The octave: a chord layout of a piano's twelve keys, each the root of a chord, with the notes outside the key borrowed from its parallel modes
- The key strip: the key on the play screen, changed by a swipe, and the octave and the inversion as one field, set or played by a finger that moves along it and across it
- The sound field: the keys' sound beside the note display, changed by a swipe
- The step compass: the one color surface, the colors one step from the chord held (a tone added, raised, lowered or taken away), its places the same before a chord is struck as after, and a finger sliding between them
- The piano: 88 keys along the bottom of the screen, lit with the notes the keys and the loops are sounding
- The computer keyboard and a game controller: each plays the chord keys, the compass and the screen's buttons by a map that Setup changes
- Effects: two arpeggios (up and down), chorus, reverb, delay, vocoder; each is switched from the effect strip on the play screen or from a zone of the chord keys, and the arpeggio's cycle and the vocoder's amount can be played by sliding on a key, as can a chord's inversion
- The effect strip: a field for each effect that is on, on the play screen, each changed by a swipe
- Drum module deferred
- The 7 heptatonic scales (pentatonic and blues hidden for now), all 12 keys, every inversion, up and down
- Synth engine (29 presets; each a `SynthPatch` in `SynthPreset`) + sample engine (SFZ, ≤250MB bundle)
- MIDI out
- Light + dark mode

## Logging

When adding a feature, identify its load-bearing events and emit `LogEvent` cases for them. Event types live in `Perfecto/Sources/Logging/LogEvent.swift`. Pass `Logger` via constructor injection; production uses `FileLogger`, tests use `RecordingLogger`.

## Known risks (watch for)

- **Loop timing** — the timeline's notes are sent 50 ms ahead and sounded on their exact frames. A main thread held up for longer than that makes a note late (it then sounds at once); `TimelineTimingTests` checks the frames with a clock that is always late. What the keys set going on the clock (a live arpeggio) is still only as punctual as the main thread.
- **Inversion + voice leading + chord lock interactions** — subtle; write explicit test cases for combinations before shipping.
