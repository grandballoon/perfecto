# The MIDI controller

A hardware MIDI controller is to be played as an instrument of the app's own: its keys and its other controls made into what the app plays (an Orchid's chord buttons and roots, or another way of playing), and combined at once with what another source does (a phone, the computer keyboard, a game controller).

## What is built

The desk has a pane for the controller (CTRL), which draws it and lights it with what it sends.

- `MidiInput` hears every MIDI source but the app's own.
- `ControllerLayout` is a device's face: each control's kind, frame and factory message. The Alesis V61 (the first, not the MKII) is the only one so far.
- `ControllerState` reads each message against the controls' bindings; a note no control has is a key, and the keys' octave shift is worked out from the notes.
- LEARN teaches a control what it sends: choose it on the drawing, then press or move it on the device. The learned bindings are saved by layout, and RESET forgets them.

## Played as an Orchid

At the desk, and only there, the controller is played as Telepathic Instruments' Orchid is, without its sounds (`OrchidState`).
`OrchidMap` says which control plays which part, by its id on the layout, so a control keeps its part whatever it has been taught to send.
On the V61:

| Orchid | V61 |
| --- | --- |
| The one-octave keyboard: each key the root of a chord | Every key, the root of its chord in the octave it is in (as sent, so the octave buttons move them) |
| Chord type buttons: Dim, Min, Maj, Sus | The top row of pads (5 to 8) |
| Chord modifier buttons: 6, m7, M7, 9 | The bottom row of pads (1 to 4) |
| Voicing dial | Knob 1 to start with; any knob or either wheel, chosen on the pane (VOICE) |
| Key: a press switches key mode, and held, the next key struck is the key | Button 1 |
| (The Orchid has none) Key change: pressed, the next key struck is the key | Button 2 (SET KEY) |
| (The Orchid has none) The arpeggio | None to start with; any knob or either wheel, chosen on the pane (ARP) |
| (The Orchid has none) The arpeggio's order, by how hard a key is struck | The keys' velocity, switched on the pane (VEL ARP) |

