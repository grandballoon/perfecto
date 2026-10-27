# A controller at a laptop: design exploration

What the app becomes if an Xbox 360 controller is the only input and a laptop's screen is the only display.
This began as an exploration, not a decision, and nothing in it changes the phone.
All five models are now built as layouts of a Mac app of their own, Perfecto Desk (`Desk/`, whose README says how each is played and what is still open).

The product's guiding sentence is: allowing the user to create consonant, beautiful music, in a theoretically rigorous way, with as much of the relevant option available and visible in a random access pattern.
On the phone that means a finger can land anywhere, so every option is a place on glass.
A controller has no places, only a hand state: which sticks lean where, which buttons are down, how far the triggers are pulled.
So here "random access" becomes: **everything one gesture away from the hand's current state is drawn on the screen and labelled with what it would sound.**
With no fingers over the screen and a laptop's width of it, that is affordable in a way it never is on a phone.

## Where the app is today

The controller is "one more finger" (`GamepadState`, `GamepadInput`, `KeyboardMap.gamepad`, `GamepadStick`).
Its buttons are keys of a small keyboard: the seven degrees on A, B, X, Y and three of the d-pad, loop on R1, solo on L1, play and stop on Menu.
The left stick is the joystick, read into the nearest of eight directions with hysteresis (`GamepadStick.direction`).
The triggers are read only as buttons, the right stick not at all, and nothing rumbles.
Everything it does goes through `PerformanceState`'s own calls, so nothing downstream knows of it.
That boundary is worth keeping: every model below is a new front end over the same calls (`press`, `release`, `ringChose`, `ringLifted`, `pressToneMark`, `holdVoicing`, `releaseVoicing`, `EffectsState.holdArpeggio`, `setBrightness`), plus a few new ones where noted.

## The hand, as a budget

Before the models, what a hand on this controller can actually do at once.
This decides more than any screen does.

- **Each thumb is on one surface at a time.**
  The left thumb is on the left stick or on the d-pad; the right thumb is on the right stick or on the face buttons.
  A model that needs the right stick and a face button at the same instant needs a third thumb.
- **The index fingers rest on the bumpers or the triggers, one each.**
  In a claw grip a middle finger can take the trigger while the index keeps the bumper, so four shoulder controls at once is possible but tiring; two at once is the honest budget.
