# Perfecto Desk

Perfecto at a desk: an app played from a game controller, on the same theory core and sound library as the phone.
It is a Godot app (`godot/`, whose README says how it is built and run), for the Mac now and the Steam Deck and consoles after (`docs/desk-engine-and-audio.md`).
The Mac desk it grew from, a SwiftUI app on the Swift cores (`Sources/PerfectoDesk`, `Sources/DeskCore`), still builds and is to be retired.
The design it builds is `docs/gamepad-desk-ui.md`, which takes the Xbox 360 controller as the reference and lays out five ways of playing it.
Where the instincts in that note diverge, all of them are built, as layouts to choose between and refine.
Beside them is Face Chords, the simplest, which the desk opens on: it is the standard the screen is refined against.

## Running it

```bash
Desk/godot/play.sh
```

plays the Godot desk, once it is built (`godot/README.md`).
The Mac desk is `Desk/scripts/bundle.sh`, which builds `Desk/build/Perfecto Desk.app`, or `swift run PerfectoDesk` in `Desk/`.

It plays from:

- **An Xbox One or Series controller** (or any controller macOS knows), over Bluetooth or USB, read through GameController, with its motors used for rumble.
- **A wired Xbox 360 controller**, read straight from USB (`Xbox360USB`): macOS has no driver for the 360, so nothing else claims it.
  The wireless 360 needs its receiver, which speaks another protocol and is not read.
  Only the Mac desk reads it so far.
- **The computer keyboard**, always, so every layout can be tried without a controller: WASD is the left stick, IJKL the right (Shift holds it half out, for the inner ring), the arrows the d-pad, Space A, B X Y themselves, Q and E the bumpers, Z and C the triggers, R and O the sticks pressed in, Return Start and Tab Back.

The screen's right-hand panel always says what every control does now, relabelled as layers change, and lights each control while it is held.

Notes go to the kernel's own sound, to MIDI, or both (Menu › Output).
MIDI comes from a virtual source called **Perfecto Desk**, which a DAW on the Mac lists among its inputs.
The chords are on channel 1 and the line on channel 2.
Unlike the phone, a note's velocity is how hard it was struck, and what is played on a held note goes out as controllers: its swell as expression (CC 11), its brightness as CC 74, and a slide as pitch bend over ±24 semitones.

## The controls every layout shares

- **Back** goes to the next layout; a click on the layouts along the top does too.
- **Start** opens the menu: the layout, how the color ring is laid out, what Face Chords' left stick colors with, the chords' and the line's sounds, the key, the scale, the octave, the tempo, voice leading, the step compass's order, the output, and saving the arrangement as a MIDI file.
  The d-pad moves and changes, A opens, B closes.
  A on a sound opens the library: left and right through its categories, up and down through its sounds, each heard as it is reached.
- **B** lets go of everything (but in Face Chords and Petals, where it strikes, and the Arranger, where it undoes).
- The **d-pad** rolls the inversion (left and right) and moves the octave (up and down), unless a layout needs it for something else.

## The consonance guard

A switch in the menu (Consonance guard) makes the chords and notes that are not consonant unplayable, in every layout.
What it blocks stays where it is, dimmed and out of reach, so a direction keeps its meaning; a button that would strike it does nothing, the controller knocks twice for no, and the screen says why ("G maj is outside the run").
A chip beside the key says which guard is on.

"Consonant" is one rule throughout: triads (major, minor, suspended, diminished, augmented), 7ths, added 9ths and 9ths; the 11ths and 13ths, which stack a tone over another, are not.
The guard's mode says against what it is read:

- **Always**: a chord of a consonant quality, and a line's note of the key.
- **With what's sounding**: as always, and a chord must share a note with the chord sounding (so the move is near), and sit with the line's note; a line's note must make a consonant chord with the chord under it (over C major, D is an added 9th and plays, C♯ does not).
  With nothing sounding there is nothing to be near.
- **With the run**: as always, and within the notes of the last six chords played: a chord can bring at most one note from outside them, so the music drifts to new keys a note at a time, and a line's note must be one of them.
  The run is heard whether the guard is on or not; Menu › Forget the run starts it afresh, and the chip shows its notes.

