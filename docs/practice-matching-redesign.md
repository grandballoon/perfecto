# Matching notes to the recording: findings and plan

Score practice needs a new way to match the score's notes to the recording.
The current recording strip and scrubber are hard to use and partly broken.
This note says what is wrong, what replaces it, what is already written, and what is left.

## What is wrong now (read from the code, not yet reproduced on a device)

- `PracticeRecordingStrip` puts three kinds of drag in one 72 pt strip: scrubbing (the background), run edges (24 pt handles) and step ticks (up to 24 pt handles each).
- In a dense passage the step ticks cover most of the strip.
  So a drag meant to scrub usually grabs a tick and pins that step where the finger is, which moves notes and starts a re-match.
  This is the most likely cause of "badly broken".
- Every scrub frame calls `stop()` and then restarts the player when the drag ends (`ScorePracticeState.scrub`, `stand`).
- The strip's window jumps between three sources (`heldWindow`, `zoom`, and the run in focus), so what is shown moves under the finger.
- `PracticeScrubber` maps the whole recording onto one bar, so on a long recording a point of the bar is seconds of audio and nothing can be placed precisely.
- Precise matching is only possible by dragging, and there is no way to step through notes or nudge one by a small amount.

## The new design

Under the piano, two timelines on one shared time axis (recording seconds):

1. **The waveform lane**: the recording's outline, the runs shown as faint bands, nudge points (flags and doubts), the playhead, and a guide line at the chosen note.
2. **The notes lane**: a piano roll of both hands' notes where the recording has them (x is time, y is pitch).
   The shown hand is in its color, the other hand dim and not tappable.
   The chosen step is white, and pinned moments are marked.

Below them:

3. **An overview bar**: the whole recording, with the visible window drawn as a box.
   A tap or drag on it moves the window.
   It does not move the playhead.
   The zoom − and + buttons sit beside it.
4. **A notes row**: previous note, nudge −100 ms, −10 ms, the chosen note's time (to the millisecond), +10 ms, +100 ms, next note, hear it, and unpin.
5. **The transport row**, as now, without Start and End.

### Interaction rules

- A drag on either lane pans the view.
  The only exception is a drag that starts on the chosen note in the notes lane, which moves that note.
  The choice between the two is made once, at the start of the drag.
- A tap on the waveform puts the playhead there.
- A tap on a note chooses its step.
  A tap on an empty part of the notes lane puts the playhead there.
- A pinch zooms about the point under the fingers.
- Choosing a step stops playback, stands the playhead at it, lights its keys, and brings it into view.
- A nudge pins the chosen step at its new time.
  It stays between the moments held on either side of it, so it never passes a neighbour.
  The rest is matched again 0.8 s after the last nudge, not on every press.
- "Hear it" plays from 1.5 s before the chosen note to 1 s after it, then returns the playhead to the note.
- While the recording plays, the view turns over a page at a time when the playhead reaches its edge.
  Panning or zooming stops that until the next play or seek.
- Keyboard: `[` and `]` choose the previous and next note, `,` and `.` nudge by 10 ms.
  These are new `KeyboardButton` cases with standard keys, and old saved maps pick them up through `KeyboardMap.completed(from:)`.
- The run edge handles, the step tick drags, drag-scrubbing, and the Start and End buttons are removed.
  A run's start is now set by choosing its first note and nudging or dragging it.

### Where the logic lives

The design follows the functional-core rule:

- **`RecordingWindow`** (core, new): the visible stretch as a value.
  It has `panned`, `zoomed(by:around:)`, `centred`, `revealing`, `paging(to:)` and `clamped`, never shorter than 0.25 s.
- **`Practice`** (core): `moving(_:to:in:)`, `nudging(_:by:in:)`, `unpinning`, `isPinned`, `step(_:nearest:within:in:)` and `step(_:from:forward:in:)`.
  A moment is clamped between the nearest anchors of the alignment, not its neighbouring onsets.
  So with nothing matched, a single pin still moves the whole score.
- **`ScorePracticeState`** (shell): `window`, `follows`, `selectedStep` (which replaces `previewStep`), `timelineNotes`, `pitchRange`, `shownWindow(at:)`, `showWindow`, `zoom(by:)`, `select`, `tapNotes(at:within:)`, `selectNext`, `nudge(by:)`, `moveSelected(to:isDone:)`, `unpinSelected`, `hearSelected` (with a new `Listening.step` case), and `matchAgain(after:)`.
- `peaksPerSecond` goes from 50 to 200, so a note's attack is visible when zoomed in.

## Status

Built, uncommitted in the working tree.
The core (`RecordingWindow`, the nudge and step-finding functions on `Practice`, `NudgeTests`), the shell (`ScorePracticeState`), the keys, and the views (`PracticeTimelines`, `PracticeOverview`, `PracticeNotesRow`, the transport without Start and End, the steps strip on `selectedStep`) are done.
The state's tests are rewritten in terms of select, nudge, unpin, the window and seek, with new ones for the debounced re-match, "hear it" and the paging window.
`docs/score-practice.md` (decisions 5, 9, 12 and "Where things are") and `CLAUDE.md` describe the new design.

Left: checking the screen by eye on the Mac and a phone, above all the room under the piano on a phone held sideways (see below).

## Open questions

- Two-finger trackpad scrolling on the Mac will not pan the lanes: SwiftUI's `DragGesture` does not get scroll events on iOS 17.
  Click-drag, pinch, the overview and the zoom buttons cover it for now.
  A small UIKit pan recogniser with `allowedScrollTypesMask` would add it.
- On a phone held sideways the area under the piano is tight: two lanes plus three rows come to about 240 pt.
  The lanes may need to shrink, or the notes row may need to fold into the transport row.
- No game-controller defaults are given for the new buttons, since the d-pad holds chords.
  They can be mapped in Setup.