- **Analog surfaces:** two sticks (2D each, about 8 bits of usable angle and 3 to 4 usable rings of radius once the dead zone and the 360's loose centre are taken out) and two triggers (one axis each, about 256 levels, of which a hand holds perhaps 4 to 6 steadily without help).
- **Digital surfaces:** A, B, X, Y, LB, RB, Back, Start, L3, R3, and the d-pad.
  The 360's d-pad is a disc on a pivot: its four cardinals are reliable and its diagonals are not, so a model should ask only cardinals of it.
- **Clicking a stick moves it.** L3 and R3 are pressed with the thumb that aims the stick, and pressing pushes the aim inwards and a little off; a click is only safe at the centre or as "commit what I am pointing at", read from the angle a moment before the click.
- **Springs.** Both sticks and both triggers spring back.
  That makes them natural "played" controls (held while the hand holds them, gone on release), the same meaning `keepsRingColor` and the key strip's switches give "not kept".
  Anything "kept" needs a latch: a click, a button, or a gesture read as a commit.
- **Rumble.** Two motors, a heavy low one and a light high one, each with a level.
  Their response is slow (tens of milliseconds to spin up), so rumble can carry rates up to perhaps 15 to 20 Hz and textures, not audio.

So the strongest simultaneous gesture is: left stick + right stick + one or both triggers + one bumper.
The face buttons and the d-pad are for when a thumb is free, which in a good model is between chords, not during them.

## Conventions every model shares

These are worth fixing before the models differ, so whichever is chosen inherits them.

- **The screen shows the hand.** A small controller drawing in a corner shows what every button and stick means right now, relabelled as layers change, as the hotkey tips do for the keyboard (`hotkeyTip`).
- **Every target is named in sound, not in symbol.** A pie sector does not say "V", it says "V · G7"; a ring cell says "Em9", not "Dorian 9th".
  Key, degree and color are worked out with the core as the phone does (`ChordKey.chord(in:)`, `chordShape`, `markedChordName`).
- **Pointing is not playing.** A stick leaning into a target lights it and (optionally) shows its notes on the piano; a separate control strikes.
  This is the controller's version of the ring's lit neighbours: aiming is free, so the screen can show where the aim would go before the ear hears it.
- **Neighbours are lit by the core's own distance.** Cells one step from what is sounding are marked (`colorSteps`), as the ring does; the Tonnetz's three flips are marked; the chord–scale tree's next chords are marked.
- **Direction means the same thing everywhere it can.** Up is more notes (a higher stack), down fewer; clockwise or right is brighter (towards Lydian), anticlockwise or left darker (towards Locrian).
  This is the color ring's own geometry, read as stick directions.
- **Rumble is information, never decoration.** It says something the ear might miss: a step crossed, a dissonance's beating, a loop's downbeat.

## Model 1: Twin rings

### Core idea

Each stick is a ring that already exists in the app.
The left stick is a pie of the seven degrees; the right stick is the color ring, with its angle the mode and its radius the stack height, exactly as the ring is drawn (`ColorRing`, `ColorRingPosition`).
The right trigger strikes, and how hard and how far it is pulled is how loud and how bright.
A chord is: lean left (which chord), lean right (which color), pull (play).
All three are simultaneous, so a colored chord is one gesture, and a change of color under a held chord is the right thumb moving.

The degree pie is laid out in the diatonic circle of thirds, I iii V vii° ii IV vi, so neighbouring sectors share two notes (I and iii share E and G in C), and a thumb rolling round the stick is the smoothest chain of chords the key has.
The chain is a cycle (vi back to I shares C and E), so the pie has no seam.
Seven sectors take about 51° each.

### Map

| Control | Does |
|---|---|
| Left stick | Degree pie, circle of thirds, I at the top. Sticky: the last sector chosen stays chosen when the stick returns to centre. |
| L3 (at centre) | Drone: the chord sounding keeps sounding after RT lets go, until the next strike. |
| Right stick angle | The ring's sector (mode), in the Home arrangement: the held degree's own mode at the top, darker anticlockwise, brighter clockwise, the 60° gap at the bottom. |
| Right stick radius | The ring's band: centre is the plain triad, then 7th, 9th, 11th (three outer bands; the 13th is on RB, see "Hard"). |
| R3 | Keep the cell pointed at (`keepsRingColor` latched for this cell); R3 at centre resets (`resetRingColor`). |
| RT | Strike. Crossing 8% sounds the chord, with a level from how fast the trigger travelled (the first 20 ms of pull); depth afterwards is the note's level and brightness, as aftertouch; releasing below 5% ends the chord. |
| LT | The arpeggio, held on as a zone holds it (`EffectsState.holdArpeggio`): off at rest, then a bar, 2, 1, ½ beat as it is pulled, with a rumble tick at each step. |
| LB, RB (tap) | The key a fifth down, a fifth up (`homeKey`), previewed on screen while held, taken on release. |
| LB (held) | Marks layer: the right stick becomes the mark wheel (below). |
| RB (held) | The 13th band and the extended reach: the right stick's outer band is the 13th while it is held. |
| D-pad ← → | Inversion down, up (`Inversion`, as the voicing pad's step). |
| D-pad ↑ ↓ | Octave up, down. |
| A | Strike without the trigger (fixed level), for a player who wants the trigger only for swells. |
| B | Release everything. |
| X | Loop (`QuickLoopState`). |
| Y | Hold, as the Tonnetz's HOLD: the next strike latches. |
| Start | Play and stop. |
| Back | The menu (`SidePanel`), driven by the d-pad and A. |

The mark wheel (LB held): the right stick's circle is divided into the six chord tones, 3 at the top and round clockwise to 13, and each tone's 60° into three petals, ▼ ✕ ▲, 20° each.
A petal pointed at is played while LB is held (`pressToneMark`); R3 keeps it.
Only the marks `toneMarkOptions` allows are drawn, and the ones it would not are dimmed, as the row under the ring dims them.

### Screen

```
+------------------------------------------------------------------------------------+
|  C major  ·  voicing 4/root  ·  arp off                       [hand: LB RB LT RT]  |
|                                                                                    |
|            DEGREE (left stick)                    COLOR (right stick)              |
|                  I                                      Dorian                     |
|               C maj                             Aeol  .--------.  Mixo             |
|        vi  .---------.  iii                   Phryg / 11 11 11 \  Ion              |
|      A min/           \E min                       /  9  9  9  9 \                 |
|           |   [ V ]    |                     Locr |  7  7 (7) 7  7 | Lyd           |
|      IV   |   G maj    |  V                       |      triad     |               |
|     F maj  \  lit: iii /G maj                      \  .  plain  .  /                |
|             '---------'                             '----  gap  --'                 |
|         ii              vii°                                                       |
|        D min           B dim                    pointing: G 7  (Mixolydian 7th)    |
|                                                 one step:  G maj7, G 9, G sus4      |
|                                                                                    |
|   sounding:  G 7   G B D F     level ████████░░  bright ██████░░░░                 |
|   ┌──┬─┬┬─┬──┬──┬─┬┬─┬┬─┬──┬──┬─┬┬─┬──┬──┬─┬┬─┬┬─┬──┐                              |
|   │  │█││ │  │  │ ││█││ │  │  │ ││ │  │  │ ││ ││ │  │   piano, lit                  |
+------------------------------------------------------------------------------------+
```

### Visible random access

Every degree and every cell of the ring is on screen at once, named in the current key.
Because aiming is silent, the screen can afford to show what the aim lands on before it sounds, and the cells one step from the sounding chord are lit, so the player sees which move is the gentle one.
The ring's own visual (the phone's `ColorRingPad`) is reused, larger.

### Range

One gesture (LS + RS + RT): 7 degrees × (1 plain + 7 modes × 3 bands) = 154 chords in the key, each struck from silence.
Under a held chord, one thumb: any color of that degree, or any degree with that color.
Two gestures: a key change (a bumper tap), a voicing change (thumb to the d-pad), the 13th (RB), or one mark (LB + right stick).
Three: a mark on a 13th chord in another key.

### What is hard

- **Radius is the weakest axis.** Three bands plus a centre is near the limit of a 360 stick held by a moving thumb; five would not be reliable, which is why the 13th is on RB.
  Band edges need the same hysteresis as `GamepadStick` (in at 0.5, out at 0.35) scaled per band.
- **The right stick springs to centre, which is the plain triad.** Letting go of the stick under a held chord changes its color back, which is right for "played" and wrong for "kept"; R3 is the latch, and R3 moves the aim, so the commit must read the angle from just before the click.
- **The d-pad needs the left thumb**, which is on the degree stick; voicing is changed between chords, or under a chord held by RT, since the degree is sticky.
  That is acceptable for octave and inversion, which are slow-changing.
- **The mark wheel's 18 petals at 20°** are dense; it relies on the screen drawing the wheel and lighting the petal pointed at, as marking menus do.
  Only marks that are legal are targets, which typically leaves 8 to 12.

### Architecture

- Reuses: `Degree`, `ColorRing.position(height:sector:arrangement:)`, `ColorRingPosition`, `ColorRing.turn`, `colorSteps`, `ToneMarks`, `toneMarkOptions`, `markedChordName`, `Inversion`, `KeyVoicing`, `HeldArpeggio`.
- New pure values (in `Core/Events`, beside `GamepadStick`, since they need `atan2` and the music theory core may not import Foundation):
  - `PieGate`: sectors (count, span, where the first is, a gap), radial bands, and hysteresis, with `select(x:y:from:) -> PieCell?`.
    `GamepadStick.direction` becomes `PieGate.eight`.
  - `DiatonicCycle.thirds: [Degree]` (pure, could live in the music theory core: it is a fact about the key, not the controller).
  - `TriggerStrike`: a reducer over trigger samples (value, time) giving `.strike(level:)`, `.depth(Double)`, `.release`.
  - `GamepadFrame`: every axis and button at one moment.
- The core of the model is one function: `(TwinRingsState, GamepadFrame) -> (TwinRingsState, [GamepadEffect])`, where an effect is a call on the host as data (`.press(.degree(.V))`, `.ringChose(position)`, `.ringLifted`, `.holdVoicing(v)`, `.rumble(Rumble)`), tested by equality.
  `GamepadState` becomes the shell that feeds it frames and performs the effects.
- New on `PerformanceState`: a struck level (the keys' `NoteSound.level` per strike) and aftertouch (a `noteChange` of level and brightness on the keys' held notes, the mechanism the Trautonium already uses).

## Model 2: Petals and depth

### Core idea

Strike with the face buttons, so rhythm is crisp and digital, and use the triggers as a bipolar dial of brightness, the ring's angle split at its middle.
The left stick chooses the degree (as in Model 1); the face button chosen strikes it at one of four stack heights; the triggers bend the mode darker (LT) or brighter (RT) from the degree's own.
This is the ring again, read on different surfaces: band on the buttons, sector on the triggers.
It borrows Steam's daisywheel: a stick picks a petal, the face buttons pick within it, and the petal shows its four choices in the diamond they are pressed in.

### Map

| Control | Does |
|---|---|
| Left stick | Degree pie (circle of thirds), sticky. |
| A / X / Y / B | Strike the chosen degree as triad / 7th / 9th / 11th. Several held: the highest sounds (the most recent press is active, by `PerformanceMode`'s contract). |
| LT depth | Darker by 1, 2, 3 sectors (towards Locrian), each step a detent marked by a rumble tick. |
| RT depth | Brighter by 1, 2, 3 sectors (towards Lydian). Both pulled: the deeper wins. |
| LB (held) | Marks layer: A ▲3 (sus4), B ▼7 (6), X ✕7 (add), Y ▲5 (aug) — the four most used marks from `ColorStepsTests`' census, struck as the chord. |
| RB (held) | Effects layer: A arpeggio up, B arpeggio down, X delay, Y reverb, each switched as its field on the effect strip (`EffectsState.setSlot`). |
| Right stick | The voicing pad: the stick is a `VoicingBend` held while leaned (`holdVoicing(at:)`), along is inversion and across is octave, as the voicing field's pad. |
| R3 | Keep the bend as the voicing (`keepsVoicing` for one change). |
| D-pad ← → | Key a fifth down, up. |
| D-pad ↑ ↓ | The key's scale, through the heptatonic scales (the Key page's choice). |
| L3 | Drone. |
| Start / Back | Play and stop / menu. |

### Screen

```
+------------------------------------------------------------------------------------+
|  E♭ major                     darker ◄ LT ░░░▓  RT ▓░░░ ► brighter                 |
|                                                                                    |
|                       I  E♭                                                        |
|           vi  Cm   .--------.    iii  Gm                                           |
|                   /   [V]    \                  V · B♭ (Mixolydian, own)           |
|          IV A♭   |    B♭      |   V  B♭                  Y                         |
|                   \          /                       B♭ 9                          |
|           ii  Fm   '--------'    vii° D°        X                 B                |
|                                                B♭ 7            B♭ 11               |
|                                                          A                         |
|                                                        B♭ maj                      |
|                                                                                    |
|    LT 1: B♭ Dorian → B♭m 7 …   RT 1: B♭ Ionian → B♭ maj7 …   (preview, by depth)   |
|                                                                                    |
|   sounding: B♭ 7    B♭ D F A♭        piano ┌┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┐                 |
+------------------------------------------------------------------------------------+
```

The diamond on the right always shows the four chords the four buttons would strike, at the trigger depth now; pulling a trigger rewrites the diamond as it goes, so the player reads the change before striking.

### Visible random access

The diamond is the whole of what the right thumb can do, named; the pie is the whole of what the left can.
The triggers' previews show one step either way.
It shows less of the ring at once than Model 1, but what it shows is exactly what is reachable in this hand state, which is the spec read strictly.

### Range

One gesture: 7 degrees × 4 heights × 7 modes (own ± 3) = 196, minus the modes past the ring's ends for degrees near them (Locrian's degree cannot go darker; the trigger stops at the ring's end and the preview says so).
Marks are one more finger (LB), so the joystick's sus4, 6, add9 and aug colors are one gesture too.
Two gestures: key, scale, voicing kept.

### What is hard

- **Trigger detents without detents.** Three steps per trigger depend on rumble ticks and the screen; a player in time will overshoot.
  Making the outer step the "deepest" with a wider zone helps.
- **Bipolar on two triggers** means both fingers are committed to color, and nothing else analog is left for the right hand while it strikes (the right stick is under the striking thumb).
  Expression (level) is gone: the face buttons strike at one level.
- **The 13th** is off the buttons; it could be A+Y, at the cost of a rule to learn.
- Rhythm is the best of all the models: a button is a percussive strike with no travel.

### Architecture

- Reuses: as Model 1; the bipolar triggers are `ColorRing.position(height:sector:arrangement: .home)` with the sector the own mode's plus the depth.
- New pure values: `TriggerSteps` (a value in, a step out, with hysteresis and the tick as an effect), and `MarkFlavor` (a named mark, e.g. `.sus4 = (.third, +1)`) as a table in the music theory core, tested against `toneMarkOptions` so a flavor offered is always legal.
- The face buttons stay a `KeyboardMap`, but the actions they map to become chords at a height (`KeyboardAction.chordAt(StackHeight)`), so Setup's map editor still applies.

## Model 3: The neighbourhood

### Core idea

Stop choosing chords by name at all: the screen is centred on the chord sounding, and around it, at the right stick's eight directions, are the chords one step away.
"One step" is a lens, chosen by the bumpers, and every lens is a distance the core already has:

- **Voice-leading lens (Tonnetz):** the three flips P, L, R, and the three two-flip moves that share one note (PL, PR, LR... drawn as the next ring of triangles), where the stick's directions are the real directions of the triangles' sides on the net (`TonnetzCell.flipped`, `TonnetzNet`).
- **Color lens:** the colors of this degree one `colorSteps` step from what sounds, laid out by the shared convention: up a note added, down a note taken away, right brighter (a note raised), left darker (a note lowered), diagonals the marks.
- **Scale lens (chord–scale tree):** the chords this chord is at home in the scales of (`TreeChord.next`), grouped by the letter their root is above, eight at a time, with the left stick paging through the branches.
- **Diatonic lens:** the six other degrees, placed by the circle of thirds so the two that share two notes are left and right, the fifth up and down.

A **flick** (out and back within ~180 ms) moves there and strikes: the chord becomes the centre and the neighbourhood is redrawn around it.
A **hold** auditions: the neighbour sounds while the stick leans, and letting go comes back to the centre.
So flick is "kept" and hold is "played", told apart by time, with no latch to press.

### Map

| Control | Does |
|---|---|
| Right stick flick | Move to that neighbour and strike it. |
| Right stick hold | Audition that neighbour; release comes back. |
| R3 | Strike the centre again. |
| LB / RB | Previous / next lens. |
| Left stick | The path: ← back along the chords played (undo a move), → forward again, ↑ ↓ page the scale lens's branches. |
| L3 | Bookmark the centre into a palette of eight (drawn along the bottom). |
| LT | Brightness (`setBrightness`), continuous. |
| RT | Level / swell of what sounds, continuous; at rest the chords still sound at the strike level. |
| D-pad | Palette: hold ↑ and flick the right stick to jump to a bookmark. ← → inversion. |
| A | Hold (latch). |
| B | Release. |
| X | Loop. |
| Y | Home: back to the key's tonic chord (the tree's HOME). |
| Start / Back | Play and stop / menu. |