**Guard: key's notes only** blocks chords and notes from outside the key as well, in any mode.
A degree on a stick whose chord the guard blocks is not chosen, and a chord being held never changes into one it blocks.

## The layouts

### Face Chords

The key's chords by number on the four face buttons, as a guitarist's chart has them.
A always plays I.
Without LT, B, X and Y play IV, V and vii°; with LT held, ii, iii and vi.
The map is `godot/project/desk/face_chords.json`, read when the desk starts (a degree for each button, without LT and with it); a mistake in it is shown and leaves this one.
What sounds is always the latest face button held, read in the layer LT is in now: pulling or letting go of LT while a button is held changes the chord as a new press does, and a button let go hands the chord back to one still held beneath it.
With no face button held nothing sounds, and LT alone strikes nothing.
LT is on past halfway, and held a little either side of it, so a trigger resting near the middle cannot flicker between two chords.
The screen shows each button as a tile where it is on the controller, with its chord's number and name and the other layer's chord in a corner, and the chord heard large in the middle.
The d-pad rolls the inversion and moves the octave, and the chord held moves with it.

#### A second voice

R3 adds a second voice, and takes it away again.
It is a line of chords of its own, an octave over the first, played in the line's sound (Menu › Line sound) and over MIDI on the line's channel.
Each press goes to one voice or both, chosen as it is pressed, and each voice sounds the latest face button it holds, as the first does alone:

- **At first** a press is the first voice's.
- **With LB held** it is the second's alone, and stays there when LB is let go.
- **LB double-clicked** puts both voices on: a press plays its chord on both, and another double-click goes back to one.
- **With both on**, LB and a face button, or a face button and LT pulled at the same moment (either first, within 80 ms), play the second voice alone, over what the first is holding.

LT struck with a face button so is the second voice's pull: the second voice plays that button's chord with LT, and the first voice keeps its chord for as long as the pull is held, as if LT were let go.
Every other pull is both voices' layer, as with one voice: LT held before a face button plays both in its layer, and LT pulled later on a held button changes both voices' chords.
A press that comes a moment before LT has been struck on both, so the first voice plays it for that moment and then goes back to what it held.

The middle of the screen names the second voice's chord under the first's, and its button has a blue bar along its foot.

#### Drums

Face Chords has a drum machine under it, and drum pads.

- **L3** starts and stops the beat, on the click, so the beat starts where it is clicked.
- **RB held** makes the face buttons drum pads: A kick, B snare, X closed hat, Y open hat; with LT held too, A low tom, B clap, X mid tom, Y high tom.
  A face button or d-pad press made under RB is the drums' until it is let go, so it never reaches the chords, and a chord held when RB is pulled sounds on.
- **RB with the d-pad**: left and right choose the beat, up and down move the tempo 4 bpm.
  The tempo is the desk's one tempo, which Menu › Tempo also sets.
- **RB with Back and Start** chooses the kit, the one before and the next.
  With the beat stopped, the new kit's kick sounds, so it is heard at once; with it playing, the next step is in the new kit.

A beat is a bar of sixteenth notes; there are six (Backbeat, Floor, Half time, Shuffle, Broken, Toms), and a new one is taken up from the step the bar is at.
It plays on under the menu, so a tempo chosen there is heard, and stops when the desk goes to another layout.
The screen shows the bar under the face buttons, its step lit as it sounds, and the beats and kits to choose from, each of which a click chooses too; while RB is held the face buttons show their drums.
Over MIDI the drums are on channel 10, as General MIDI has them (36 the kick, 38 the snare, 42 and 46 the hats).

The kits are made in code (`Sources/PerfectoDrumKit`), not recorded.
Each has a kick, a snare, a closed and an open hat, a clap and three toms, every one its own recording.
A kit is its voices (how deep the kick is and how far its pitch falls, how much of the snare is wires, what metal the hats are) and its character, what the recordings are put through after: saturation, wavefolding, compression, a low sample rate and few bits, a low-pass and a small room.
There are eight:

