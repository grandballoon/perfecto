# Score practice

Score practice is a way to memorize a piece by watching it on the piano.
A learner gives the app a score of the piece and a recording of it, cuts each hand's part into runs, matches the runs to the recording, and then watches the runs light up on the keys as the recording plays, once or over and over.

It lives on the piano when the piano has the whole screen (`ScorePracticeView`), with the piano in the middle of the screen, where the eye rests.

## What is seen

The keys light one after another as the hand plays them, each as it is struck, in the hand's color (green for the right hand, violet for the left).
A struck key flashes white for an instant, so a key struck twice in a row is seen to be struck again.
The hand's next keys are marked with a dot of its color, so the eye can lead the hand.

There are no notes falling toward the keys, as in the videos that teach by that.
That view is about timing; this one is about which keys, in which order, and it is deliberately not built.

The piano is pinched and dragged as it always is, and it is brought to the runs being watched when they are chosen (the fit button does it again), so a run, which is usually of one hand, is seen all at once.

## The format

The score is MusicXML, either compressed (`.mxl`) or not (`.musicxml`, `.xml`).

- It is what every notation program exports (MuseScore, Dorico, Finale, Sibelius), and `.mxl` is their default: one small file that the Files app, AirDrop and Mail pass along as it is.
- It states which staff every note is on, and the staff is what says the hand.
  A MIDI file only has tracks, which a piano's export may or may not divide by hand, so a run of one hand would be a guess.
- Harmonicland reads the same format, by the same rules (`src/inputs/musicxml.ts`, `mxl.ts`), so a score prepared for one is ready for the other.
  Harmonicland also reads MIDI and LilyPond; the app does not, since LilyPond needs LilyPond itself to read and MIDI cannot say the hand.

The recording is any audio file the system plays (`.m4a`, `.mp3`, `.wav`, `.aiff`, `.caf`).
It is heard as it was recorded: nothing is synthesized, and the recording is never stretched.

## Decisions

1. **A step is what lights at once.**
   A hand's notes are read as steps, the notes struck together (`Score.steps`).
   A chord is one step, and a held note under moving ones belongs to the step it was struck in.
   Runs are counted in steps.

2. **A run is a stretch of one hand's steps, and runs make a tree.**
   Each hand's whole part is a run, its root, and cutting a run divides it into runs of its own, which can be cut again when the fingering is still too much to follow (`Practice.cutting`, `joining`).
   A run's runs always cover it end to end.
   Joining two runs keeps the runs either had.
   A run is not a hand chosen per sitting: it is of one hand, because the score's hands are separate parts.

3. **The score moves, not the recording.**
   A recording is listened to for its rubato, so the score's seconds are bent to the recording's (`Alignment`), as harmonicland does.
   An anchor is a moment of the score and where the recording has it; between two anchors the notes share out the recording's time in the score's proportions, and beyond the last the nearest pace keeps.

4. **The anchors are the piece's, not a hand's.**
   Both hands are in one recording, so matching a right-hand run also places the left hand's notes at that moment.

5. **Matching a run is anchoring its ends.**
   "Start" and "End" set where the matched run (the one run chosen, or the run in focus) begins and ends to the moment heard.
   Dragging the edge between two runs on the recording moves both.
   Matching a run inside the run in focus first keeps the run in focus where it is heard (`Practice.keeping`), so its other runs stay put.

6. **What plays is worked out, not kept.**
   The runs watched (those chosen, or the run in focus) become stretches of the recording, in order, joined where they touch (`Playback.segments`), and their notes become timed lights (`Playback.notes`, `lights`).
   Runs one after another play straight through, and runs apart play one after the other, so "watch runs 2 and 4 on repeat" is one choice.

7. **The phone and the Mac share their pieces through iCloud.**
   The library is a folder in the app's iCloud container (`iCloud.com.lukesovernconley.pocketchord`) when the device is signed in, and the device's own support folder when it is not (`ScoreLibrary.resolve`); pieces kept on the device before it was signed in are moved into iCloud.
   Every read and write is coordinated, so a piece from the other device is downloaded before it is read and a save is never caught half written.
   `ScoreLibraryWatcher` downloads whatever the other device adds as soon as it is known of and says when anything changes, and the piece open takes up the other device's save if it is later than its own (`Piece.modified`).
   Two devices that edit one piece while apart keep the copy iCloud chooses; nothing is merged.

8. **The sound lights the keys.**
   `RecordingPlayer` plays the recording through an engine of its own, beside the instrument's, and says the moment being heard from the player's own count of frames, so the lights follow the sound and not a timer.
   Segments are handed to the player ahead of time, so a run repeats with no gap.

## Where things are

- `Perfecto/Sources/ScorePractice/`: the pure core, tested with `swift test` in `Perfecto/` (`ScorePracticeTests`).
  `Score`, `MusicXML` and `Mxl` read a score; `Practice` is the runs and anchors, and every change to it is a function from one value to the next; `Alignment` maps score time to recording time; `Playback` says what plays and what lights.
- `ViewModels/ScoreLibrary.swift`: the pieces on disk, each a folder in iCloud (or Application Support) with the score and recording as given and `piece.json` beside them, and the watcher of the iCloud folder.
- `ViewModels/ScorePracticeState.swift`: the shell the screen talks to.
  It keeps the piece open, the hand shown, the run in focus and the runs chosen, saves the piece on each change, plays the recording and brings the piano to the runs.
- `Audio/RecordingPlayer.swift`: the recording's player, behind `RecordingPlaying` so the state is tested without audio.
- `Views/ScorePracticeView.swift`, `PracticeRecordingStrip.swift`: the screen.

## Open questions

- Slowing the recording down without changing its pitch would help with fast runs; the player is an engine already, so it would be a time-pitch unit in front of it.
- A score whose hands cross staves (a right-hand note written in the bass staff) is read by staff, so such a note counts for the left hand.
- Nothing is drawn of the notation itself; the steps strip names the notes, which is enough to cut by.
