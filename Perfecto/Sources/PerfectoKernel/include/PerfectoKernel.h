// The audio kernel: everything Perfecto sounds for itself is rendered here.
//
// Its whole input is timed events and the audio input (a mic); its output
// is samples. It is plain C++ behind this C interface, with nothing from any
// platform in it, so the same kernel runs in the iOS app, in tests on a Mac,
// and wherever else it is compiled.
//
// Threads:
//  - `perfecto_kernel_render` is the render thread's. It never allocates,
//    locks or waits.
//  - `perfecto_kernel_send` is for one other thread at a time.
//  - `perfecto_kernel_time`, the chorus's, reverb's and vocoder's settings, and what
//    says how a capture is getting on are for any thread.
//  - Everything else is called while nothing is rendering.
//
// Time is a count of frames rendered since the kernel was prepared. An event
// takes effect on exactly the frame it names, however the frames are divided
// into render calls. An event whose frame has already been rendered takes
// effect on the next frame rendered, so time 0 means "as soon as possible".

#ifndef PERFECTO_KERNEL_H
#define PERFECTO_KERNEL_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PerfectoKernel PerfectoKernel;

// MARK: Sounds

/// A value that moves from `from` to `to` over `time` seconds after a note
/// starts, then stays there.
typedef struct {
    float from;
    float to;
    float time;
} PerfectoSweep;

/// A slow wave that moves a patch's sound for as long as a note sounds: a
/// sine of `rate` Hz that starts with the note, from nothing, and comes up
/// to its full depth over `rise` seconds. Each depth is how far it moves
/// one thing either way; 0 leaves that thing alone, and a `rate` of 0 is no
/// wave at all.
typedef struct {
    float rate;
    float rise;
    /// The operators' pitch, in cents: vibrato.
    float pitch;
    /// The width of every pulse wave, as a share of its cycle.
    float pulse_width;
    /// The filter's cutoff, in octaves.
    float cutoff;
} PerfectoLfo;

typedef enum {
    PerfectoWaveSine = 0,
    PerfectoWaveTriangle,
    PerfectoWaveSquare,
    PerfectoWaveSawtooth,
    /// High for `pulse_width` of each cycle.
    PerfectoWavePulse,
    /// The sine partials in `partials`.
    PerfectoWavePartials,
} PerfectoWave;

enum {
    /// The operators in a patch.
    PerfectoOperatorCount = 2,
    /// The most partials a `PerfectoWavePartials` wave can name.
    PerfectoPartialCount = 16,
    /// The most copies of its operators a patch can sound at once.
    PerfectoUnisonCount = 7,
};

/// One of a patch's two sources: a wave at a multiple of the note's pitch.
typedef struct {
    PerfectoWave wave;
    /// For `PerfectoWavePulse`: 0...1.
    float pulse_width;
    /// For `PerfectoWavePartials`: each partial's strength, the fundamental
    /// first. The wave is scaled to peak at 1, as the others do.
    float partials[PerfectoPartialCount];
    /// Its frequency as a multiple of the note's.
    float ratio;
    /// Its strength beside the other operator's. 0 is an operator not used.
    float level;
} PerfectoOperator;

/// What one sound is made of. Every voice has the same path, and a patch
/// says which parts sound and how:
///
///     operator 2 ──(modulates, or is mixed with)──→ operator 1
///         (+ noise) → low-pass filter → drive → amplitude envelope
///         → the note's brightness
///
/// and an LFO that moves the operators' pitch, their pulse width and the
/// filter's cutoff. The operators can be several copies of themselves a
/// little out of tune with each other (`unison`), and can wander a little
/// from their pitch, each note its own way (`drift`).
///
/// From there a note goes where it says (its pan, and how much of it to the
/// chorus, the reverb and the vocoder), and everything is added and held
/// under full scale by a limiter.
typedef struct {
    PerfectoOperator operators[PerfectoOperatorCount];
    /// The second operator bends the first one's phase by `index` (in
    /// radians, as an FM index) and is not heard itself. Otherwise the two
    /// are mixed, sharing `level` by their own levels.
    bool modulates;
    PerfectoSweep index;
    /// How many copies of the operators sound at once, 1 (and 0) being the
    /// operators alone, up to `PerfectoUnisonCount`. The copies are tuned
    /// evenly from `spread` cents under the note to `spread` over it, and
    /// together are as loud as one.
    int32_t unison;
    float spread;
    /// How far, in cents, each operator wanders either side of its pitch:
    /// slowly, and differently for every note, so no two notes are tuned
    /// quite alike, as an analog synth's are not. The operators of a patch
    /// that `modulates` wander together.
    float drift;
    /// Noise beside the operators, as loud as this share of `level`: swept
    /// down it is the breath at the start of a blown note, and steady it is
    /// air in the sound. 0 is none.
    PerfectoSweep noise;
    /// Seconds in which a note covers 63% of the way to its pitch from the
    /// pitch of the note before it, when it follows that note with no gap
    /// (the nearest in pitch of the notes of this sound that ended just
    /// as it started). 0 is every note at its own pitch from the start.
    float glide;
    bool filtered;
    /// The filter's cutoff as a multiple of the note's frequency, so a
    /// patch is as bright in every octave.
    PerfectoSweep cutoff;
    /// 0 (none) up to 1 (ringing).
    float resonance;
    /// The filter falls away at 24 dB an octave above its cutoff, not 12:
    /// a darker, rounder sound for the same cutoff.
    bool steep;
    /// How hard what the filter lets through is pushed into a soft limit
    /// of its own, from 0 (not at all) to 1: the sound flattens and grows
    /// partials, and stays about as loud.
    float drive;
    PerfectoLfo lfo;
    /// Seconds to reach full level.
    float attack;
    /// Seconds in which the level covers 63% of the way to `sustain`, and
    /// after the note ends to silence (time constants: a struck sound with
    /// no sustain is 60 dB down after seven of them).
    float decay;
    float sustain;
    float release;
    /// One note's level at full velocity. Notes add.
    float level;
    /// The sound is a capture and not the operators: the recording numbered
    /// `capture`, played as it was recorded by the note `root` and faster or
    /// slower by every other, through the same filter and envelope. A note
    /// ends when the recording does, if it has not been ended sooner.
    bool sampled;
    int32_t capture;
    float root;
} PerfectoPatch;

