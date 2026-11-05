# Score practice

Score practice is a way to memorize a piece by watching it on the piano.
A learner gives the app a score of the piece, keeps runs of it, each a stretch of one hand or of both, and then watches the runs light up on the keys as the score plays, once or over and over.
Then they tap the runs on the keys themselves, note by note, with the next note marked or from memory, and are told at each tap whether it was right.

It lives on the piano when the piano has the whole screen (`ScorePracticeView`), with the piano in the middle of the screen, where the eye rests.

## What is seen and heard

The keys light one after another as the hand plays them, each as it is struck, in the hand's color (green for the right hand, violet for the left).
A struck key flashes white for an instant, so a key struck twice in a row is seen to be struck again.
The hand's next keys are marked with a dot of its color, so the eye can lead the hand.

The score is heard as it is written, on the app's own sound (an electric piano), both hands at once, at the score's own tempo.
It does not sound like a pianist, but every note is where the score puts it.

There are no notes falling toward the keys, as in the videos that teach by that.
That view is about timing; this one is about which keys, in which order, and it is deliberately not built.

The piano is pinched and dragged as it always is, and it is brought to the runs being watched when they are chosen (the fit button does it again), so a run is seen all at once.

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
   A hand's notes are read as steps, the notes struck together (`Score.steps`), and so are both hands' notes together.
   A chord is one step, and a held note under moving ones belongs to the step it was struck in.
   A run begins and ends on a step.

2. **Runs are independent views of one score.**
   A run is a stretch of the score from any step to any other, of the right hand, the left, or both together (`Passage`, `PracticeRun`).
   Hands separate is how a piece is learned, so a run of one hand is the ordinary run, and a run of both is a choice, never the rule.
   Runs may overlap, lie one inside another or repeat a stretch, and adding, naming or deleting one leaves every other as it was (`Practice.adding`, `naming`, `removing`).
   Runs were once cut from each hand's whole part, as a tree whose runs always covered it; that made every run depend on the cuts around it, so it is gone.
   A piece kept with such a tree is read as its runs, each its own, and each hand's whole part is the whole piece, which is not a run.

3. **The score is the timing.**
   A run is where the score has it, from its first step to where the step after its last begins, or its last notes end (`Passage.span`), in the score's seconds.
   Pieces once had a recording that the score was matched to; the match was hard to get right and could put a run's start anywhere in the recording, so it is gone.
   A piece kept with a recording is read as its score: what was made of the recording is passed over, and its runs are kept.

4. **The screen shows one view at a time.**
   The hands chips show the right hand, the left, or both together (`ScorePracticeState.hands`), with the runs of those hands and their keys lit.
   With no run chosen, the whole piece of the hands shown is watched.

5. **A run is made and changed only in editing, and kept only when saved.**
   A new run begins as the note of the hands shown at the playhead (`Passage.step`); an existing one is put into editing from its menu, or by the edit button while it is the one run chosen.
   In editing, the run is dragged along the score's bar, a step at a time and keeping its length (`Passage.moved`), and at each end, Start and End, a button takes in one more note and another gives one up (`extendingStart`, `extendingEnd`, `shrinkingStart`, `shrinkingEnd`), never below one note.
   Nothing is changed until Save, which adds the run or puts the edited one in place of its old self (`Practice.replacing`) as one change that can be undone; Cancel leaves everything as it was.
   On a touch screen this keeps a finger meant to watch or seek from moving a run: while one run is edited, the other runs, the hands chips and undo wait.
   The keys show the run's first note as it moves, the piano follows it, and Play plays it.
   There is no list of notes to choose from; the bar and the keys are enough to place a run by.

6. **What plays is worked out, not kept.**
   What is watched (the runs chosen, or the whole piece of the hands shown) becomes stretches of the score, in order, joined where they overlap or touch (`Playback.segments`), and its notes become timed lights, each in the color of its hand (`Playback.notes`, `lights`).
   Runs one after another play straight through, and runs apart play one after the other, so "watch runs 2 and 4 on repeat" is one choice.
   Play begins where the playhead stands, if that is inside the runs watched, and otherwise at the next of them (`Playback.start`); a repeat goes back to the first.

7. **Both hands are heard; the hands shown are lit.**
   A pass of playing is the stretches one after another and every note of both hands struck in them, cut off where its stretch ends (`Playback.pass`), so the left hand is heard under a right-hand run as it is in the piece.
   A pass begun inside a stretch also sounds the notes held over that moment.

8. **The notes are sent ahead and the lights follow the same reckoning.**
   `ScorePlayer` sends each note a quarter of a second ahead of its moment, stamped with it, to the same audio and MIDI as the keys, so each sounds on its exact frame however late the main thread is; a note's end is sent the same way, only once it is near.
   The moment heard is worked out from the clock's time and the pass (`PlayPass.scoreTime`), so the piano is lit by the reckoning the notes are sounded by.
   Stopping lets go of every note sent, even one not yet heard.

9. **The whole score is a bar under the piano.**
   It shows the runs shown along it, the chosen ones brighter and runs that overlap in lanes one above another (`Practice.lanes`), and the playhead (`PracticeOverview`).
   A tap or a drag brings the playhead there; while nothing plays, the whole of the hands shown is lit at the moment the playhead stands at, not only the runs watched.
   Play stops while the bar is dragged and goes on from where it is let go, and the skip buttons go five seconds back or on in the same way.

