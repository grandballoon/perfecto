# Coloration that depends on the chord

A design exploration, not a decision.
It asks how much simpler the phone's play screen can be if the chord colors stop showing every color for every chord, and instead show what is near the chord being played.
Nothing here is built; `docs/color-ring.md` is what is built.

## The question

Today the color ring shows all of its 35 cells (5 stack heights × 7 modes of the major scale) and its 18 tone-mark buttons for every chord, all the time.
That follows the guiding rule of the spec: as much of what is relevant as can be, visible and reachable at random, in one touch.
The cost is room and reading: upright, the ring and its marks take 330 points under the keys (`SurfaceShape.ring.portraitHeight`), and a player has about 55 targets to read while they play.

The question is what the screen can become if that rule is dropped for coloration alone.
The surface need not show everything.
It should instead make a wide range of colors that are a step from the chord, and that sound well in the key and on the degree, easy to reach.

That splits into two problems, which this document keeps apart:

1. **After the press (live).** A chord key is held, so its degree, key and color are known.
   The surface can be small and specific: it can show only this chord's neighbours, named, and reshape itself for each chord.
2. **Before the press (inert).** No chord is held.
   The surface must still mean something, because a player will often put the color finger down at the same moment as the chord finger, or just before it.
   What it shows and means then has to be independent of the chord, or resolve against whatever chord arrives.

The two must feel like one surface: a finger that lands on the inert surface and is then joined by a chord should not find itself on a different thing than a finger that lands after the chord.

## What there is to build on

- `colorSteps(a, b)` counts steps between two pitch-class sets above the root: a note added, a note taken away, or a note moved a semitone (a whole tone counts 2).
- `ChordColor` is already partly relative to the degree: `.grid(height, nil)` and `.marked(height, nil, marks)` stack through the degree's own mode (`ChordGrid.ownMode`), so the same color is a different chord on each degree and follows the key.
- `ColorRingPosition(height:mode:)` with a nil mode is that relative color on the ring, and the home arrangement turns the ring so the own mode is at the top.
- `ToneMarks` express every single-step move of a stack tone, and every mark is one step (`ColorStepsTests.everyMarkIsOneStep`).
- `chordShape(key:spec:)` turns any color into intervals and a name, so any surface that yields a `ChordColor` is named, sounded, looped and announced by what already exists.
- The joystick's default mode (`JoystickMap`) is already, informally, a chord-dependent near-step surface: eight fixed directions whose shapes depend on the degree's `TriadBase` (flip the 3rd, add the ♭7, add the 7th, add 9, sus4, 6/sus2, lower the 3rd, raise the 5th).
  It is a hand-made table for three triad qualities; what follows is mostly a way of computing that idea properly, from any color, in any key.
- `PerformanceState.color(for:in:)` resolves the color at the moment a chord starts, against the degree that plays, and `mode.onColorChange` reaches a held chord when the color changes.
  So a surface whose meaning is relative needs no new plumbing to be resolved late.
- `ChordKeySlide` and the key zones already read where on a key a finger is, which matters for design E.
- The Acoustics target (`IntervalAnalyzer.roughness`) measures roughness by Plomp and Levelt's curve, which matters for ranking.

## Principles: what "near-step consonant" means

### The neighbourhood

For a sounding color `c` on degree `d` in key `k`, let `I(c)` be its intervals above the root (`chordShape(...).intervals`, reduced to pitch classes).
The **one-step neighbourhood** is every pitch-class set `x` with `colorSteps(I(c), x) == 1`, the root kept.
It is made of three kinds of edit, which is the vocabulary every design below shares:

- **Add**: one pitch class not in `I(c)`.
- **Take away**: one tone other than the root.
- **Move**: one tone other than the root, a semitone up (**raise**) or down (**lower**), onto a pitch class not already sounding.

For a triad that is 9 adds, 2 removals and about 4 moves: 15 sets.
For a seventh chord it is 8 adds, 3 removals and about 6 moves.

### Fit: three tiers, decided by Ints alone

Not all neighbours are equal, and the ranking should be explainable in the music theory core's own terms (pure Swift, no `exp`).

