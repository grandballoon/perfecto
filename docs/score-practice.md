# Score practice

Score practice is a way to memorize a piece by watching it on the piano.
A learner gives the app a score of the piece, cuts each hand's part into runs, and then watches the runs light up on the keys as the score plays, once or over and over.

It lives on the piano when the piano has the whole screen (`ScorePracticeView`), with the piano in the middle of the screen, where the eye rests.

## What is seen and heard

The keys light one after another as the hand plays them, each as it is struck, in the hand's color (green for the right hand, violet for the left).
A struck key flashes white for an instant, so a key struck twice in a row is seen to be struck again.
The hand's next keys are marked with a dot of its color, so the eye can lead the hand.

The score is heard as it is written, on the app's own sound (an electric piano), both hands at once, at the score's own tempo.
It does not sound like a pianist, but every note is where the score puts it.

There are no notes falling toward the keys, as in the videos that teach by that.
That view is about timing; this one is about which keys, in which order, and it is deliberately not built.

The piano is pinched and dragged as it always is, and it is brought to the runs being watched when they are chosen (the fit button does it again), so a run, which is usually of one hand, is seen all at once.

## The format

The score is a Standard MIDI File (`.mid`), or MusicXML, either compressed (`.mxl`) or not (`.musicxml`, `.xml`).

A MIDI file says the hand only by how its tracks are divided, so the hand is decided by rule (`MidiScore`):
a track named for a hand plays it ("rh", "right", "treble", "upper"; "lh", "left", "bass", "lower"), and otherwise the first track with notes is the right hand and the rest the left, a channel of a track that uses several counting as a track.
A file of one track is split at middle C, which is a guess.

MusicXML states which staff every note is on, and the staff is what says the hand, so it never has to be guessed.
It is what every notation program exports (MuseScore, Dorico, Finale, Sibelius), and `.mxl` is their default.
Harmonicland reads the same format, by the same rules (`src/inputs/musicxml.ts`, `mxl.ts`), so a score prepared for one is ready for the other.

The piece menu opens a piece kept, or closes the one open (`ScorePracticeState.closePiece`), which takes it off the piano and keeps it among the pieces; deleting a piece erases it.
The screen opens the latest piece the first time it appears, and after that leaves the piano as it was left, with no piece if one was closed.

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

3. **The score is the timing.**
   A run is where the score has it, from its first step to the end of its last (`Practice.span`), in the score's seconds.
   Pieces once had a recording that the score was matched to; the match was hard to get right and could put a run's start anywhere in the recording, so it is gone.
   A piece kept with a recording is read as its score: what was made of the recording is passed over, and its runs are kept.

4. **What plays is worked out, not kept.**
   The runs watched (those chosen, or the run in focus) become stretches of the score, in order, joined where they touch (`Playback.segments`), and their notes become timed lights (`Playback.notes`, `lights`).
   Runs one after another play straight through, and runs apart play one after the other, so "watch runs 2 and 4 on repeat" is one choice.
   Play begins where the playhead stands, if that is inside the runs watched, and otherwise at the next of them (`Playback.start`); a repeat goes back to the first.

5. **Both hands are heard; the hand shown is lit.**
   A pass of playing is the stretches one after another and every note of both hands struck in them, cut off where its stretch ends (`Playback.pass`), so the left hand is heard under a right-hand run as it is in the piece.
   A pass begun inside a stretch also sounds the notes held over that moment.

6. **The notes are sent ahead and the lights follow the same reckoning.**
   `ScorePlayer` sends each note a quarter of a second ahead of its moment, stamped with it, to the same audio and MIDI as the keys, so each sounds on its exact frame however late the main thread is; a note's end is sent the same way, only once it is near.
   The moment heard is worked out from the clock's time and the pass (`PlayPass.scoreTime`), so the piano is lit by the reckoning the notes are sounded by.
   Stopping lets go of every note sent, even one not yet heard.

7. **The whole score is a bar under the piano.**
   It shows the runs shown along it, the chosen ones brighter, and the playhead (`PracticeOverview`).
   A tap or a drag brings the playhead there; while nothing plays, the whole hand is lit at the moment the playhead stands at, not only the runs watched.
   Play stops while the bar is dragged and goes on from where it is let go, and the skip buttons go five seconds back or on in the same way.

8. **The phone and the Mac share their pieces through iCloud.**
   The library is a folder in the app's iCloud container (`iCloud.com.lukesovernconley.pocketchord`) when the device is signed in, and the device's own support folder when it is not (`ScoreLibrary.resolve`); pieces kept on the device before it was signed in are moved into iCloud.
   Every read and write is coordinated, so a piece from the other device is downloaded before it is read and a save is never caught half written.
   `ScoreLibraryWatcher` downloads whatever the other device adds as soon as it is known of and says when anything changes, and the piece open takes up the other device's save if it is later than its own (`Piece.modified`).
   Two devices that edit one piece while apart keep the copy iCloud chooses; nothing is merged.

9. **The practice screen has the keys while it is open.**
   The play/stop key (Space to start with) plays the runs watched or stops them, and the chord keys and the compass play nothing, from the keyboard or a controller (`PerformanceState.isPractising`).
   The play screen is still there under the piano, so a key that reached it would play chords or start the loops unseen.
   A keyboard map saved with buttons since taken away (the nudge points and the note keys) keeps the rest of what it had.

10. **A run can be named, and every run is seen at once.**
    A run goes by its place ("2.3"), or by a name the learner gives it ("the leap"), by pressing and holding its chit, or right-clicking it, and choosing Name (`Practice.naming`).
    Cutting a named run leaves the name on its first part, and joining two keeps the first's name, or else the second's.
    "All runs" lists every run of both hands as an outline, each under the run it was cut from, with its steps and where it is in the score (`Practice.outline`); a row goes to its run, which is chosen to watch among the runs it is one of (`ScorePracticeState.goTo`).

11. **Every control says what it does.**
    A pointer resting on any button of the screen shows what it does (`help`), beside the key that does it where there is one (`hotkeyTip`).

## Where things are

- `Perfecto/Sources/ScorePractice/`: the pure core, tested with `swift test` in `Perfecto/` (`ScorePracticeTests`).
  `Score`, `MusicXML`, `Mxl` and `MidiScore` read a score; `Practice` is the runs, and every change to it is a function from one value to the next; `Playback` says what plays, as passes of timed notes, and what lights.
- `ViewModels/ScoreLibrary.swift`: the pieces on disk, each a folder in iCloud (or Application Support) with the score as given and `piece.json` beside it, and the watcher of the iCloud folder.
- `ViewModels/ScorePracticeState.swift`: the shell the screen talks to.
  It keeps the piece open, the hand shown, the run in focus, the runs chosen and the playhead, saves the piece on each change, plays the score and brings the piano to the runs.
- `Audio/ScorePlayer.swift`: what plays the score on the note sinks, behind `PracticePlaying` so the state is tested without sound.
- `Views/ScorePracticeView.swift`, `PracticeOverview.swift`: the screen.

## Open questions

- Playing slower than written would help with fast runs, and is now only a matter of stretching each pass's times.
- A score whose hands cross staves (a right-hand note written in the bass staff) is read by staff, so such a note counts for the left hand.
- Nothing is drawn of the notation itself; the steps strip names the notes, which is enough to cut by.