- **Analog**: round and long, a booming kick and soft hats.
- **Punch**: short, hard and forward, a kick that hits and a snare of noise.
- **Glue**: Punch's drums squashed together, saturated, their tails brought up under the strikes.
- **Harsh**: distorted and folded until it buzzes, bright and dense.
- **Lo-fi**: an old sampler's, at 14 kHz and 10 bits, dulled and squashed.
- **FM**: clean and glassy, bell-like hats and toms of frequency modulation.
- **Room**: drums in a room, the walls answering them.
- **Tight**: dry and short, every drum a click and gone.

#### The timeline

A bar along the top of Face Chords records what is played, layer over layer, plays it back, and edits it.
RT held is the timeline's hand, as LT is the chords' second layer: a button pressed while RT is held is the timeline's until it is let go, so it never strikes a chord.
It leaves R3 and LB to the second voice and L3 and RB to the drums.

- **RT + A** records a new layer, with every other layer playing along; again, it stops recording.
  The first take starts where its first chord was played, so there is no silence before it.
- **RT + X** plays, and stops; both start from the chords chosen, or from the top.
- **RT + ← →** choose the chord before or after; with LT held too, they stretch the choice over several.
  **RT + ↑ ↓** choose the layer.
- **With chords chosen, a chord played is written into them**, each at its own time: the progression changes and its rhythm does not.
- **RT + Y** loops the span chosen, its ends on the nearest beats: the layer repeats it for as long as the song plays, in step with where it was recorded, and its chords can still be chosen and changed.
  With nothing chosen it ends the loop.
- **RT + B** quantizes the chords chosen (with none, the whole layer) to the grid (Menu › Arranger grid; a sixteenth with none).
- **RT + right stick**: left and right nudge the chords chosen a 32nd of a beat earlier or later, again and again while held (by a line of the grid with LT); up mutes the layer; down deletes the chords chosen.
- **RT + left stick**: left undoes, right redoes.
- **RT tapped alone** lets go of the choice.

A chord changed without letting go stays joined to the next through every edit, so a progression played legato stays legato.
A song with a loop in it plays until it is stopped; one without stops at its end.
The mouse does the same from the bar: its buttons, a click on a chord to choose it (Shift stretches the choice), on a layer's number to choose the layer, and on its M to mute it.
The timeline stops when the desk goes to another layout and plays on under the menu.
Its playback goes to the kernel's sound only, not yet to MIDI, and it records the chords alone, not yet the drums or the second voice.

#### Coloring with the left stick

The left stick colors the chords the face buttons hold, and LB pins the colors it finds.
Two ways of coloring are built, to be compared: Menu › Face Chords stick chooses one, and the panel left of the face buttons shows what each direction plays on the chord held (with none held, what it does).
A color is played while the stick leans and goes when it comes back to the middle; a chord already held takes a new color tied, so only the notes that move are struck again.
The stick colors every chord held alike, both voices', each on its own degree, and a stick leaned before a face button colors the chord the button strikes.
RT held takes the stick for the timeline, so the chords are plain meanwhile.

**Orchid buttons** are the eight chord buttons of Telepathic Instruments' Orchid, a direction each:

| Direction | Button | What it does |
| --- | --- | --- |
| ↑ | Maj | the major triad in place of the degree's own |
| ↗ | m7 | adds the minor seventh |
| → | 9 | adds the ninth |
| ↘ | M7 | adds the major seventh |
| ↓ | Min | the minor triad |
| ↙ | 6 | adds the sixth (on a diminished triad, its seventh: a diminished seventh) |
| ← | Dim | the diminished triad |
| ↖ | Sus | the fourth in the third's place |

Face Chords plays in the Orchid's key mode: with no type held, the triad is the degree's own, so the extensions add to the chord the key has.
The Orchid's buttons are pressed two at a time, and so are these: **lean to one, then roll round the rim to another without coming back through the middle**, and both are held.
The direction first leaned to stays held for as long as the stick is out, and whichever direction it is on now is added to it, as a second finger would be; back at the first, it is held alone again.
Of two types the later plays, as on the Orchid; the sixth over a seventh is the thirteenth, and the two sevenths together are the major one.
The buttons are laid round the stick so each direction's neighbours make a chord with it, a short roll away: Maj and m7 a seventh (on ii, II7, its secondary dominant), m7 and 9 a ninth, 9 and M7 a major ninth, M7 and Min a minor-major seventh, Min and 6 a minor sixth, 6 and Dim a diminished seventh.
Pairs further apart are reached by rolling further, through the directions between, which sound on the way.
The Orchid itself was played from a MIDI controller, its type and extension buttons on two rows of pads (`docs/midi-controller.md`); the Orchid has eight buttons, so the stick has one in each of its eight directions.

