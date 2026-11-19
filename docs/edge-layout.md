# The edge layout

A chord layout for a phone on its side (`ChordGridLayout.edge`), made to try a larger color surface than the play screen has had.
The seven chord keys are at the screen's edges, and the middle is a surface that colors the chord held.
The surface in the middle is meant to be swapped while it is tried, so the layout gives it a slot of its own, and there are three to choose from: the step compass grown, a table that never moves, and a tree of steps from the chord held.

## The keys

The keys are two columns, one at each side of the screen (`EdgeKeyLayout`).
The root's column has I to IV from the bottom up, so the root is in a bottom corner.
The other column has V to vii° from the top down, so the degrees go round from the root: up one side, across, and down the other.
Each column's keys share its height, so the column of three has taller keys than the column of four.
A column is 15% of the screen's width, from 88 to 150 points, and never more than a third of it.

Right-handed, the root's column is on the left, so the left hand chooses the chords as a guitarist's frets them and the right hand colors them in the middle.
Setup's Left-handed switch (`PerformanceState.handedness`, under the layout while the edge is chosen) mirrors the whole layout: the root is in the bottom right corner and the degrees go round the other way.
The left hand's frames are the right hand's in a mirror, which `EdgeKeyLayoutTests` checks.

The keys are drawn by `ChordKeysView` (`ChordKeyArrangement.edge`) and played through `ChordKeySurface` like every layout's, each marked with `chordKey(_:)` as a rectangle.
`EdgeKeyLayout` is a value worked out from the size alone, so the keys and the middle are laid out by the same frames.

Held upright, the edge layout has no room for its middle, and the screen shows the circle.

## The screen

A band along the top has the menu button's corner, the note display and the sound, the key strip (at most 260 points wide) and MIDI (`PerformanceView.edgeLandscapeLayout`).
Under it, the keys are at the sides, and the middle has the loop bar and the effect strip over the surface, which has everything left.
The key strip is in the band, not over the surface, to give the surface the height.

## The middle

What is in the middle is a `CenterSurface`, kept on `PerformanceState.centerSurface`, and drawn by `EdgeCenterSurface`, which is the one place that asks which.
A new surface is a case of `CenterSurface` and a line in `EdgeCenterSurface`, and Setup's choice offers it.
Whatever the surface, it colors the chord through `PerformanceState` as the compass does, so the modes, loops and sinks get the chord as played and know nothing of it.

### The step compass, grown

The first surface is the step compass (`StepCompassSurface` with `hasCorners`), since it is what the play screen already colors with (`docs/chord-dependent-coloration.md`).
Its cross of places is as on the other layouts, larger.
The four corners the cross leaves empty (`StepCompassGrid.Corner`, each two cells by two) hold the compass's switches, so they are within reach while playing:

- Top leading, the order of its choices (theory or common), Setup's Compass order.
- Top trailing, whether its places are named by chords, Setup's Compass names.
- Bottom leading, a step back along the walk kept (`PerformanceState.compassStepBack`), named by the steps the walk takes ("+♭7 · +2", `CompassWalk.steps`).
  It is dimmed while the compass plays its places rather than keeping them.
- Bottom trailing, the pin, which is the small switch in the compass's corner on the other layouts.

The places are still each kind's first and second choice.
More choices to a kind (a third rank) would change `StepCompass.ranks` in the music theory core, its C++ port and the desk, and the walks saved by place; it is left for when the grown compass has been played.

### The color table

The second surface is a table of chord qualities whose layout never changes (`ColorTable`, `ColorTableSurface`), so a quality is always found in the same place, whatever chord is held.
A row is a family, commonest first:

- Triads: maj, min, sus2, sus4, dim, aug, 5.
- Sixths and adds: 6, min6, add9, min add9, 6/9, min6/9.
- Sevenths: maj7, 7, min7, min7♭5, dim7, min(maj7), 7sus4.
- Ninths, altered and 11ths: maj9, 9, min9, 7♭9, 7♯9, add11, min add11.

A quality is played on whatever chord is held, in key or not, so maj7 on V is G maj7, marked as out of key.
It is a color of its own (`PerformanceState.tableTones`), not a place: while there is one it is the color on every degree, and the compass's places are not.
The last column has the plain chord at the top, which lets the table's color go, and the pin at the bottom.
The pin works as on the compass: played, a quality sounds while a finger is on it; kept, it stays until another is chosen or the plain chord.
With a chord held each cell is named by the chord it plays, and otherwise by its quality.

### The color tree

The third surface is the compass's steps as a tree drawn from the chord held (`ColorTree`, `ColorTreeLayout`, `ColorTreeSurface`).
The root, in the middle, is the chord the tree steps from: the plain chord, or the walk kept.
A branch goes out from it to each of the compass's eight places, each kind its way as on the compass (up adds, right raises, down takes away, left lowers), its first choice turned back from that way and its second on.
From the branch a finger is on, a step further fans out to the surface's edge: each kind's first choice from that branch's chord.
A child that only undoes its branch (Csus4 lowered back to C) is left out, and two paths to the same chord stay two nodes, so it is a tree and not a graph.

A node is the path of places that reaches it, played as a walk is (`StepCompass.walk`), so a node is the same steps on every degree.
A finger on a node plays its whole path at once (`PerformanceState.treeHeld`), and sliding along a branch to a child walks it a step further.
Played, lifting is the plain chord again.
Kept by the pin, lifting keeps the path (`treeLifted`, which adds it to the walk), and the tree is drawn from its node next.
The path held is the compass's held place grown to several (`PerformanceState.heldPath`), played on top of the walk kept, so the compass and the tree share one state.
With a chord held each node is named by the chord it plays and its step; with none, by what its step does from I.
Under the tree are the plain chord, a step back along the walk kept, and the pin.

### Which surface, and what is shared

Setup's Middle choice, under the Left-handed switch, picks the surface.
Switching surfaces lets go of whatever color was played or kept.
The surfaces share the pin (`keepsCompassColor`), the compass's order and its names, and the latest one touched is the color: a compass place lets the table's quality go, and a quality lets the walk go.


## Open questions

- Whether the root's column should have four keys and the other three, or the other way round, so that V is under the same thumb as I.
- Whether the root should be the larger key, since it is played most.
- Whether the loop bar and the effect strip belong in the middle, over the surface, or somewhere that leaves the surface the whole height.
- Whether the switches in the compass's corners are the right ones, or whether the corners should be more places (two-step colors, or a third choice).
- Whether the table should hold only the qualities that fit the key on the degree held, or all of them as now.
- Whether the tree's children should show for the last branch played after the finger lifts, so the second level can be read before it is reached.
- Whether the tree's branches should give a kind both its choices at the second level too, once it is clear how much can be read at once.