10. **The phone and the Mac share their pieces through iCloud.**
   The library is a folder in the app's iCloud container (`iCloud.com.lukesovernconley.pocketchord`) when the device is signed in, and the device's own support folder when it is not (`ScoreLibrary.resolve`); pieces kept on the device before it was signed in are moved into iCloud.
   Every read and write is coordinated, so a piece from the other device is downloaded before it is read and a save is never caught half written.
   `ScoreLibraryWatcher` downloads whatever the other device adds as soon as it is known of and says when anything changes, and the piece open takes up the other device's save if it is later than its own (`Piece.modified`).
   Two devices that edit one piece while apart keep the copy iCloud chooses; nothing is merged.

11. **The practice screen has the keys while it is open.**
   The play/stop key (Space to start with) plays the runs watched or stops them, and the chord keys and the compass play nothing, from the keyboard or a controller (`PerformanceState.isPractising`).
   The play screen is still there under the piano, so a key that reached it would play chords or start the loops unseen.
   A keyboard map saved with buttons since taken away (the nudge points and the note keys) keeps the rest of what it had.

12. **Every change to the runs can be undone.**
    Adding, editing, naming and deleting a run are each a change, undone and redone by the arrows in the header, or Command-Z and Shift-Command-Z (`History`).
    What is undone is saved as any change is.
    The changes are kept while the piece is open, not with it, so opening it again begins with nothing to undo.

13. **A run can be named, and every run is seen at once.**
    A run goes by its bars ("Bars 5–8"), or by a name the learner gives it ("the leap"), by pressing and holding its chit, or right-clicking it, and choosing Name (`Practice.naming`); Edit and Delete are there too.
    "All runs" lists every run under each view of the score, with its steps and where it is in the score; a row goes to its run, which is shown and chosen to watch (`ScorePracticeState.goTo`), and it can be edited, named or deleted there.

14. **Every control says what it does.**
    A pointer resting on any button of the screen shows what it does (`help`), beside the key that does it where there is one (`hotkeyTip`).

15. **A run can be tapped on the keys, note by note.**
    The Tap button turns the piano's keys into keys to press (`ScorePracticeState.startTapping`): the learner taps the runs watched, step by step, in the order of the score, and each tap sounds at once on the same sound the score plays in (`PracticePlaying.press`).
    It is a small amount of embodied practice, to help a run that has been watched to be taken in by the hand; it is not about timing, and nothing waits or hurries.
    Each tap is told: a right one is marked on its key with a tick and said ("Right, E5"), a wrong one is marked red with a cross, said ("Wrong note, F5: try again") and felt, and the place stays where it was until the right note comes (`TapDrill.tapping`).
    A step of several notes, a chord or both hands together, is done when each of its notes has been tapped, in any order and together or one by one.
    The last note of the runs finishes a pass, said with its wrong notes, and the next tap begins another from the first step.
    The next note is marked on its key as a hand's next keys are, or not, by the Next note switch (`ScorePracticeState.showsNextNote`): it can be switched at any moment without losing the place, and is kept while the app runs, not with the piece.
    The notes of a chord already tapped stay lit either way, so it is seen how much of it is left.
    Tapping begins at the step at the playhead if that is inside the runs, the playhead follows the place so the score's bar shows how far the learner has got, and moving the playhead moves the place.
    Choosing other runs or other hands while tapping taps those from their start; playing the score ends tapping.
    While tapping, a finger on the piano is a key the moment it touches, so the pinch, the one-finger drag and the double tap are off (a trackpad's or a mouse wheel's scroll still moves it), and the fit button brings the keys to the runs.
    The core is `TapDrill`: the steps to tap and how far the learner has got, every tap a function from one drill to the next.

## Where things are

- `Perfecto/Sources/ScorePractice/`: the pure core, tested with `swift test` in `Perfecto/` (`ScorePracticeTests`).
  `Score`, `MusicXML`, `Mxl` and `MidiScore` read a score; `Practice` is the runs, every change to it a function from one value to the next, and `History` the changes, to undo; `Playback` says what plays, as passes of timed notes, and what lights; `TapDrill` is a run being tapped.
- `ViewModels/ScoreLibrary.swift`: the pieces on disk, each a folder in iCloud (or Application Support) with the score as given and `piece.json` beside it, and the watcher of the iCloud folder.
- `ViewModels/ScorePracticeState.swift`: the shell the screen talks to.
  It keeps the piece open, the hands shown, the runs chosen, the run being made, the changes to undo and the playhead, saves the piece on each change, plays the score and brings the piano to the runs.
- `Audio/ScorePlayer.swift`: what plays the score on the note sinks, behind `PracticePlaying` so the state is tested without sound.
- `Views/ScorePracticeView.swift`, `PracticeOverview.swift`: the screen.

## Open questions

- Playing slower than written would help with fast runs, and is now only a matter of stretching each pass's times.
- A score whose hands cross staves (a right-hand note written in the bass staff) is read by staff, so such a note counts for the left hand.
- Nothing is drawn of the notation itself.