### Screen

```
+------------------------------------------------------------------------------------+
|  lens:  ‹ COLOR ›  TONNETZ   SCALES   DEGREES                 path: C · Am · F · Dm |
|                                                                                    |
|                             + 7th                                                  |
|                             Dm 7                                                   |
|              ▼ 3                                + 9 (add)                          |
|             D sus2                             Dm add9                             |
|                                                                                    |
|   darker      ▼ 5          [  D m  ]           ▲ 3        brighter                 |
|              D dim          ii, Dorian         D maj                                |
|                                                                                    |
|              ✕ 3                                ▲ 5                                |
|              D 5                               Dm♯5                                |
|                             ✕ 5                                                    |
|                           Dm (no 5)                                                |
|                                                                                    |
|   rumble on move: ▁ one note moved   ▃ two   █ a leap                              |
|   palette:  [C] [Am7] [F maj7] [G sus4] [ ] [ ] [ ] [ ]                            |
+------------------------------------------------------------------------------------+
```

### Visible random access

This is the spec at its most literal: the screen shows exactly the eight places one flick away, and nothing else competes for the eye.
It trades breadth for a guarantee: every move offered is one note (or one rule) from where the music is, so consonance is the default and the theory is the layout.
Breadth comes back through the lenses and the palette, each one bumper or one d-pad hold away.

