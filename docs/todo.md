# To do

Open loops on the `audio-engine` branch, as of 2026-10-06.
The designs are in `docs/audio-engine-spec.md` and `docs/sequencer-spec.md`.


We need to implement drum machine support

We need to refactor the Sound architecture to support swap-in, swap-out for different machine sounds.



## Check on the phone

Nothing below has been heard or seen on a device except that the keys make sound and the sequencer screen looks right.

- [X] Each preset against your memory of it, especially the filtered ones. Finding: Works.
- [X] The reverb and the chorus, and whether the limiter is audible under dense layers. Finding: sounds good.
- [ ] A recorded loop stays tight, and a second loop played over it lands in time.
- [X] Sound survives plugging and unplugging headphones. FINDING: yes, sound survives
- [X] Mic sample: record, play at several pitches, relaunch and find it still there. Finding: hitting record, making noise, and then hitting the "stop record" button crashes the app.
- [X] Vocoder with headphones: is it intelligible, and is its level close to the plain notes?
- [X] Vocoder on the speaker: does it feed back, and does echo cancelling dull or break the sound?
- [X] Audio export: the file opens elsewhere and sounds like the app.
- [ ] CPU with many layers (the build on the phone is Debug, so it reads high).

## Timing and the clock

- [ ] Move the clock off the main thread, onto its own queue.
  It runs on the main thread, so a stall longer than the 50 ms lead makes a timeline note late.
  It is not known how often the phone stalls that long; opening the side panel and redrawing the sequencer grid are the likely causes.
- [ ] If stalls are heard before that is done, lengthen the lead (`NotePlayer.sequencedLead`).
  It is a one-line change, and the timeline is then heard that much further behind the clock.
- [ ] A live arpeggio and Repeat are only as punctual as the main thread.
  They need the same lead the timeline has, which means the keys' own clocked notes being sent ahead.
- [ ] The mapping from real time to kernel frames, and the MIDI timestamps, are tested only in simulation.
  Check MIDI timing against a DAW.

## Velocity

- [ ] Decide what drives velocity.
  The kernel takes a velocity per note, but every note is struck at 0.7 because the keys do not sense force.
  Candidates: where on the key the finger lands, how fast it arrives, or a setting.
- [ ] Decide whether velocity also opens the filter, per patch, as the spec proposes.
- [ ] MIDI velocity is fixed at 100; it should follow whatever is decided.

## Vocoder

- [ ] Tune its level by ear.
  One constant (`makeup` in `Vocoder.hpp`), set from a synthetic voice.
- [ ] Give its output chorus and reverb.
  Small: decide whose settings it follows, then add two sends in the kernel's mix.
- [ ] Consider noise for consonants the carrier lacks, if speech is hard to make out.
- [ ] Loop a vocoded or sung phrase as a layer.
  This is the one that needs new design; see "Audio loops" below.

## Audio loops (needs design)

A vocoded phrase or a sung line is not notes, so it cannot be a loop of notes.
The kernel can already record the vocoder's output or the mic into a capture and play a capture back.
What is missing is in the timeline:

- [ ] A note that plays a recording and not a chord.
  `TimelineNote` is a chord today, and the grid, the edits and `compile` assume it.
- [ ] Recording one from the LOOP button, and what happens to the notes played during that take.
- [ ] Keeping the recordings with the saved timeline (only the mic sample is kept on disk now).
- [ ] What a tempo change does to a recorded layer, which cannot stretch.
- [ ] Which of the four captures a layer gets, and what happens when they run out.

Once this exists, exported audio includes vocoded layers; until then, vocoder notes are exported plain.

## Solo strip

A first version is built, for trying on the phone: `docs/solo-strip.md` says what it does and what is still open.

- [ ] Try the three placements (Setup, SOLO STRIP) and choose one, or keep the choice.
- [ ] Decide which notes: the pentatonic built now leaves out a seventh the chord has.
- [ ] A loop does not record what the strip plays.
- [ ] The strip's sound: it takes the keys' preset and volume, and has no glide.
- [ ] The more permissive models (tension that resolves, pitch that bends between cells).

## Sampled sounds

- [ ] Band-limit a recording played far above its pitch, which can sound harsh.
- [ ] Sampled instruments (audio engine step 13).
  Waiting on: which instruments, permission to download them, and sfizz or the kernel's own sampler.
  No samples are to be downloaded yet.

## Smaller gaps

- [ ] Per-layer volume is stored but not heard.
- [ ] Voice-stealing is no longer logged (the kernel steals on the render thread).
- [ ] A chord is not sounded when it is entered in the sequencer, only when playback reaches it.
- [ ] Audio export is only in the sequencer's share menu; consider one in Play mode, and a smaller format for messaging.
- [ ] Voice leading and inversion per note have no field in the timeline.
- [ ] Looping a scattered set of steps was dropped for one stretch of time; say if it matters.
- [ ] Reverb per layer, if one room for everything proves too limiting.

## Stale documents

- [ ] `spec.md` still describes AudioKit, Mic Sample as a mode, and a `.playAndRecord` session.
- [ ] `project.yml` still lists the AudioKit packages; the project file is hand-edited and does not use it.

- [ ] When exporting sound, there's a long delay between selecting the file format and the "share" UI popping up. If this is a matter of encoding the file for export, we need a progress bar with percentages (if feasible) or a spinner icon (if not). If this is a problem with the code that calls the share interface on iOS, we need to fix that.

- [ ] Switching from Play mode to Sequence mode by tapping the sequencer button sometimes takes several taps.

- [ ] Define concept of UIPanel and UITemplate so that swappable component architecture can be expanded down the line (implementation of this is not immanent; current architecture is acceptable for now).