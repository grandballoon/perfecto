# Solo strip

A strip of notes beside the chord keys for playing runs on top of whichever chord is pressed.
Every note it offers fits the chord, so it keeps Perfecto's "no wrong notes" convention.
The idea was noted on 2026-10-07, and a first version was built the same day for trying on the phone.

## What is built

The SOLO button, beside MIDI, switches the strip on.
Setup's SOLO STRIP choice says where it goes:

- **Under**: under the chord keys, which give up some of their height.
  The handle between them is dragged to give the strip more or less.
  On its side, a phone that has room to spare beside the keys (the grid and circle layouts) puts the strip there, and the keys give up nothing.
- **Beside**: upright along the trailing edge of the keys, which give up some of their width.
- **Colors**: in the chord colors' place, so the two cannot be played together.

The strip is one voice.
A finger on a cell sounds its note, sliding along the strip plays a run, and with two fingers down the newer one sounds and lifting it hands the note back to the other.
It sounds in the keys' preset, with the effects as they are set, and goes out over MIDI with the chords.

### Which notes

The pentatonic the chord implies (`soloIntervals`):

1. The triad the chord is built on, always.
2. Each note of the chord's scale that is not a semitone from a note of the triad.
3. Of two such notes a semitone apart, only the upper.

So a major chord gets the major pentatonic, a minor chord the minor one, and a dominant keeps its seventh.
A chord whose triad leaves the scale little room (diminished, augmented) gets little more than its own tones.
The chord's scale is the mode a grid color names, and the key's scale otherwise.

A seventh that a color adds is not part of the triad, so the strip does not have it: over G maj7 it plays G A B D E, without the F♯.

### Where each note sits

The cells ascend from the key's tonic, in the octave the chords are built in, whatever the chord.
Between the chords of a key most cells keep their note and the others move by a step, so the hand does not lose its place.
The chord's own tones are tinted and its root carries a mark.

### The chord it plays over

The chord that is sounding.
With none, the last chord played (the tonic's triad before any has been), so the strip can still be played once the keys are let go.
A note being held rings on when the chord changes under it; the next cell pressed is the new chord's.

## Still open

- **Which notes.** The pentatonic is the middle of three tiers.
  Chord tones only is safer and gives arpeggios, not runs.
  The chord's scale with only its avoid notes removed has the seventh the pentatonic lacks.
  A setting could step through them.
- **Going further.** "Wrong" is mostly about what a note does, not which pitch it is.
  The promise could become "tension always resolves": avoid notes that glide to a neighbour when held, pitch that is continuous between cells and settles on landing, ornaments as gestures.
- **A held note at a chord change.** It rings on now; it could bend to the nearest note that fits.
- **The lead voice.** A patch and a volume of its own, and glide.
- **Loops.** A loop does not record what the strip plays, since a take is chords.
- **A layer's chord.** With no key held, the strip follows the chords of the layer shown in the sequencer, as the display does, and no other layer's.
- **Placement.** Three are built to be compared; one may be enough.
- **The SOLO button.** It is on the play screen and not in the menu, where every other setting is.