### Range

One gesture: 8 chords, all near.
Two gestures: 32 (four lenses), or any of eight bookmarks.
Far chords are several moves, which is the point and the cost: it is an instrument for walking, not for jumping.
Undo along the path makes exploring cheap.

### What is hard

- **Flick versus hold by time** is learnable (games use it for quick-throw versus aim), but a musician holding a stick to audition and then wanting to commit needs a way that is not "flick again": R3 while held commits, read from the angle before the click.
- **Lens geometry differs.** The Tonnetz's directions come from the net and alternate with the triangle's orientation, so "up" is not always the same move; the other lenses fix their directions by the shared convention.
  The screen must redraw on every move without the player losing where they were: a short animation that slides the old centre to where the stick pointed, as the Tonnetz's net does.
- **Rhythm is soft**: a flick has travel, about 60 to 100 ms from rest to the gate, so the strike is late unless it is read at the gate's crossing, not at the return.

### Architecture

- Reuses: `TonnetzCell`, `TonnetzMove`, `Triad.applying`, `colorSteps`, `ToneMarks`, `TreeChord.next`, `TreeStep`, `ChordScaleTreeState`'s tiers (the path is a tier list), `TonnetzState` as the line that plays the Tonnetz lens.
- New pure values:
  - `Neighbourhood`: for a lens and a centre, eight `(direction, target)` pairs or nil, a pure function per lens (the color lens is new: the colors one step away, placed by what the step does).
  - `StickGesture`: a reducer over stick samples in time, giving `.aim(direction)`, `.flick(direction)`, `.hold(direction)`, `.lift`.
  - `ChordPath`: the chords moved through, with back and forward, as plain data (and the obvious thing for a loop to record).
  - `Rumble` for a move, from the voice-leading distance between the two voicings (`computeVoicing` with voice leading, summed semitones), so the hand feels the size of the step.
