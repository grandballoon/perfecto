# The color ring

The chord colors of the v0.1.0 release: a ring of the chord grid's colors, laid out so that colors one note apart sit next to each other, with marks under it that move a tone of the chord a semitone or leave it out.
Its mockup is board AA of the "Unified Chord Shaper" canvas (https://claude.ai/artifact/WEjCsXxRYc99KrQZfpq4Dd); boards Y and Z are the ring and the joystick's colors put to the same test.

## Where this fits

v0.1.0 is Play mode alone (decided on 2026-10-21): the other features are kept on branches, not deleted, and come back after the release.
The ring is a third color surface (`ColorSurface.ring`) beside the joystick bar and the chord grid, and the app starts on it (`PerfectoApp`); Setup's Surface picker still has the other two until the release takes them off.
On a phone on its side with the circle layout, the ring and its marks have the leading half to themselves, as large as the half's height allows; the note display, the sound, the key and the voicing are in two rows over the chord keys in the trailing half, and the function buttons, the loop bar, the effect strip and the key strip's color field are not drawn (`PerformanceView.ringLandscapeLayout`).
Upright, the ring and its marks are in the chord colors' place under the keys (`SurfaceShape.ring`), which is cramped; a phone on its side is the screen this is designed for.

## What the ring is

The ring has a band for each stack of thirds and a sector for each mode of the major scale.

- Going outward adds a note: the triad innermost, then the 7th, the 9th, the 11th and the 13th (`StackHeight`).
- Going round changes the scale the notes come from, one note at a time, from the darkest mode to the brightest: Locrian, Phrygian, Aeolian, Dorian, Mixolydian, Ionian, Lydian (`ColorRing.modes`).
- Locrian and Lydian are five notes apart, so the seven sectors take 300° and the ring has a 60° gap where they would meet.
- The held degree's own mode is shaded and its name lit.

It has two arrangements of the same colors, one at a time, chosen in Setup (`PerformanceState.ringArrangement`):

- **Fixed**: the sectors never move. Dorian, the middle of the order, is at the top, and the gap is at the bottom. A place on the ring is always the same chord shape.
- **Home**: the ring is turned so the held degree's own mode is at the top (`ColorRing.turn`). The top is always the chord as the key has it, and the gap moves round with the degree.

A cell is a `ColorRingPosition`: a height and the mode it stacks through, or nil for the degree's own mode.
A tap on a home ring's own sector chooses nil, so it stays each degree's own mode as other degrees are played; every other tap chooses its mode.
So switching the arrangement changes nothing that sounds.

The cells one step from what is playing are lit (`colorSteps`).
A step adds a note, takes one away, or moves one a semitone, counted between pitch classes, so a 9th is its 2nd.
On the ring, 54 of the 58 pairs of touching cells are one step apart; the other four are where `stackThirds` leaves out a clashing tone (`ColorStepsTests`).
Cells with the same notes as the chosen one are outlined, as the plain major triad is in Lydian, Ionian and Mixolydian.

## The tone marks

Under the ring, a column for each tone above the root (3, 5, 7, 9, 11, 13), each with ▲ a semitone up, ▼ a semitone down, and ✕ leave it out (`ToneMarksRow`).
A chord symbol is built the same way, as a stack and marks on its tones (C9♯5♯9), so the name the display shows is the stack's and the marks in brackets: "G 9(♯5, ♯9)".
Every mark is one step (`ColorStepsTests.everyMarkIsOneStep`), so a mark is a move to a neighbour, as a move round the ring is.

- A mark is named by what it makes of the tone: ▲ sus4 on a major 3rd, ▼ 6 on a ♭7, ▲ ♯9.
- A move is not made where the tone has no name (a major 7th raised would be the root) or another tone already sounds that pitch class, since landing on one is a tone lost, not moved (`markedTones`).
- A tone the stack leaves out because it clashes (the 3rd of a major 11th, the 11th of a major 13th, `droppedTones`) has its ✕ outlined, and the mark brings it back ("add 3").
- A tone the cell has not got is dimmed.

Every color the joystick has, on a major, minor or diminished chord, is a cell and at most three marks: sus4 is a triad ▲3, sus2 a minor triad ▼3, add9 a 9th ✕7, 6 a 7th ▼7, 6/9 a 9th ▼7, aug a triad ▲5, 7♯9 a 9th ▲9, 7♭9 a 9th ▼9, 7alt a 9th ▲5 ▲9, m(maj7) an m7 ▲7, maj7♯11 the Lydian 11th ✕9, and add11 the Ionian 11th with its 3rd back, ✕7 ✕9.
Of the 59 distinct shapes, 24 are a cell, 27 a cell and one mark, 7 two marks and one three.
That is why the modes of harmonic minor and melodic minor are not on the ring: their colors are marks on the major scale's, and on the ring their sectors would be two to four notes from their neighbours.

## Kept, or played

A pin beside the marks says whether the ring keeps what it is set to (`PerformanceState.keepsRingColor`, on to start with), as the key strip's fields have.

- While it keeps, a cell tapped and the marks stay until another cell or mark is tapped, or COLOR ↺ goes back to the plain chord (`resetRingColor`), so every chord played after them is in their color. Playing a chord, choosing its color and marking a tone then needs no more than one finger at a time.
- While it does not, they are played: the cell only while a finger is on the ring (`ringLifted`), and a mark only while its button is held (`pressToneMark`, `releaseToneMark`), so lifting goes back to the plain chord and COLOR ↺ has nothing to undo. Several marks can be held at once; of two moves of one tone, the last pressed plays.
- What is kept is left as it was while the ring plays, and is back when the pin is.

A change reaches the chord being held at once, as a change of the joystick's or the grid's color does (`mode.onColorChange`).

## Where it is in the code

- The music theory core, pure:
  - `ToneMarks.swift`: `ChordTone`, `ToneMarks`, `markedTones`, `markedStack`, `markNames`, `markedChordName`, `toneMarkOptions`.
  - `ColorRing.swift`: `ColorRingArrangement`, `ColorRingPosition`, `ColorRing` (the modes, the turn, positions and colors), `ChordColor.tertian`.
  - `ColorSteps.swift`: `colorSteps`.
  - `ChordColor.marked(StackHeight, HeptatonicMode?, ToneMarks)`: a grid color with marks, never with none (`ChordColor.tertian` makes a grid color then). `chordShape` plays it through `markedStack` and names it with `markedChordName`; ChordLink releases it as it does a grid color.
- The state: `PerformanceState.ringArrangement`, `keepsRingColor`, `ringPosition` and `toneMarks` (kept), `playedRingPosition` and `heldMarks` (played), `ringCell` and `ringMarks` (as they play), `ringChose`, `ringLifted`, `pressToneMark`, `releaseToneMark`, `resetRingColor`, and `color(for:in:)`'s `.ring` case. Switching surfaces clears the ring with the others.
- The views: `ColorRingGeometry` (where the cells are, by which the ring is drawn and read), `ColorRingPad` (the ring), `ColorRingSurface` and `ToneMarksRow`.
- Setup: the COLOR RING choice, shown while the ring is the surface.
- The sequencer's step editor and the pad editor color from the grid while the ring is the surface; the marks are for playing.
- Logging: `ring_color_changed(arrangement:color:)`, `ring_arrangement_switched(arrangement:)` and `ring_keep_switched(isOn:)`.
- The UI spec: `play-ring-fixed` and `play-ring-home`.

## What is left out

- The voicing ring around the color ring (boards U to X): the key strip's voicing field stays as it is.
- Marking the notes from outside the key, which board Y does on its piano.
- The other colors' place in the release: the joystick bar and the chord grid are still in Setup, until the release takes them off.

## Open questions

- **Which arrangement stays.** The Setup switch is for comparing. Once one arrangement is chosen, the switch goes.
- **Upright.** The ring has little room under the keys; whether the release is played on its side only is still to be decided.