// MARK: Events

typedef enum {
    /// Starts a note under `note_id`, which no sounding note has.
    PerfectoEventNoteOn = 1,
    /// Ends the note `note_id`. Unknown ids are ignored.
    PerfectoEventNoteOff = 2,
    /// Changes how the note `note_id` is played while it sounds: its
    /// `brightness`, `chorus`, `reverb`, `vocoder`, `delay`, `bend` and
    /// `level`, all seven. The change is glided to, not jumped to.
    PerfectoEventNoteChange = 3,
    /// Starts recording into the capture numbered `note`, from this frame,
    /// in place of what it held; notes playing it end. What is recorded is
    /// the source numbered `sound` (a `PerfectoCaptureSource`). One capture
    /// is recorded at a time: starting another ends the first.
    PerfectoEventCaptureStart = 4,
    /// Ends the recording at this frame (it ends by itself when the capture
    /// is full), and makes it playable.
    PerfectoEventCaptureStop = 5,
} PerfectoEventType;

/// What a capture records.
typedef enum {
    /// The audio input.
    PerfectoCaptureInput = 0,
    /// What the vocoder puts out.
    PerfectoCaptureVocoder = 1,
} PerfectoCaptureSource;

typedef struct {
    /// The frame the event takes effect on.
    uint64_t time;
    /// The sender's name for the note.
    uint64_t note_id;
    PerfectoEventType type;
    /// Note on: the MIDI note, 0...127. Capture start: which capture.
    int32_t note;
    /// Note on: how hard it was struck, 0...1.
    float velocity;
    /// Note on: which sound, as numbered by `perfecto_kernel_set_sound`.
    /// Capture start: what to record.
    int32_t sound;
    /// Note on and note change: the note's own low-pass, from 0 (dark) to 1
    /// (open: the sound as its patch makes it).
    float brightness;
    /// Note on: where the note is between left (-1) and right (1).
    float pan;
    /// Note on and note change: how much chorus the note has, from 0 (none)
    /// to 1 (as much wavering copy as sound).
    float chorus;
    /// Note on and note change: how much of the note goes into the reverb
    /// and not straight out, from 0 (dry) to 1 (the room alone). It is a
    /// send: turning it down never cuts what is already ringing.
    float reverb;
    /// Note on and note change: how much of the note goes to the vocoder,
    /// to be shaped by the voice at the input, and is not heard itself:
    /// from 0 (none) to 1 (all of it). While the vocoder is off, none does.
    float vocoder;
    /// Note on and note change: how much of the note is echoed, from 0
    /// (none) to 1 (the first echo as loud as the note). It is a send: the
    /// note is heard as it was, and turning it down never cuts the echoes
    /// already on their way.
    float delay;
    /// Note on and note change: how far the note is from the pitch of
    /// `note`, in semitones up (or, below 0, down). A note changed little
    /// and often is heard to slide.
    float bend;
    /// Note on and note change: how loud the note is beside the same note
    /// played whole, from 0 (silent) to 1.
    float level;
} PerfectoEvent;

/// The most notes that can be held at once. A note past this takes over a
/// voice: the quietest one already released, or else the one held longest.
int32_t perfecto_kernel_voice_count(void);

/// The most events that can be waiting for their time at once.
int32_t perfecto_kernel_event_capacity(void);