- The one state that is new across the app is "the centre", which for the Tonnetz and tree lenses already exists (`TonnetzState`, `ChordScaleTreeState.position`) and for the color and degree lenses is the keys' chord.

## Model 4: Two hands, two voices

### Core idea

Give each hand an instrument, and give each its trigger as pressure.
The left hand plays harmony (degree pie, a few colors), and LT is its swell, like an organ's expression pedal.
The right hand plays a line: the right stick is the solo strip bent into a circle, or the Trautonium's bar, and RT is the pressure the CLAUDE.md says a phone cannot sense ("in place of the pressure a real one is played by").
A trigger is that pressure: the Trautonium as it was meant to be played, on a controller.

It also gives the Dissonance Lab a body: two sticks are two notes, and the rumble is their beating, felt in the hands.

### Map (the duet)

| Control | Does |
|---|---|
| Left stick | Degree pie (circle of thirds), sticky; a sector entered while LT is held is a tied change of chord. |
| LT | Chord level: from silent to full; pulling it in from 0 strikes, letting it go fades (a swell, not a strike). |
| LB / L3 | Chord color: LB cycles plain, 7th, 9th (the ring's bands in the own mode); L3 resets. |
| Right stick | The solo pie: the strip's notes for the chord sounding (`soloNotes`, five to seven of them), clockwise up from the tonic, the outer ring an octave up. |
| RT | The line's pressure: level and brightness; pulling it in strikes the note pointed at, moving the stick with RT held slides to the next petal (the kernel's glide). |
| RB | The Trautonium instead of the solo pie (below). |
| D-pad ↑ ↓ | The line's octave. |
| D-pad ← → | The chord's inversion. |
| A / B / X / Y | Free for the thumb between phrases: A loop, B release, X arp on the chord, Y hold the chord. |