- A type held builds the chord on that triad on whatever root is struck; of several held, the last pressed.
- The modifiers add their notes, as many as are held: the sixth (a diminished triad's is its seventh, so a diminished seventh), a seventh, the ninth. A sixth over a seventh is the thirteenth, and the two sevenths together are the major one.
- In key mode a root with no type held plays its chord as the key has it, and the modifiers add to that; out of key mode it plays the root alone, as the Orchid does.
- A root outside the key is played in key mode as the octave layout plays it: a chord borrowed from a parallel mode.
- The keyboard's width is the octave, where the Orchid has one octave of keys and a button to move it: a key's chord has its root on that key (`PerformanceState.press(_:inOctave:)`), whatever octave the Key page has.
The voicing's control rolls it from there, so the key strip's octave plays no part in what the controller plays, and a loop keeps each chord's octave as it was struck.
A chord that rings on after its key lifts (a drone) stays in the octave it was struck in.
- The key button held with a root struck makes that root the key, minor while Min is held; it also switches key mode on. Key mode is also switched from the pane, and remembered.
It is on to start with, so a key alone plays a chord, where the Orchid starts with it off.
- The key change button does what the key button held does without being held: pressed, it is lit and the next root struck makes that root the key (minor while Min is held) and is not played; pressed again before one is, it chooses none.
Any key of the keyboard chooses its note, whatever octave it is in.
- The voicing's control's whole travel is every inversion the keys can be set to (`PerformanceState.inversions`), root position at its middle, and each step rolls the chord one note, as the Orchid's dial does. It sets the inversion, so the key strip's voicing shows it.
- What the buttons build is a chord color (`ChordColor.built`, `ChordBuild` in the music theory core), and the buttons are a color surface of their own: while one is held it also builds the chords the screen's keys play.
- A root presses through `PerformanceState`'s own calls, so the modes, the effects and the loops know nothing of the controller: Strum, Repeat and the arpeggiators are the Orchid's performance modes here, and LOOP records what it plays.
- The voicing and the arpeggio are the parts played by turning (`OrchidPart`), and each can be given any of the knobs or wheels the map offers (`OrchidMap.turned`), or none. A control plays one part, so giving it to one takes it from the other. What each part is given is remembered.
- The arpeggio's control turned up from its middle plays the chord's notes from the lowest to the highest, and turned down from the highest to the lowest: Arpeggio 1 and Arpeggio 2.
- The further from the middle, the faster, through the arpeggiator's cycles: past a rest of a tenth of its travel either way of its middle, the rest is divided evenly among Bar, 2, 1 and ½.
- The pitch wheel springs back to its middle, so letting go of it stops the arpeggio, and given the voicing it is root position at rest; the knobs and the mod wheel stay where they are left.
- The control holds the arpeggio on as a key zone does (`EffectsState.heldArpeggio`), over the slide and the zones: it is played, not set, so the arpeggiator's settings and the effect strip stay as they were, and a loop records the arpeggio as it was played.
- The velocity a key is struck with can play the arpeggio's order (VEL ARP on the pane, off to start with and remembered): every chord is then arpeggiated, a key struck soft (below 64) from the lowest note up and one struck hard from the highest down (`OrchidState.pattern(struckAt:)`).
The order is chosen as the key is struck and kept while it is held, so a chord held beneath another takes its own order back when the one over it lifts.
The arpeggio's control, while it is pushed, still says how fast, and only the velocity says which way; with the control at rest the arpeggio is as fast as the arpeggiator's cycle as set (`HeldArpeggio.cycle`, nil).
A V61 sends no aftertouch, so how hard a key is struck is all it says of how it is pressed, and a held key cannot change its order.
- While LEARN is on the controls play nothing.

The pane marks each control with its part, lights Button 1 while key mode is on, and lights Button 2 while it waits for a key.
ChordLink v1 has no field for a chord built from buttons, so one is announced as a release, as a grid color is.

## Why a layout is written for each device

MIDI says nothing of what a device looks like.
CoreMIDI gives a device's name, its maker and model, and its ports; nothing of its controls.
MIDI 2.0's capability inquiry (Property Exchange) could let a device describe its controls, but few do, and a USB MIDI 1.0 controller like the V61 cannot.
So a device is recognized by its name and drawn from a layout written for it, and what its controls send is learned by hearing them, since an editor (the V Editor) can change it.

The V61's guide gives only the wheels' messages.
The knobs are on CC 20 to 23, as Spectrasonics' setup for the V61 has them.
The pads (notes 36 to 43 on channel 10) and the buttons (CC 48 to 51) are a guess, to be confirmed on a real V61 and corrected in `AlesisV61.swift` if they are wrong.
The panel's measurements are estimates from its dimensions (112 by 24.4 cm) and its guide's drawing.

## What is next

- The rest of the Orchid: its bass (a voice of its own under the chords, following their roots or played alone), the voicing dial's press (a single note's octave or split), its secret chords (two types held together), and its key mode's choice of the scale's own seventh.
- The wheels and the other knobs: playing what the slide plays now.
- Two hands: every key is a root, and of several held only the last pressed sounds, so a bass under the chords, or a split, is still to design.
- Combining sources further: a color held on the phone or the computer keyboard applied to a root played on the controller (the other way, a button held building the screen's chords, already works).
- Passing through: what the controller plays sent on to the "Perfecto" source, changed by the map, so a DAW hears the controller as the app plays it.
- More layouts, and a plain one for a controller with none: its keys, and the controls it has been heard to send.

## Open questions

- Whether a source should be chosen, or every source heard as it is now.
- Whether the key strip's octave should be hidden at the desk while a controller is connected, since it plays no part in the controller's chords.
- Whether the V61's buttons are momentary from the factory: the key button is read as one, and a button that latches would switch key mode only every other press.
- How the V61's octave shift should be shown while no key has been played since it was changed: the buttons send nothing, so the shift is only seen from the next note.
