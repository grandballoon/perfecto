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
//  - `perfecto_kernel_time`, the chorus's and reverb's settings, and what
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
///         → low-pass filter → amplitude envelope → the note's brightness
///
/// From there a note goes where it says (its pan, and how much of it to the
/// chorus and the reverb), and everything is added and held under full
/// scale by a limiter.
typedef struct {
    PerfectoOperator operators[PerfectoOperatorCount];
    /// The second operator bends the first one's phase by `index` (in
    /// radians, as an FM index) and is not heard itself. Otherwise the two
    /// are mixed, sharing `level` by their own levels.
    bool modulates;
    PerfectoSweep index;
    bool filtered;
    /// The filter's cutoff as a multiple of the note's frequency, so a
    /// patch is as bright in every octave.
    PerfectoSweep cutoff;
    /// 0 (none) up to 1 (ringing).
    float resonance;
    /// The filter falls away at 24 dB an octave above its cutoff, not 12:
    /// a darker, rounder sound for the same cutoff.
    bool steep;
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
    /// `brightness`, `chorus` and `reverb`, all three. The change is glided
    /// to, not jumped to.
    PerfectoEventNoteChange = 3,
    /// Starts recording the input into the capture numbered `note`, from
    /// this frame, in place of what it held; notes playing it end. One
    /// capture is recorded at a time: starting another ends the first.
    PerfectoEventCaptureStart = 4,
    /// Ends the recording at this frame (it ends by itself when the capture
    /// is full), and makes it playable.
    PerfectoEventCaptureStop = 5,
} PerfectoEventType;

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