With RB held the right stick's vertical axis is the Trautonium's bar (two octaves from the tonic, `BarRange`), pitch following the stick from where it landed, landing on the nearest note of the key (`Key.note(nearest:)`) and brought back to it after a rest (`TrautoniumState.rest`); RT is the level (`TrautoniumState.level`, from the trigger rather than from across the bar).

### Map (the lab, on its screen)

| Control | Does |
|---|---|
| Left stick, right stick | The two notes: each a pie of the twelve intervals from a fixed lower note, or the lower and the upper note, with fine tuning by radius (cents off equal temperament, for hearing a fifth settle). |
| LT / RT | Each note's level. |
| Rumble, low motor | The spotlighted pair's beat (`CollidingPair.beatRate`, `envelope(at:)`), rendered as a rumble that swells and fades at that rate up to ~15 Hz, and a steady buzz past it (roughness). |
| Rumble, high motor | The summed roughness (the meter), as a level. |
| LB / RB | The level (`LabLevel`) down, up. |
| A | A/B: equal temperament with no enhancement. |

### Screen (the duet)

```
+------------------------------------------------------------------------------------+
|  A minor                                                                           |
|                                                                                    |
|      HARMONY (left)                                  LINE (right)                  |
|            i Am                                       A                            |
|      VI F .-----. III C                         G .-------. C                      |
|          / [ iv ] \                              /  ·  ·   \                       |
|   iv Dm |   Dm     | v Em                     E | ( D )    | D   ← lit: in Dm      |
|          \        /                              \  ·  ·   /                       |
|    ii° B° '------' VII G                        C  '-------'  E                    |
|                                                   (outer ring: octave up)          |
|    swell LT  ▓▓▓▓▓▓░░░░                   pressure RT ▓▓▓▓▓▓▓▓░░  bright ▓▓▓▓▓░    |
|                                                                                    |
|   chord: Dm   D F A                       line: D 5  (gliding → F 5)               |
|   ┌┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┬┐  piano: chord blue, line orange            |
+------------------------------------------------------------------------------------+
```

### Visible random access

Both instruments' whole ranges are drawn, and the line's petals are the notes that fit the chord now, so the "no wrong notes" of the solo strip is visible as the shape of the pie changing with the chord.
The lab shows its ladders and meter as on the desk, and adds the rumble's meaning beside it ("beat 3.2 Hz — felt").

### Range

One gesture per hand, at once: 7 chords × 3 colors under 5 to 7 notes × 2 octaves.
It reaches fewer chords than Models 1 and 2 and far more expression: two continuous levels, a slide, and a bar that is in tune however roughly it is struck.

### What is hard

- **Two continuous voices at once is a skill**, like playing a theremin with a drone; most players will hold the chord with LT and play the line.
- **The solo pie's petals change with the chord**, so a note's place moves under the thumb when the left hand changes chord; `soloNotes` ascending from the tonic keeps the tonic fixed at the top, which limits the drift, but petal count changes (5 versus 7) move the others.
  A fixed twelve-petal layout with the unfit notes dimmed and unreachable is the alternative.
- **The Trautonium is not sent over MIDI** and neither is the lab, as now.
- **Rumble latency** blurs fast beats; above ~15 Hz the motor can only say "rough", which is also where the ear stops hearing beats and starts hearing roughness, so the limit matches the perception.

### Architecture

- Reuses: `soloIntervals`, `soloNotes`, `SoloState` (its `NotePlayer`), `TrautoniumState`, `BarRange`, `Key.note(nearest:)`, `IntervalAnalyzer`, `CollidingPair`, `DissonanceLabState.play(_:above:level:)` (the way in the CLAUDE.md already reserves for "whatever drives it later").
- New pure values: `SoloPie` (the strip's notes laid out by angle, and which petal a stick points at, with hysteresis, the solo strip's `SoloStripCells` in polar form); `Rumble.ofBeat(rate:roughness:)`, giving the two motors' levels over time as data that the shell plays through `GCController.haptics`.
- New on the bars: a level that comes from outside (`TrautoniumState` reads level from across the bar today); the trigger supplies it instead.
- `SoloState` would need a level and a slide, which the Trautonium's bars already have through `NoteSound.bend` and `level`.

