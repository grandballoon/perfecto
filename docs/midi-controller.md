# The MIDI controller

A hardware MIDI controller is to be played as an instrument of the app's own: its keys and its other controls made into what the app plays (an Orchid's chord buttons and roots, or another way of playing), and combined at once with what another source does (a phone, the computer keyboard, a game controller).

## What is built

The desk has a pane for the controller (CTRL), which draws it and lights it with what it sends.

- `MidiInput` hears every MIDI source but the app's own.
- `ControllerLayout` is a device's face: each control's kind, frame and factory message. The Alesis V61 (the first, not the MKII) is the only one so far.
- `ControllerState` reads each message against the controls' bindings; a note no control has is a key, and the keys' octave shift is worked out from the notes.
- LEARN teaches a control what it sends: choose it on the drawing, then press or move it on the device. The learned bindings are saved by layout, and RESET forgets them.

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

- Playing from it: a map from the controller's controls to what the app plays, as `KeyboardMap` is for the computer keyboard, through `PerformanceState`'s calls so that modes and sinks know nothing of it.
- An Orchid-like map: the keys choose a chord's root (as the octave layout's keys do) and the pads and buttons its color, with the wheels and knobs playing what the slide plays now.
- Combining sources: each source a finger of its own, so a color held on the phone or the computer keyboard applies to a root played on the controller.
- Passing through: what the controller plays sent on to the "Perfecto" source, changed by the map, so a DAW hears the controller as the app plays it.
- More layouts, and a plain one for a controller with none: its keys, and the controls it has been heard to send.

## Open questions

- Whether a source should be chosen, or every source heard as it is now.
- Whether the controller's own notes should sound while nothing is mapped.
- How the V61's octave shift should be shown while no key has been played since it was changed: the buttons send nothing, so the shift is only seen from the next note.