**Perfecto · default, extended and chromatic** are the phone's joystick (its default mode to start with, the original coloration), its table as it was (`JoystickMap`), in one of its three modes: in the default mode ↑ flips the third, ↗ a dominant seventh, → a major seventh, ↘ add9, ↓ sus4, ↙ a sixth (sus2 on a minor chord), ← lowers the third, ↖ augments; the extended and chromatic modes have the jazz colors (9, 11, 7♯9, half-diminished; 13, 6/9, 7alt, maj7♯11 and more).
The panel names each direction's color by the chord it makes on the chord held.

**Pins** keep the colors found for a chord, to play from a layer of their own:

- **LB pressed while the stick colors a chord** pins that color to it, two buttons held and all; pressed again on a color already pinned, it takes it out.
  A knock says it was pinned, a tick that it was taken out.
- **LB held** puts the chord's pins on the left stick: the first pin is at the top and each next one clockwise, up to eight, and a direction with no pin plays the chord plain.
  Pressed while coloring, the stick keeps the color it pinned until it moves to another direction, so nothing jumps.
- The pins are the favorites (below, under Twin Rings), in the table played: a chord's pins are its degree's favorites in the key, so what is pinned here is in the Favorites tab and in Twin Rings' Y layer, and the other way round.

LB is the toggle because it is the one control that is free with a face button and the stick both held: the thumbs are on them, the d-pad is under the same thumb as the stick, LT is the face buttons' second layer, RB the drums and RT the timeline, and L3 starts the beat.
LB's own uses are the second voice's, and they are read from the face buttons' presses, so they still work: with LB held a face button pressed goes to the second voice, and the stick plays that chord's pins.
Two presses of LB within a third of a second still switch both voices on, with the second voice added, so pin and unpin with a breath between.
The timeline records a colored chord as it sounds.

### Twin rings

The recommended model.
The left stick is a pie of the seven degrees in scale order, I at the top and on clockwise (I ii iii IV V vi vii°); the chords sharing two notes with the one sounding are lit, wherever they are.
The right stick is the color ring: its angle the mode, darker anticlockwise and brighter clockwise, each sector a note or two from the next; its radius the stack height (7th, 9th, 11th; with RB held, 9th to 13th).
The modes are named round the outside, the key's own is marked, and the gap where the darkest and brightest would meet is labelled.
RT strikes, louder the faster it is pulled, and its depth then swells and brightens what sounds; A strikes at a fixed level.

A lean on the right stick is played while it is held and goes back when it is let go.
A flick (out and back quickly) keeps the cell it pointed at, so kept and played are told apart by the hand, with no latch.
LB held puts the step compass on the right stick while it is held, and a long-press of LB (held a third of a second) leaves it on after LB is let go, until another long-press; a tap of LB still moves the key a fifth down. The compass: up adds a tone, right raises one, down takes one away, left lowers one, each kind's second choice a little clockwise of its first.
The LB layer has a second view, the **voices** (L3 while the layer is on, or Menu › LB layer, switches between it and the compass).
It is chords as voices moving, after Dmitri Tymoczko's *A Geometry of Music*: a chord is a point with a coordinate for each voice, and the chords near it are the ones a small motion of its voices reaches.
The consonant chords are the nearly even ones, which are exactly those a small motion joins, so nearness keeps consonance close at hand.

- The **right stick** moves the two highest voices: up and down the top voice, right and left the middle one, the upper right and lower left both together, and the other two diagonals in contrast (closer and wider).
  The inner ring moves each voice a semitone and the outer ring two, so the shells round a chord are its neighbours a semitone and two away.