## Model 5: The couch arranger

### Core idea

The other four models play; this one makes the timeline (`Timeline`, `SequencerState`) a thing a controller edits as well as a mouse does.
A cursor moves over the step grid with the d-pad, and the same pies that play (Model 1's) set the chord of the steps under it.
The point of including it: a controller at a laptop is as likely to be used to build a progression as to perform one, and the sequencer is where "visible random access" has the most to show.

### Map

| Control | Does |
|---|---|
| D-pad | The cursor over the steps (cardinals only), by `StepGridShape`'s rows. |
| A | Select the step; hold A and move the cursor to select a run. |
| Left stick + right stick | Set the selected notes' degree and color (Model 1's pies), heard as they are aimed (audition). |
| RT | Commit the aimed chord to the selection; its depth while committing is the notes' length (to the next step, a half, a whole). |
| X | Join / Split (`SequencerState.joinEdit`). |
| Y | Play from the cursor. |
| B | Undo. |
| LB / RB | The layer before / after (`SequencerState`'s layer on screen). |
| LT | Scrub: the timeline played under the cursor at the trigger's speed. |
| Start / Back | Play and stop / menu. |

### Screen

```
+------------------------------------------------------------------------------------+
|  layer 2 of 4  ·  4/4  ·  92 bpm                                    ▶ Y from here   |
|  ┌────┬────┬────┬────┐ ┌────┬────┬────┬────┐ ┌────┬────┬────┬────┐                 |
|  │ C  │ ·  │ ·  │ ·  │ │ Am7│ ·  │[F ]│[F ]│ │ G7 │ ·  │ ·  │ ·  │   bar 1..3      |
|  └────┴────┴────┴────┘ └────┴────┴────┴────┘ └────┴────┴────┴────┘                 |
|                                     ^ cursor, 2 selected                           |
|      degree pie (LS)                     color ring (RS)          aimed: F maj9    |
|        [compact pies as Model 1, with the selection's current chord ◆ marked]       |
+------------------------------------------------------------------------------------+
```

### Visible random access

The grid is all on screen, and the pies show what a commit would write; the ◆ mark the step editor uses for a note's own setting carries over.

### Range

Any chord of the key into any selection in one gesture (aim + RT).
Moving the cursor is the slow part: a long timeline is many d-pad presses, so the left stick (when not aiming) could fling the cursor by bars.

### What is hard

- Both thumbs aim the chord, so the cursor cannot move while aiming; aim and commit, then move.
- It doubles every editor control; it should only exist if Model 1 is chosen, since it is Model 1 plus a cursor.

### Architecture

- Reuses `TimelineEdits`, `StepGridShape`, `TimelineNote.steps`, `SequencerState.joinEdit`, and Model 1's reducer for the aiming.
- New pure value: `GridCursor` (a step, a selection anchor, moved by `StepGridShape`'s rows), whose edits are `TimelineEdits`.

## Comparison

| | 1 Twin rings | 2 Petals and depth | 3 Neighbourhood | 4 Two voices | 5 Couch arranger |
|---|---|---|---|---|---|
| Chords in one gesture | 154 | ~196 | 8 (×4 lenses) | 21 | as Model 1 |
| Shows on screen | the whole key and ring | what this hand state reaches | the eight next places | both instruments | the timeline and the pies |
| Strike | analog (RT), with level | digital (buttons), crisp | flick, soft | analog swell and pressure | commit, not played |
| Expression | level and brightness on RT, arp on LT | none in the strike | swell and brightness | the most: two pressures, slides | none |
| Theory carried by layout | circle of thirds, the ring | the ring, read as triggers | voice leading, color steps, scales | solo scale, key snapping, beating | as Model 1 |
| Learnability | medium (two pies at once) | easiest to start | easy to start, hard to navigate far | hard to play both | follows Model 1 |
| New core | `PieGate`, `TriggerStrike`, reducer | `TriggerSteps`, `MarkFlavor` | `Neighbourhood`, `StickGesture`, `ChordPath` | `SoloPie`, `Rumble.ofBeat` | `GridCursor` |
| Main risk | radius resolution | trigger steps without detents | flick timing | splitting attention | a second editor to keep |

## Recommendation

Prototype **Model 1, Twin rings**, with Model 3's flick-versus-hold as the way color is kept or played, and Model 4's beating rumble on the Dissonance Lab's screen as a separate small experiment.

- It is the one model that maps one-to-one onto structures the app already has and has already tested: the ring's sectors and bands are a stick's angle and radius, the degree pie is the keys, and the trigger strike is the only genuinely new behaviour.
  That makes it cheap to judge whether the controller is musical at all before investing in a new way of thinking about chords.
- It reaches the most of the key in one simultaneous gesture, with real expression on the trigger, and it shows all of it.
- Flick versus hold on the right stick removes R3, the model's worst control: a flick into a cell keeps it, a hold plays it.
  That makes the kept/played duality something the hand does, not a pin.
- The beating rumble is independent, small (a `Rumble.ofBeat` and a shell that plays it), and is the most surprising thing a controller adds that no other input can; it is worth knowing early whether it reads.

What to build first, in order, each testable on its own:

1. `GamepadFrame` and `PieGate` (with `GamepadStick` rewritten as `PieGate.eight` and its tests kept), and the triggers read as values in `GamepadInput`.
2. The Twin-rings reducer, `(state, frame) -> (state, [GamepadEffect])`, tested by equality over scripted frames: a lean, a pull, a release.
3. The shell in `GamepadState`, performing the effects through `PerformanceState`'s calls; a struck level and aftertouch on the keys' player.
4. The desk screen for it (a `DeskPane`, beside the Tonnetz and the controller pane, or the window's whole width when the controller is the input).
5. `Rumble` effects for band and step crossings, then the lab's beating.

Logging: `gamepad_struck(level:)`, `gamepad_pie_chose(stick:cell:)`, `gamepad_lens_switched` if Model 3 comes in, per the project's rule that a feature's load-bearing events are `LogEvent` cases.

## Patterns that could flow back to the phone

- **Aim, then strike.** On the controller, choosing a chord and sounding it are different fingers, so the screen shows the chosen chord before it sounds.
  On the phone the two are one touch; a "pre-select" (a chord key that only lights, and a strike pad that sounds it) would give the phone the same look-ahead and a rhythm surface that is not also a chooser.
- **The circle of thirds as an order for degrees.** The chord keys are in scale order; a ring of degrees in thirds puts each degree beside the two it shares two notes with, which is a better circle layout than the current one, whose neighbours share one or none.
- **Flick keeps, hold plays.** The ring's pin could go: a tap on a cell keeps it, a touch held and slid plays it and lets go back.
  This is a gesture the phone already reads (the key strip's swipe fields distinguish tap from rest).
- **Radius as stack height** already is the ring; the controller confirms it as the right axis, and suggests drawing the ring larger in its bands near the centre, where the hand is most precise.
- **Neighbourhood lenses.** A "what is one step from here" view (color, voice leading, scale) is not specific to a controller; on the phone it would be a mode of the ring or the Tonnetz that relabels its neighbours.
- **Haptic beating.** The phone's Taptic Engine can play the Dissonance Lab's beat (Core Haptics, a continuous event with an intensity curve at the beat rate), the same `Rumble.ofBeat` data played by a different shell.
- **Legends that name the sound.** The controller screen names every target by what it would sound in this key ("V · G7"); the phone's chord colors mostly name the rule ("Dom 7"), which is less than the controller would show.

## Open questions

- **Which controller, really.** An Xbox 360 controller has no native support on macOS: the GameController framework sees Xbox One and Series controllers (and DualShock and DualSense), and a 360 needs a third-party driver.
  The desk reads a wired 360 itself, straight from USB, since nothing else claims it (`Xbox360USB`), and every other controller through GameController, with rumble through `GCController.haptics`; the wireless 360's receiver is not read.
- **Does the trigger strike feel early or late?** A trigger has travel; reading the strike at 8% and the level from the first 20 ms needs to be tried against a button's strike with a metronome.
- **How many radial bands does a thumb hold?** Three plus the centre is the guess; the prototype should log band changes the player did not mean (a band entered and left within 100 ms) to measure it.
- **Is the degree pie fixed or turned?** The ring has Fixed and Home; the degree pie has the same choice (I always at the top, or the chord sounding at the top so its two smooth neighbours are always left and right).
- **What does a loop record of a trigger swell?** Aftertouch is a `SoundChange` on a held note, which a loop already records for a slide; a swell from silence (Model 4's LT) is a note that starts quiet, which needs nothing new, but should be checked.
- **Does the controller screen replace the desk layout or sit in it?** The `DeskLayout` is to be thought through again (CLAUDE.md); a controller-first screen is one input for that rethink, not a fourth layout to keep.
- **Menus.** Back opens the side panel, driven by the d-pad; whether every setting there is reachable by d-pad and A (focus order through SwiftUI's focus system on Catalyst) is unverified.
- **Accessibility of rumble as information.** If rumble carries meaning (steps, beats), the screen must carry it too, for a controller with no motors and a player who turns them off.
