# Perfecto Desk

Perfecto at a desk: a Mac app played from a game controller, on the same theory core and sound library as the phone.
The design it builds is `docs/gamepad-desk-ui.md`, which takes the Xbox 360 controller as the reference and lays out five ways of playing it.
Where the instincts in that note diverge, all of them are built, as layouts to choose between and refine.

## Running it

```bash
Desk/scripts/bundle.sh
```

That builds `Desk/build/Perfecto Desk.app`, which opens like any app.
`swift run PerfectoDesk` in `Desk/` runs the same app without a bundle, and `swift test` there runs the core's tests.

It plays from:

- **An Xbox One or Series controller** (or any controller macOS knows), over Bluetooth or USB, read through GameController, with its motors used for rumble.
- **A wired Xbox 360 controller**, read straight from USB (`Xbox360USB`): macOS has no driver for the 360, so nothing else claims it.
  The wireless 360 needs its receiver, which speaks another protocol and is not read.
- **The computer keyboard**, always, so every layout can be tried without a controller: WASD is the left stick, IJKL the right (Shift holds it half out, for the inner ring), the arrows the d-pad, Space A, B X Y themselves, Q and E the bumpers, Z and C the triggers, R and O the sticks pressed in, Return Start and Tab Back.

The screen's right-hand panel always says what every control does now, relabelled as layers change, and lights each control while it is held.

Notes go to the kernel's own sound, to MIDI, or both (Menu › Output).
MIDI comes from a virtual source called **Perfecto Desk**, which a DAW on the Mac lists among its inputs.
The chords are on channel 1 and the line on channel 2.
Unlike the phone, a note's velocity is how hard it was struck, and what is played on a held note goes out as controllers: its swell as expression (CC 11), its brightness as CC 74, and a slide as pitch bend over ±24 semitones.

## The controls every layout shares

- **Back** goes to the next layout; a click on the layouts along the top does too.
- **Start** opens the menu: the layout, the chords' and the line's sounds, the key, the scale, the octave, the tempo, voice leading, the step compass's order, the output, and saving the arrangement as a MIDI file.
  The d-pad moves and changes, A opens, B closes.
  A on a sound opens the library: left and right through its categories, up and down through its sounds, each heard as it is reached.
- **B** lets go of everything (but in Petals, where it strikes, and the Arranger, where it undoes).
- The **d-pad** rolls the inversion (left and right) and moves the octave (up and down), unless a layout needs it for something else.

## The layouts

### Twin rings

The recommended model.
The left stick is a pie of the seven degrees in the cycle of thirds (I iii V vii° ii IV vi), so neighbouring sectors share two notes and rolling the thumb round is the smoothest chain of chords the key has.
The right stick is the color ring: its angle the mode (the degree's own at the top, darker anticlockwise, brighter clockwise), its radius the stack height (7th, 9th, 11th; with RB held, 9th to 13th).
RT strikes, louder the faster it is pulled, and its depth then swells and brightens what sounds; A strikes at a fixed level.

A lean on the right stick is played while it is held and goes back when it is let go.
A flick (out and back quickly) keeps the cell it pointed at, so kept and played are told apart by the hand, with no latch.
LB held puts the step compass on the right stick: up adds a tone, right raises one, down takes one away, left lowers one, each kind's second choice a little clockwise of its first.
LT is the arpeggio, off and then quarter, eighth and sixteenth notes as it is pulled, a tick felt at each.
A bumper tapped moves the key a fifth; X switches voice leading; Y holds the chord after the strike lets go; L3 goes back to the plain color.

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

The other layouts play; this one writes.
The sticks aim a chord as Twin rings does, the d-pad moves a cursor over four bars of beats, A writes the aimed chord on the cursor's beat, and RT writes it held for as long as RT was pulled deep (one, two or four beats).
X clears a beat, B undoes, LT listens to the aimed chord, the bumpers change the tempo, and Y plays the bars round from the cursor, through the same sound and MIDI as everything else.
Menu › Save the arrangement writes it as a MIDI file to Music › Perfecto Desk.

## How the principles are carried

- **Consonance.** Every target is a chord of the key unless it says otherwise: a borrowed chord is drawn dashed and in italics, and one with a semitone clash is dimmed.
  The pies offer the key's own chords first, the line offers the key's own notes, and the bar comes to rest in tune.
- **Nearness.** What is one step from the chord sounding is lit, in every layout that has a sounding chord: the ring's cells a note away, the degrees sharing two notes, and in the Neighbourhood nothing but the near.
  The degree pie is in the cycle of thirds so that what is near on the stick is near in the ear, and voice leading (X in Twin rings) keeps each chord as close to the last as it can be.
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
- `PerfectoDesk` is the shell: `DeskHost` reads the controllers 250 times a second, merges them into one frame, steps the desk, and performs its effects on `DeskAudio` (the kernel's Audio Unit, with every preset loaded), `DeskMIDI` and the controllers' motors.
  The screen is shown the desk at most 60 times a second, and only when it has changed.
- The theory core (`MusicTheoryCore`) and the sound library (`PerfectoSound`: the presets, their patches and the kernel as an Audio Unit) come from the Perfecto package, the same files the phone's app compiles.

Settings and the layout are kept between launches.
Events worth knowing are logged to the unified log under `com.perfecto.desk`.

## Open

- Nothing has been tried on a real 360 yet: the USB reader follows the controller's documented protocol, and the Xbox Wireless Controller is read through GameController.
- How many radial bands a thumb holds, whether the trigger's strike feels early or late, and whether flick and hold are told apart reliably are all to be found out by playing (`docs/gamepad-desk-ui.md`, Open questions).
- The phone's effects (chorus, delay, vocoder, key zones) and loops are not at the desk; the sound has a little reverb and nothing else.
- The Dissonance Lab's beating rumble (Model 4's second half) is not built: the lab is parked off v0.1.0.