- The **left stick**, up and down, moves the bass, while the voices are on.
- Every move is exact, so a direction always means the same motion; a move that lands on a chord that is not consonant (a triad, a 7th, an added 9th, or the evenly divided diminished and augmented) is dimmed and cannot be taken, and one that would cross or meet another voice is not offered.
- The root is free to move: C major's top voice up two is A minor over C, its bass down a semitone E minor over B.
- A flick takes the step and the next steps walk on from there; a lean held plays the move and goes back; R3 while leaning takes it.
  R3 at rest takes the walk back to the chord it started from, then the compass's step, then the color.
  Choosing another degree on the left stick (with the layer off) starts afresh.

A chord of four voices or more moves its two highest and its lowest; the others stay.

LT is the arpeggio, off and then quarter, eighth and sixteenth notes as it is pulled, a tick felt at each.
A bumper tapped moves the key a fifth; X switches voice leading; Y holds the chord after the strike lets go.
R3 with the stick at rest is the middle: it takes back the compass's step first, to the chord as it was before the compass, and then the color, to the plain chord; the middle of the compass says what it will go back to.

The ring can be laid out three ways, since each gives up something the others keep.
L3 turns to the next, as do Menu › Color ring and the switch over the ring; Petals and the Arranger follow the same choice.

- **Home**: the major scale's seven modes, turned so the degree's own is at the top, so up is always the chord as the key has it.
  The ring is lopsided by as much as the own mode is near an end (on I, one sector brighter and five darker), so the gap moves with the degree.
- **Fixed**: the same seven modes, never turned: Dorian at the top and the gap at the bottom, so a direction always means the same mode, and the key's own chord is wherever its mode is.
  In brightness order its two sides are mirror images: each mode faces its inversion across the stick (Lydian and Locrian, Ionian and Phrygian, Mixolydian and Aeolian), with Dorian, its own mirror, at the top.
- **Centred**: the degree's own mode at the top with the modes nearest it in brightness either side, from the major, melodic minor and harmonic minor scales (the chord grid's rows), so it is balanced on every degree as far as the brightest and darkest modes allow.

A kept color names its mode, not its place, so it stays kept when the ring is turned another way.

The sectors can also go round in different orders (Menu › Ring order), so that a direction and a grouping come to mean a quality.
Each combines with the arrangement: Home and Centred keep the key's own mode at the top, and Fixed keeps every direction the same from degree to degree.