PerfectoKernel *perfecto_kernel_create(void);
void perfecto_kernel_destroy(PerfectoKernel *kernel);

/// Makes the kernel ready to render at `sample_rate`: silent, nothing
/// waiting, time 0. Its sounds and captures are kept; a recording under
/// way is ended.
void perfecto_kernel_prepare(PerfectoKernel *kernel, double sample_rate);

/// The most sounds the kernel holds, numbered from 0.
int32_t perfecto_kernel_sound_count(void);

/// Makes `patch` sound number `sound`. Its waves are built here, so this
/// takes a moment and allocates: it is for loading sounds before playing,
/// while nothing is rendering. A number never set plays a plain sine.
void perfecto_kernel_set_sound(PerfectoKernel *kernel, int32_t sound, const PerfectoPatch *patch);

// MARK: Captures

/// How many captures the kernel holds, numbered from 0, and the most frames
/// each can hold. Their memory is set aside when the kernel is made.
int32_t perfecto_kernel_capture_count(void);
int32_t perfecto_kernel_capture_capacity(void);

/// The capture being recorded into, or -1.
int32_t perfecto_kernel_capturing(const PerfectoKernel *kernel);

/// How many recordings have ended since the kernel was made: by a stop, by
/// filling up, or by the kernel being prepared again. A sender that noted
/// the count when it asked for a recording knows it is over, and playable,
/// when the count has moved.
uint32_t perfecto_kernel_captures_ended(const PerfectoKernel *kernel);

/// Frames of `capture` that notes play: 0 while it is empty or being
/// recorded. What is played is the recording from just before its first
/// sound to just after its last, with any steady offset taken out, brought
/// up to full level.
int32_t perfecto_kernel_capture_length(const PerfectoKernel *kernel, int32_t capture);

/// The sample rate `capture` was recorded at.
double perfecto_kernel_capture_rate(const PerfectoKernel *kernel, int32_t capture);

/// Copies what notes play of `capture` into `out`, which has room for
/// `room` frames, and returns the frames copied. Not while it is recorded.
int32_t perfecto_kernel_capture_read(const PerfectoKernel *kernel, int32_t capture, float *out, int32_t room);

/// Makes `frames` frames of `samples`, recorded at `sample_rate`, what
/// `capture` holds, played as they are. For loading a recording kept from
/// before, while nothing is rendering.
void perfecto_kernel_capture_load(PerfectoKernel *kernel, int32_t capture,
                                  const float *samples, int32_t frames, double sample_rate);

// MARK: The mix

/// The settings every note shares: how fast the chorus wavers, in Hz; the
/// seconds the reverb's tail takes to fall 60 dB; the seconds before the
/// room first answers (a bigger room is further away); and the pitch, in
/// Hz, above which the tail dies sooner (a softer room is duller).
void perfecto_kernel_set_chorus_rate(PerfectoKernel *kernel, float hz);
void perfecto_kernel_set_reverb_tail(PerfectoKernel *kernel, float seconds);
void perfecto_kernel_set_reverb_predelay(PerfectoKernel *kernel, float seconds);
void perfecto_kernel_set_reverb_damping(PerfectoKernel *kernel, float hz);

/// The delay's settings, which every note shares too: the seconds between
/// one echo and the next (a change is glided to, and the echoes on their
/// way bend in pitch meanwhile), and how loud each echo is beside the one
/// before it, from 0 (one echo) up to a little under 1.
void perfecto_kernel_set_delay_time(PerfectoKernel *kernel, float seconds);
void perfecto_kernel_set_delay_feedback(PerfectoKernel *kernel, float share);

/// Switches the vocoder on or off. On, the share of each note sent to it
/// is shaped by the audio input (a voice) and heard that way in place of
/// the note; off, every note is heard whole, as if none were sent.
void perfecto_kernel_set_vocoder(PerfectoKernel *kernel, bool on);

/// Frames between an event's frame and its sound coming out: the limiter
/// has to see a peak coming to turn it down in time. Fixed by `prepare`.
int32_t perfecto_kernel_latency(const PerfectoKernel *kernel);

/// Hands the kernel an event. Returns false, and drops the event, if as
/// many as it can hold are already waiting for their frames.
bool perfecto_kernel_send(PerfectoKernel *kernel, const PerfectoEvent *event);

/// Frames rendered so far.
uint64_t perfecto_kernel_time(const PerfectoKernel *kernel);

/// Renders the next `frames` frames into `out`, one array per channel.
/// `in` is the audio input in the same layout; NULL is silence. Its
/// channels are averaged into one.
void perfecto_kernel_render(PerfectoKernel *kernel,
                            const float *const *in, int32_t in_channels,
                            float *const *out, int32_t out_channels,
                            int32_t frames);

#ifdef __cplusplus
}
#endif

#endif
