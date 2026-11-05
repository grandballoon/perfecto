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

The score is MusicXML, either compressed (`.mxl`) or not (`.musicxml`, `.xml`), or failing that a Standard MIDI File (`.mid`).

- It is what every notation program exports (MuseScore, Dorico, Finale, Sibelius), and `.mxl` is their default: one small file that the Files app, AirDrop and Mail pass along as it is.
- It states which staff every note is on, and the staff is what says the hand.
  A MIDI file only has tracks, which a piano's export may or may not divide by hand, so a run of one hand would be a guess.
- Harmonicland reads the same format, by the same rules (`src/inputs/musicxml.ts`, `mxl.ts`), so a score prepared for one is ready for the other.
  Harmonicland also reads LilyPond; the app does not, since LilyPond needs LilyPond itself to read.

A MIDI file is read too (`MidiScore`), for a piece that is to be had only as MIDI.
It says the hand only by how its tracks are divided, so the hand is decided by rule:
a track named for a hand plays it ("rh", "right", "treble", "upper"; "lh", "left", "bass", "lower"), and otherwise the first track with notes is the right hand and the rest the left, a channel of a track that uses several counting as a track.
A file of one track is split at middle C, which is a guess.

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

9. **The recording is dragged to go anywhere in it.**
   Under the recording strip is the whole recording as one bar (`PracticeScrubber`), and a finger on the bar or on the strip's waveform drags the recording (`ScorePracticeState.scrub`).
   While it is dragged it stops, and the keys are lit as the shown hand has them at each moment passed; while nothing plays, the whole hand is lit at the moment the recording stands at, not only the runs watched.
   Whatever was playing (the runs, or the recording listened to) plays on from where it is let go, and the skip buttons go five seconds back or on in the same way.
   Play begins where the recording stands, if that is inside the runs watched, and otherwise at the next of them (`Playback.start`); a repeat goes back to the first.

10. **The practice screen has the keys while it is open.**
    The play/stop key (Space to start with) plays the runs watched or stops what plays, and the chord keys and the compass play nothing, from the keyboard or a controller (`PerformanceState.isPractising`).
    The play screen is still there under the piano, so a key that reached it would play chords or start the loops unseen.

11. **The recording is matched by ear, and the learner only nudges.**
    When a recording is added, the app hears it once (`RecordingFeatures`): how strong each of the twelve pitch classes is a hundred times a second, through a long window that tells the notes apart and a short one that catches the moment each is struck.
    The score is turned into the same twelve classes (`ScoreChroma`, each note dying away as a piano's does), and the two are lined up by dynamic time warping (`AutoMatch`), so the score bends to the recording's rubato.
    Each step's moment is then found from the strike of its notes near where the path put it.
    A run of repeated chords sounds alike chord to chord, so a pass after the warp checks each step against the pace of the steps around it (a robust line through them) and moves one that has slipped a chord.
    The result is kept (`Practice.matched`), apart from the learner's anchors.

12. **What the learner sets is a pin.**
    A step dragged to where it is heard on the recording strip, or a run's Start or End, is an anchor the match must pass through (`Practice.anchors`).
    Changing the pins matches the rest again around them, in the background; the alignment played is the pins and the matched anchors that agree with them (`Alignment.merged`).
    "Match again" and "Clear pins and match again" in the menu start over.

13. **Nudge points are where to look.**
    Where the music heard does not fit the score for a while (a stretch the score does not have, a wrong recording), the match marks it as doubtful (`Practice.unsure`, dashed yellow on the strip).
    While listening, the learner tags a moment that sounds off with the flag button, N on the keyboard or L1 on a controller (`Practice.nudges`, orange flags).
    The chevrons beside the flag go to the previous or next nudge point, zoom the strip to it, and keep listening if it was.
    Untagging a moment also clears a doubt there, once it is seen to.

14. **What the match gets wrong.**
    A sudden pause inside a run of identical chords can put the chords after it one out, since nothing but the pace tells them apart; that is a nudge.
    A recording in a different key or tuning from the score, or with repeats the score does not have, is matched poorly and mostly doubted.

## Where things are

- `Perfecto/Sources/ScorePractice/`: the pure core, tested with `swift test` in `Perfecto/` (`ScorePracticeTests`).
  `Score`, `MusicXML`, `Mxl` and `MidiScore` read a score; `Practice` is the runs and anchors, and every change to it is a function from one value to the next; `Alignment` maps score time to recording time; `Playback` says what plays and what lights; `Chroma` hears a recording and `AutoMatch` matches it to the score.
- `ViewModels/ScoreLibrary.swift`: the pieces on disk, each a folder in iCloud (or Application Support) with the score and recording as given and `piece.json` beside them, and the watcher of the iCloud folder.
- `ViewModels/ScorePracticeState.swift`: the shell the screen talks to.
  It keeps the piece open, the hand shown, the run in focus and the runs chosen, saves the piece on each change, plays the recording and brings the piano to the runs.
- `Audio/RecordingPlayer.swift`: the recording's player, behind `RecordingPlaying` so the state is tested without audio.
- `Views/ScorePracticeView.swift`, `PracticeRecordingStrip.swift`, `PracticeScrubber.swift`: the screen.

## Open questions

- Slowing the recording down without changing its pitch would help with fast runs; the player is an engine already, so it would be a time-pitch unit in front of it.
- A score whose hands cross staves (a right-hand note written in the bass staff) is read by staff, so such a note counts for the left hand.
- Nothing is drawn of the notation itself; the steps strip names the notes, which is enough to cut by.
