We need to architecturally unify the sequencer and the loop functionalities.

It should be possible to construct a sequence and then play it back under Play Mode as a loop.

It should also be possible to record a loop and then view and edit it in the sequencer view. Similarly, the new loop should be then playable as a loop during play mode.

All the editing functionalities and effects should be possible to apply to sequencer content.

We should also take advantage of this new architecture to compensate for the difficulty in correctly timing a loop in play mode—if the user records a loop with a timing that it slightly off, we should be able to trim silence at the end or adjust the length of a note. This might be tricky, as a loop recording during play mode won't necessarily map onto the bar/timing structure of the sequencer view. This is part of why we need to examine the architecture.

We also want to be able to modify notes already placed in the sequencer in the following ways:
- changing their key, octave, etc, without changing the chord number
- adding effects (reverb, chorus, etc) with any of the normal fine-tuning available already
- changing them "in-place" by playing a note via the same interface as the play view and setting that played sound into place in the sequencer

Furthermore, we want to be able to "live-record" into the sequencer by pressing chord keys in sequence and having each be placed into the sequencer chits in the same order. 

More broadly, we need a more sophisticated view of timing and bars in the sequencer, as it relates to both layering multiple sounds over one another and to extending the length of a note to fit different time signatures. Essentially, we want to be able to encode as much of the timing information one would find on sheet music into the sequencer view.

We also want to be able to get better sound out of multiple layers when playing over loops or creating densely layered sequences, but this is a question of the audio engine, not the sequencer logic, so it's OK to accept degraded sound quality or less-than-optimal sound quality while finalizing the implementation of this new sequencer functionality, since we'll be refining and recreating the audio engine after this, not before.