- **Brightness**: darkest anticlockwise to brightest clockwise, a note at a time (for these modes, the circle of fifths).
- **Quality**: modes with a major third clockwise and with a minor third anticlockwise, each side's brightest by the seam at the top, the diminished at the far end.
- **Character note**: by the one note that makes each mode itself: Ionian and Aeolian, which alter nothing, in the middle; a note raised (Dorian ♮6, Lydian ♯4) clockwise; a note lowered (Aeolian's neighbours Mixolydian ♭7 and Phrygian ♭2, then Locrian with two) anticlockwise.
- **Fewest borrowed**: the fewest notes from outside the key at the top, fanning out either side to the most by the gap.
- **Common first**: the modes most played at the top (Ionian, Aeolian, Dorian, Mixolydian, Lydian, Phrygian, Locrian), fanning out; with Fixed, Ionian is always at the top.
- **Nearest**: nearest the chord last struck at the top, fanning out, so it turns as you play; it follows the chord struck, not the one a lean is sounding, so it never turns under the thumb.

In the fanned orders, of two modes ranked alike, the brighter goes clockwise.

A filter (Menu › Ring filter) leaves some cells out of reach: **In key**, **Major third**, **Minor third**, or **No clash** (no tone a semitone over another).
The cells it leaves out keep their places, dimmed and unlabelled, so a direction still means what it did; a sector with nothing left in it is out of the stick's reach.
The order and the filter shape the right stick's ring in Twin Rings and the Arranger; Petals' triggers always step darker and brighter by brightness.

#### Favorites

Colors can be pinned to the chords of a key and played from their own layer.
Favorites are kept in named tables ("Jazz", "Pop", "Film"); one table is played at a time, and a table can be made a key's own, so changing to that key turns to it.
A chord holds up to eight favorites in a table, one for each of the right stick's directions.

- **Hold Y**: the right stick is a pie of the chord's favorites in the table played, a flick keeping one and a lean playing it, as the compass does; the compass still steps from a kept favorite.
- **Y + A** pins the chord the hands are on (flick to keep a color first: the right thumb cannot lean and press Y at once), and **Y + X** unpins the favorite aimed at.
- **A tap of Y** still holds the chord, as before.

The Favorites tab beside the stage (next to Controls) does the same with the mouse, from any layout: it lists the tables (a click plays one; the pencil renames it), adds and removes them, makes the one played the key's own, pins the chord sounding, and shows each chord of the key's favorites with a button to unpin each.
A borrowed chord is pinned by its notes to the degree of its root; a root outside the key cannot be pinned.
Favorites are kept with the settings between launches.

### Petals and depth

The easiest to start with, and the crispest rhythm.
The left stick chooses the degree; the face buttons strike it at four heights, a diamond rising clockwise from A (triad, 7th, 9th, 11th).
LT darkens the mode a sector at a time and RT brightens it, each step a felt detent, and the diamond on screen always shows what each button would strike at the triggers' depth now.
LB held puts marks on the buttons (sus4, add9, ▲5, 6); RB held puts the effects there (arpeggio, its rate, voice leading, hold).
The right stick bends the voicing while it leans (across the inversion, up and down the octave), and R3 keeps the bend.
The d-pad moves the key round the circle of fifths and through the scales.

### Neighbourhood

No chord is chosen by name: the screen is centred on the chord sounding, and round it are the chords one step away.
The bumpers choose what a step is: the **color** lens (the step compass's tones added, raised, taken away and lowered), the **Tonnetz** lens (P, R and L, a fifth either way, and the hexatonic and N moves), or the **degrees** lens (the key's other degrees by the cycle of thirds).
A flick moves there and strikes it; a lean held listens and comes back, and R3 while leaning moves there.
The left stick walks back and forward along the path of chords moved through; L3 bookmarks the centre, and with Y held the right stick reaches the eight bookmarks.
RT swells and LT darkens; X goes home to I.

### Two voices

Each hand an instrument, each with its trigger as pressure.
The left stick chooses the degree and LT swells the chord from silence, an organ's expression pedal; LB steps its color through triad, 7th and 9th, and A makes it drone.
The right stick points at the key's seven notes, the tonic at the top, the chord's own notes marked and an outer ring an octave up; RT strikes the note pointed at, and moving to another petal while it is held slides there.
Y leaves only the chord's own notes to point at.
With RB held, the right stick is a Trautonium's bar: two octaves of continuous pitch, which comes to rest on the key's nearest note when the stick stays put.

### Arranger

The other layouts play; this one writes, in time.
The sticks aim a chord as Twin rings does, and it is placed in four bars, each chord with its own start and length, and silence where nothing is placed.
The bars are drawn as four lanes, each chord as long as it lasts, with the cursor in orange and the playhead moving through them.

There are three ways to give a chord its length:

- **Hold to write.** With the bars stopped, RT held at the cursor sounds the aimed chord and writes it for as long as it is held, at the tempo.
  It grows on the screen as it is held, a tick is felt on each beat, and on letting go it is snapped to the grid and the cursor moves to its end.
- **Record live.** With the bars playing (Y), RT writes at the playhead: the chord starts where it was struck, on the nearest line of the grid, and is as long as it was held.
- **Stretch.** LB and RB shorten and lengthen the chord at the cursor (or the one that has just ended there): a tap by a line of the grid, a hold smoothly, for as long as it is held, as far as the next chord.

The grid is Free, 1/16, 1/8, 1/4 or 1/2, changed by L3 or Menu › Arranger grid; it snaps the cursor's moves and every length, and Free snaps nothing.
A writes a beat's chord at the cursor, X clears the chord there, B undoes, LT listens to the aimed chord, and the d-pad moves the cursor a line of the grid or a bar.
The tempo is in the menu.
Menu › Save the arrangement writes it as a MIDI file to Music › Perfecto Desk, each chord as long as it was written.

## How the principles are carried

- **Consonance.** Every target is a chord of the key unless it says otherwise: a borrowed chord is drawn dashed and in italics, and one with a semitone clash is dimmed.
  The pies offer the key's own chords first, the line offers the key's own notes, and the bar comes to rest in tune.
- **Nearness.** What is one step from the chord sounding is lit, in every layout that has a sounding chord: the ring's cells a note away, the degrees sharing two notes, and in the Neighbourhood nothing but the near.
  On the degree pie the chords sharing two notes with the one sounding are lit, and voice leading (X in Twin rings) keeps each chord as close to the last as it can be.
- **Low threshold.** A plays the tonic's chord on the first press, in any layout that strikes, and the screen names every target by what it would sound before it sounds.
  The keyboard plays everything, so a controller is not needed to start.
- **Wide walls.** Five layouts on one core: harmony by name, by color, by step, as two voices, and as a written progression, with the sound library and MIDI under all of them.
- **High ceiling.** Twin rings reaches 154 chords in one gesture and more with the compass; the Neighbourhood's lenses walk anywhere a step at a time; Two voices has continuous pressure and pitch.

## How it is built

The layouts are a functional core with an imperative shell.

- `DeskCore` is pure: a `GamepadFrame` (every stick, trigger and button at one moment) goes into `Desk.step`, which returns the new state and the effects for the shell to perform, as values (`DeskEffect`: sound these notes on a line, shape them, let go, rumble, preview a sound, save a file).
  The analog surfaces are read by small gates (`PieGate`, `RadialBands`, `TriggerStrike`, `TriggerSteps`, `StickGesture`, `TapOrHold`), each holding on past its edges so a resting thumb cannot flicker.
  Each layout is a `Layout`, stepped by frames against the `DeskSettings` they share, and every chord is a `DeskChord` voiced by the theory core's `computeVoicing`.
  Its tests script frames and check the effects by equality.
- What the screen shows is a value too, made by the C++ core (`scene.hpp`), so the Godot desk's scripts only draw it.
- The timeline is a core of the C++ desk alone, beside `Desk` and not inside it, so the desk the parity test plays is unchanged: the song and its edits are values (`song.hpp`: layers of events, loops, nudge, quantize, rechord), the hands and the transport are `Timeline` (`timeline.hpp`), and `Studio` (`studio.hpp`) composes the two, handing the desk each frame without what RT holds and the timeline what the desk sounds.
  What plays back is worked out 50 ms ahead and stamped with the moment it sounds, and the shell puts each on its kernel frame.
- The Godot desk's shell is `godot/extension` (`PerfectoDesk`, in C++), which reads the controller and the keyboard through Godot, steps the C++ core, and plays its effects on the kernel, MIDI and the motors (`godot/README.md`).
- The Mac desk's shell is `Sources/PerfectoDesk`: `DeskHost` reads the controllers 250 times a second, merges them into one frame, steps the desk, and performs its effects on `DeskAudio` (the kernel's Audio Unit, with every preset loaded), `DeskMIDI` and the controllers' motors.
  The screen is shown the desk at most 60 times a second, and only when it has changed.
- The theory core (`MusicTheoryCore`) and the sound library (`PerfectoSound`: the presets, their patches and the kernel as an Audio Unit) come from the Perfecto package, the same files the phone's app compiles.

The Mac desk keeps the settings and the layout between launches; the Godot desk does not yet.
Events worth knowing are logged to the unified log under `com.perfecto.desk`.

## Open

- Nothing has been tried on a real 360 yet: the USB reader follows the controller's documented protocol, and the Xbox Wireless Controller is read through GameController.
- How many radial bands a thumb holds, whether the trigger's strike feels early or late, and whether flick and hold are told apart reliably are all to be found out by playing (`docs/gamepad-desk-ui.md`, Open questions).
- The phone's effects (chorus, delay, vocoder, key zones) and loops are not at the desk; the sound has a little reverb and nothing else.
- The Dissonance Lab's beating rumble (Model 4's second half) is not built: the lab is parked off v0.1.0.