1. **In key, not an avoid tone.** Every pitch class is in the degree's own scale (the key's scale read from the degree's root), and no added or moved tone is a semitone above a chord tone (the minor ninth that jazz theory calls an avoid note: the 4 over a major 3rd, the ♭6 over a 5th, the ♭2 over the root).
2. **In key, but an avoid tone.** In the scale, but a minor ninth over a chord tone: Cadd11 in C major, Em(♭9).
3. **Borrowed.** One pitch class outside the scale: C minor on I (the parallel minor), D major on ii (the secondary dominant's triad), C aug.

A tier-3 neighbour is not wrong; it is where the color of a chord progression comes from.
It should be offered, but marked, and after the in-key ones.

### How many there are

The counts are small and steady, which is what makes a chord-dependent surface possible.
For a diatonic triad in a mode of the major scale, the in-key one-step neighbours (tiers 1 and 2) are always 4 adds, 2 removals and 1 or 2 moves: 7 or 8 colors.
For the 21 modes of all three families it is 6 to 8.
In C major (a `*` is borrowed):

| Degree | Raise | Lower | Add, in key |
|---|---|---|---|
| I | 3→4 (sus4), 5→♯5* | 3→♭3*, 5→♭5* | 2, 4, 6, 7 |
| ii | ♭3→3* (II, the V of V), 5→♯5* | ♭3→2 (sus2), 5→♭5* | 2, 4, 6, ♭7 |
| iii | ♭3→3*, 5→♭6 (C/E) | ♭3→2*, 5→♭5* | ♭2, 4, ♭6, ♭7 |
| IV | 3→4*, 5→♯5* | 3→♭3*, 5→♭5 | 2, ♯4, 6, 7 |
| V | 3→4 (sus4), 5→♯5* | 3→♭3*, 5→♭5* | 2, 4, 6, ♭7 |
| vi | ♭3→3*, 5→♭6 (F/A) | ♭3→2 (sus2), 5→♭5* | 2, 4, ♭6, ♭7 |
| vii° | ♭3→3*, ♭5→5* | ♭3→2*, ♭5→4 | ♭2, 4, ♭6, ♭7 |

Two things stand out.
Some degrees have no in-key raise (ii, vii°) or no in-key lower (I, V), so a surface whose places are kinds of edit must sometimes fill a place with a borrowed color, and should say so.
And a move of the 5th to the ♭6 on a minor triad is the Tonnetz's L move: Am becomes F/A, so a step can land on another degree's chord.

### Ranking within a tier

Within a tier, an order is still needed, because a small surface shows the first few.
A fixed musical order serves better than a measured one:

- For adds, the next tone of the degree's own stack first (the 7th, then the 9th, the 13th, the 11th), then the others.
- For moves, the 3rd before the 5th.
- For removals, the 5th before the 3rd (taking the 3rd away leaves a bare fifth).

Roughness was tried as the ranking and is not reliable enough to be the first key.
Summing `IntervalAnalyzer.roughness` over six harmonics of each note, on I in C major, ranks add ♭13 above add maj7, and the order of adds swaps when the 9th is voiced an octave higher.
Roughness depends on the voicing, and the ranking must not change as the inversion does.
It is still useful as a check: a test in the Acoustics target can hold the fixed order to agree, mostly, with roughness on a canonical voicing, and it can break ties between borrowed neighbours.

### Relative versus absolute meaning

A color can be stated two ways:

- **Absolute**: a shape, the same on every degree (maj7, sus4, m7♭5).
  The fixed ring and the joystick's legend are this.
- **Relative**: an edit from the degree's own chord ("its next stack tone", "lower its 3rd", "its brightest in-key raise").
  The home ring's nil-mode cells are this, for height and mode.

Only relative meanings are near-step on every degree: maj7 is one step from I and two from ii (and out of key).
So the inert state, which cannot know the degree, should be built of relative meanings, and the live state should name what they resolve to.

### The rule that joins the two states

**Places are relative; labels are absolute.**
Where a target is on the surface is decided by the kind of edit and its rank, which does not depend on the chord.
What is written on it, and whether it is lit, borrowed or absent, is decided by the chord.
So a surface never moves a target out from under a resting finger when a chord lands or changes; it only relabels it.

## The time-relations

The surface has four moments to get right, whatever its shape.

```
 color finger:      ───────[down]══════════════════════[up]────
 chord finger:  ─────────────[down]═══════[up][down]═════════[up]──
                       ^      ^                 ^          ^
                       |      |                 |          |
                    inert   resolves         re-resolves  lifts
                   (no sound) on landing     on the new    (played: plain;
                                              chord          kept: stays)
```

- **Inert, nothing sounding.**
  The finger rests on a relative meaning.
  Nothing is heard.
  The surface may show what the meaning is, in words that need no chord ("+ tone", "lower", "sus").
- **The chord lands.**
  Its first sound is already colored, since `color(for:)` is asked when the chord starts.
  There must be no flash of the plain chord, so the surface's state has to be in `PerformanceState` before the press, not only in the view.
- **The chord changes while the color finger is down.**
  The relative meaning is resolved again on the new degree, as the grid's own row is today.
  The alternative, keeping the resolved shape (maj7 carried from I to ii), is the absolute meaning, and is what the kept pin can offer.
- **The color finger lifts.**
  Played: back to the plain chord.
  Kept: the color stays.

### The keep pin in this world

`keepsRingColor` has a sharper meaning once colors are edits.

- **Played** (pin off) is the natural default for a surface meant to be pressed with the chord: the color is a gesture, like a guitarist's fretting hand.
- **Kept** (pin on) can keep one of two things, and a design has to choose: the **edit** (every chord gets its own next stack tone: "everything as sevenths"), or the **shape** (every chord is a maj7).
  The edit is the home ring's behaviour and the more musical default; the shape is the fixed ring's.
- Kept also opens **walking**: each tap is a step from what is kept, so a few taps reach any color, one near-step at a time.
  This is what makes a small surface reach far.

## Six designs

Each is shown upright, under the chord keys, in the place the chord colors have now.

### A. The step compass

Eight places around a centre, by kind of edit and rank, the same in both states.
Up adds, down takes away, right raises, left lowers; the near ring is the first-ranked of each kind, a drag further out the second.

Inert (no chord held): the kinds are named, the centre is the plain chord.

```
                 ┌───────┐
                 │ + + 2 │            far: second add
                 │ +  1  │            near: first add
     ┌─────┬─────┼───────┼─────┬─────┐
     │ ◀◀2 │ ◀ 1 │   ●   │ ▶ 1 │ ▶▶2 │
     │lower│lower│ plain │raise│raise│
     └─────┴─────┼───────┼─────┴─────┘
                 │ − 1   │            near: first take-away
                 │ − − 2 │            far: second
                 └───────┘
```

Live (V held in C major, G major sounding):

```
                 ┌───────┐
                 │ add9  │
                 │  G7   │
     ┌─────┬─────┼───────┼─────┬─────┐
     │G(♭5)│ Gm* │   G   │Gsus4│Gaug*│
     └─────┴─────┼───────┼─────┴─────┘
                 │ G(no5)│            near: the 5th taken away
                 │ G5    │            far: the 3rd taken away
                 └───────┘
```

- **Concurrently:** the color thumb comes down on "+1" with the chord finger; the chord starts as its own next stack tone (G7 on V, Cmaj7 on I, Dm7 on ii).
  A player learns "up is richer" once and it is true on every degree.
- **Chord change:** the thumb stays on "+1"; the label beneath it turns from G7 to Cmaj7 as the chord moves to I.
- **Reach:** 9 colors per chord in one gesture, all one step; with the pin kept, a walk of taps reaches every color the ring has, since touching cells of the ring are one step apart (54 of its 58 pairs, `ColorStepsTests`).
- **Costs:** a tiny surface (9 targets; it fits the joystick bar's 88 points).
  The far colors of the ring (13♯11, the Lydian 13th) take three or four taps.
  Borrowed fills (Gm* on V's lower) need a visible mark, or the compass sounds wrong to a player who expects "lower" to stay in key; an alternative is to leave a place empty where the kind has no in-key edit, at the price of the rule "a place always plays something".
- **Note:** this is the joystick's default mode computed rather than written down: its "Dom 7 / Flip 3rd / Sus 4 / Aug" are absolute shapes per triad quality, where the compass's places are kinds of edit from whatever is sounding, so it also works from a seventh chord, in harmonic minor and on the octave layout's borrowed roots.

### B. The constellation

The sounding color is a node in the middle and its ranked neighbours are drawn around it, as many as fit (all 7 or 8 in-key ones, and the borrowed ones dimmer and further out).
Sliding onto a neighbour plays it; resting on it for a moment (or lifting, if kept) makes it the new centre, and its own neighbours bloom around it.
It is a walk over the graph whose edges `colorSteps` counts, with the map redrawn around where the walk is.

Inert: the constellation of the tonic's plain chord, greyed, or an empty frame of slots by kind (as A's).

```
              · add6 ·      · add9 ·
                    \        /
         · Csus4 ── [  C  ] ── Cmaj7 ·
                    /   |    \
              · C5 ·  C(no5)  · Cadd11 ·(avoid)
                        .
              ° Cm*          ° Caug*       ° outside the key
```

Live, after walking to Cmaj7 (it is the centre now):

```
               · Cmaj9 ·    · Cmaj7(13) ·
                     \        /
        · C6 ·  ── [ Cmaj7 ] ── Cmaj7sus4 ·
                     /   |   \
              · C ·    Em/C   · Cmaj7(♯11)
```

- **Concurrently:** weak.
  Before a chord the positions of the neighbours are not known, so either the inert state copies A's slots (and the constellation is A with more slots) or concurrency is given up.
- **Chord change:** the walk's place is kept as a path of edits and re-resolved on the new degree, or the walk starts again from the plain chord.
  Either way the drawing jumps, and a finger resting on it may be over a different thing.
- **Reach:** the widest of any design: everything on the ring, and more (any pitch-class set a step from a nameable one), because the walk is unbounded.
- **Costs:** a moving map is hard to play blind and cannot be learnt by the hand, only read by the eye.
  Re-centring under the finger is disorienting; re-centring on lift or on a dwell is the fix, and needs a prototype.
  It is the best teaching tool of the six and the worst instrument.

### C. Petals from the key

There is no color surface at all while no key is held.
A chord key held for a moment grows petals around itself, one per ranked neighbour, over the keys beside it; a second finger (or the same finger sliding out of the key) on a petal plays it.

Inert: the keys alone, using all the room the chord colors had.

```
   ┌──────┬──────┬──────┬──────┐
   │  I   │  ii  │ iii  │  IV  │
   ├──────┼──────┼──────┼──────┤
   │  V   │  vi  │ vii° │      │
   └──────┴──────┴──────┴──────┘
```

Live (V held; petals over its neighbours):

```
   ┌──────┬──────┬──────┬──────┐
   │  I  (G7)  (add9)  │  IV  │
   ├───(Gsus4)┐(G6)┬───┼──────┤
   │  [ V  ] │  vi  │ vii° │   │
   └──(Gm*)─(G5)───┴──────┴────┘
```

- **Concurrently:** impossible by design; the petals do not exist until a key is down.
  The finger that holds the key can slide out into a petal, so it is a one-finger gesture, which no other design is.
- **Chord change:** the petals move to the new key.
  A second finger on a petal of the old key is lifted, or keeps its edit and re-resolves; neither is obvious.
- **Reach:** 6 to 8 colors per chord, one step only, unless petals are walked.
- **Costs:** it conflicts with what the keys already do.
  A finger sliding from key to key changes chord (`KeyTouches`), and the petals lie over those keys, so sliding out to a petal and sliding to a neighbour key are the same motion; a dwell before petals grow is needed, and that makes it slow.
  The finger covers the key the petals grow from.
  It frees the most room of any design.

### D. The tension strip

One strip, ordered from the plainest color to the most tense: removals on the left, then the plain chord, then the in-key adds and moves, then the borrowed ones at the far right.
A place on the strip means a rank, "how much color", not a particular tone.

Inert: the strip as a scale of amount, with no names.

```
  ┌────┬────┬────╥────┬────┬────┬────┬────┬────┬────┬────┐
  │ −2 │ −1 │ ●  ║ +1 │ +2 │ +3 │ +4 │ +5 │ +6 │ ·7 │ ·8 │
  └────┴────┴────╨────┴────┴────┴────┴────┴────┴────┴────┘
   barer    plain   richer, in key ────────▶   borrowed ▶
```

Live (I in C major):

```
  ┌────┬────┬────╥─────┬────┬────┬────┬─────┬─────┬────┬────┐
  │ C5 │Cno5│ C  ║Cmaj7│add9│ C6 │sus4│add11│  —  │Cm* │Caug*│
  └────┴────┴────╨─────┴────┴────┴────┴─────┴─────┴────┴────┘
```

- **Concurrently:** good. "Two cells right of the plain chord" is a meaning that needs no chord, and a finger sliding along it is a crescendo of color that works the same on every degree.
- **Chord change:** the rank under the finger re-resolves: the finger keeps "a little richer" as the chords change, which is what a player sliding it means.
- **Reach:** about 12 colors in one gesture, all one step; it is a single axis, so walking from a kept color extends it.
- **Costs:** a rank is predictable in amount but not in which tone: "+2" is add9 on I and add 4 on iii, and a player who wants the sus4 has to look.
  It fits in one row (40 to 50 points), and can lie along the keys' side when the phone is on its side.
  It is the design that most resembles the solo strip, and could share its placement in Setup (`SoloPlacement`).

### E. The strike map on the key

The color is where the key is struck, and how the finger slides on it.
Up a key is taller (the triad at the bottom, then the 7th, the 9th, the 13th: the stack heights through the degree's own mode); across a key is darker to brighter (the own mode in the middle, one sector of the ring to either side).
It is the home ring, folded into every chord key.

Inert: the keys, each faintly banded.

```
   ┌──────────┬──────────┬──────────┐
   │ ·  9  ·  │ ·  9  ·  │ ·  9  ·  │
   │ ·  7  ·  │ ·  7  ·  │ ·  7  ·  │
   │ ·  I  ·  │ ·  ii ·  │ · iii ·  │
   │ dk    br │ dk    br │ dk    br │
   └──────────┴──────────┴──────────┘
```

Live (ii held, the finger has slid up and to the right):

```
   ┌─────────────────────┐
   │ Dm9    Dm9    D9    │
   │ Dm7    Dm7   [D7]   │ ← the finger: a 7th, one mode brighter
   │ Dm     Dm     D     │   (Dorian is ii's own; Mixolydian raises its 3rd)
   │ Aeo    Dor    Mix   │   labels on the held key only
   └─────────────────────┘
```

- **Concurrently:** solved trivially, since it is the same finger: the chord and its color land together, always.
- **Chord change:** each key carries its own map, so there is nothing to carry over.
- **Reach:** 5 heights × 3 brightnesses = 15 per key, which on the ring's own counts covers its most played cells.
  Marks are not reachable, so sus, add9 and 6 need another place (a small row of the most-ranked marks, or design A beside it).
- **Costs:** it takes the slide, which today plays the inversion, the brightness, the arpeggio's cycle, the vocoder's amount and the key zones; color by place would have to be one more of those uses, chosen in Setup, and could not be combined with the zones.
  It needs a second reading (across the key) in `ChordKeyTouches`.
  Keys must be tall enough to be struck at five heights, which upright they are not with the solo strip or the key strip on screen.
  It frees the whole color area.

### F. The home lens (the conservative one)

The ring as it is, but in its home arrangement, cut to the 3 × 3 cells around the own mode's triad (triad, 7th, 9th × one sector darker, own, one brighter), with the tone marks reduced to the one or two in-key moves of the chord being held.
It is the filtered ring the question warns against, and is here as the baseline the others are measured by.

Inert:

```
   ┌────────┬────────┬────────┐
   │ dark 9 │  9     │ brt 9  │
   ├────────┼────────┼────────┤
   │ dark 7 │  7     │ brt 7  │
   ├────────┼────────┼────────┤
   │ dark   │ plain  │ bright │      ▲ mark   ▼ mark
   └────────┴────────┴────────┘
```

Live (I in C major):

```
   ┌────────┬────────┬─────────┐
   │ C9     │ Cmaj9  │Cmaj9 =  │      ▲ sus4   ▼ 6
   ├────────┼────────┼─────────┤
   │ C7     │ Cmaj7  │Cmaj7 =  │
   ├────────┼────────┼─────────┤
   │ C =    │   C    │ C =     │      (= the same notes as the plain chord)
   └────────┴────────┴─────────┘
```

- **Concurrently:** good, since the home ring's cells are already relative.
- **Reach:** 9 cells and 2 marks: 11 targets, about 20 colors with the marks.
- **Costs:** half of its cells sound the same as their neighbours on short stacks (a triad is the same in Ionian, Mixolydian and Lydian), which is the ring's mode axis showing where it says least.
  That is the argument for edits over modes as the inert vocabulary.

## The inert state, on its own

What can a surface mean before it knows the chord, and still be worth pressing?
Candidates, from most chord-independent to least:

1. **A kind of edit.** Add, take away, raise, lower.
   Always defined, always one step.
   On some degrees a kind has no in-key edit, so it must fall to a borrowed one or be silent.
2. **An amount.** The k-th ranked neighbour (design D).
   Always defined, predictable in amount, not in tone.
3. **A stack height.** "As a seventh", "as a ninth", through the degree's own mode.
   Always defined and always in key, but only adds, and one height is several steps from the triad (a 13th is four).
4. **A brightness offset.** One mode brighter or darker than the degree's own.
   Defined, but often silent on short stacks; it would have to skip to the next mode whose notes differ, which makes it an edit (kind 1) in disguise.
5. **A function.** "Make it dominant", "borrow from the parallel minor", "suspend it".
   Chord-independent and meaningful to a musician, but often more than one step (a ii made dominant is a raise and an add), so it is outside the near-step brief.
   It is worth a later look as a second layer.
6. **An absolute shape.** maj7, sus4, m7♭5.
   Chord-independent in sound but not near-step: on the wrong degree it is far and out of key.
   It is what the kept-shape pin offers, not what the inert surface should be built of.

So the inert surface should be built of kinds (1), with amount (2) as its second dimension: that is exactly design A's compass, where direction is kind and distance is rank, and design D is its one-dimensional cousin.
Height (3) is the other good candidate, and is what design E and the home ring already use.

What the inert surface should show: the kinds, in words that need no chord.
What it should not do: show the tonic's labels as a stand-in (as `ColorRingSurface` does today with `state.activeDegree ?? .I`), since a player then reads "Cmaj7" on a place that will play G7.

## How it maps onto the code

All of it is a functional core under the existing types, with a thin shell.

### The core (pure, in `MusicTheoryCore`)

- `ColorEdit`: `.add(Int)`, `.remove(ChordTone or Int)`, `.move(from: Int, to: Int)`, over intervals above the root.
- `ColorFit`: `.inKey`, `.avoid`, `.borrowed`, decided from the degree's scale (`HeptatonicMode(key:degree:)` or `ChordGrid.ownMode`) and the minor-ninth rule.
- `colorNeighbours(of color: ChordColor, key: Key, degree: Degree) -> [ColorNeighbour]`: every one-step neighbour, each with its edit, its fit, its resulting color and its name, ranked by tier and then by the fixed order above.
  This is the one function every design reads.
- `ChordColor.expressing(_ intervals: [Int], key:degree:) -> ChordColor?`: the inverse of `chordShape`, the `.grid` or `.marked` color with the fewest marks that sounds a pitch-class set, searched over the ring's 35 cells.
  It is what lets every design end in an ordinary `ChordColor`, so naming, ChordLink, loops and the sequencer need nothing new.
  A test should hold that every one-step neighbour of every ring cell on every degree is expressible, or list the ones that are not (the doc's guess is that nearly all are, since every mark is one step).
- `ColorPlace` (A and D): a kind and a rank, and `resolve(_ place: ColorPlace, from: ChordColor, key:degree:) -> ColorNeighbour?`, which picks from `colorNeighbours`.
  Nil is a place with nothing to play on this degree.
- For walking: `ColorPath`, a list of places, resolved one after another from the plain chord, so a kept walk can follow the degree (kept edit) or be frozen to its last `ChordColor` (kept shape).
- Tests by plain equality: the table above for C major, the counts (6 to 8 in-key neighbours on every degree of all 21 modes), and that every place resolves to a color one step from where it started.

Roughness cannot live in the core (it needs `exp`).
The fixed order is the ranking; a test in `Perfecto/Tests` that imports both the core and Acoustics can check it against roughness on a canonical voicing, and fail loudly if a change to the order makes it disagree badly.

### The shell

- `PerformanceState` gains one more case in `color(for:in:)`, resolving the held place (or kept path) against the degree, as the `.ring` case resolves `ringCell`.
  The place is state, set by the view before any chord lands, so the first sound is colored.
- `ringChose`/`ringLifted`/`keepsRingColor` generalize to the place: chosen, lifted, kept, reset, each calling `mode.onColorChange` as now.
- A geometry type per design (`CompassGeometry`, `TensionStripCells`) that is drawn by and read against the same frames, as `ColorRingGeometry` is, so a pure function maps a point to a place.
- The view labels each place from `colorNeighbours` for the held degree, or with its kind while none is held.
- Logging: `color_place_changed(place:resolved:)`.

### What it would replace

Any of A, D or E could replace both the ring (and its marks) and the key strip's color field (`KeyColorField`), which today is a third way of choosing a color with its own keep switch.
One surface and one pin instead of three surfaces and two pins is most of the simplification the v0.1.0 release wants.

## Comparison

| | A compass | B constellation | C petals | D strip | E strike map | F home lens |
|---|---|---|---|---|---|---|
| Targets on screen | 9 | 9 to 15, moving | 0 inert, 6 to 8 live | 12 | 0 (on the keys) | 11 |
| Room, upright | ~88 pt | ~200 pt | none | ~48 pt | none | ~150 pt |
| Inert meaning | kind and rank | weak | none | amount | height and brightness | height and mode |
| With the chord, at once | yes | no | no | yes | yes, one finger | yes |
| One gesture reaches | 9 | 15+ | 6 to 8 | 12 | 15 | ~20 |
| Walking (kept) reaches | everything | everything | everything | everything | no | no |
| Learnable by the hand | yes | no | partly | partly | yes | yes |
| Conflicts | none | none | sliding between keys | solo strip's place | the slide and the zones | none |
| New core | neighbours, places | neighbours, paths | neighbours | neighbours, places | none | none |

The musical range lost is the same kind in every design: the colors three or more steps from the plain chord (13♯11, a 9♯5♯9) are no longer one touch away.
Today they are, on the ring, but a player rarely plays them by reading a 55-target surface mid-phrase, and the near-step colors they do play are on every design here.

## Recommendation

Prototype **A, the step compass**, first, in the joystick bar's footprint (88 points upright), played with the pin off.

- It is the only design that is small, playable at the same moment as the chord, learnable by the hand, and free of conflicts with the keys.
- Its places mean the same before and after the press, and only their labels change, which is the rule that makes the two states one surface.
- It is the joystick's best idea (eight directions, chord-dependent shapes) put on a footing that is computed rather than tabulated, so it reaches colors from any color, in any of the 21 modes and on the octave layout's borrowed roots.
- Its core, `colorNeighbours` and `ChordColor.expressing`, is the same core D and B need, so the prototype is not wasted if the compass is not kept.
- The kept pin then gives the walk, which recovers the ring's whole range one step at a time.

Keep the ring in Setup beside it while the compass is tried, as the joystick and grid are kept now, and compare by playing.
Try **E** next as a Setup choice for the slide, since it needs no surface at all and the slide's reading already exists; it may be the answer on a phone held upright, where the compass and the ring both compete with the keys for height.

## Open questions

- **Borrowed fills.**
  Where a kind has no in-key edit (no in-key raise on ii), does the compass play the borrowed one (D major on ii, the V of V: often exactly what is wanted) marked as such, or stay silent?
  The table suggests borrowed fills are musically good more often than not.
- **Take-away.**
  Are the removals worth two of eight places?
  A bare fifth is useful in a rock voicing; a chord without its 5th sounds little different.
  Down could instead be "suspend" (3→4, 3→2), which is a move, not a removal.
- **Diagonals.**
  Eight places by kind and rank leave the diagonals unused; they could be the two-step combinations most often wanted (a 7th and a 9th at once, a 7sus4).
- **Kept: edit or shape.**
  Which one the pin keeps, or whether it should be two pins.
  The home ring keeps the edit; a player building a progression of maj7s wants the shape.
- **Walking from where.**
  Played mode steps from the plain chord; kept mode from the kept color.
  Should a played gesture over a kept color step from the kept color too, so a kept seventh and a played "+" make a ninth?
- **Seventh chords as the base.**
  If the key strip or a key zone makes every chord a seventh, the compass's neighbours are a seventh's (8 adds, 3 removals): the ranking of adds over a seventh chord needs its own look.
- **Loops and ChordLink.**
  Both should hear the resolved `ChordColor`, not the place, so a loop keeps the chord as played and the sinks know nothing of compasses.
  That falls out of resolving in `color(for:)`, but `.marked` colors are announced over ChordLink as grid colors are, which should be checked for the colors the compass reaches.
- **The step editor and the pad editor.**
  They know the degree before the color is chosen, so they could use the live compass directly; or they keep the grid, as they keep it while the ring is the surface.
- **Ranking by ear.**
  The fixed order and the avoid rule are a theory; the order should be heard on every degree of every mode before it is frozen into tests.
- **Phone on its side.**
  The ring was designed for it and has a half of the screen there; whether the compass should grow into that half (rank 3, more places) or leave it to the keys.

