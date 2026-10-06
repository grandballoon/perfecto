// The audio kernel: everything Perfecto sounds for itself is rendered here.
//
// Its whole input is timed events (and, later, the mic's audio); its output
// is samples. It is plain C++ behind this C interface, with nothing from any
// platform in it, so the same kernel runs in the iOS app, in tests on a Mac,
// and wherever else it is compiled.
//
// Threads:
//  - `perfecto_kernel_render` is the render thread's. It never allocates,
//    locks or waits.
//  - `perfecto_kernel_send` is for one other thread at a time.
//  - `perfecto_kernel_time` is for any thread.
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

typedef enum {
    /// Starts a note under `note_id`, which no sounding note has.
    PerfectoEventNoteOn = 1,
    /// Ends the note `note_id`. Unknown ids are ignored.
    PerfectoEventNoteOff = 2,
} PerfectoEventType;

typedef struct {
    /// The frame the event takes effect on.
    uint64_t time;
    /// The sender's name for the note.
    uint64_t note_id;
    PerfectoEventType type;
    /// Note on: the MIDI note, 0...127.
    int32_t note;
    /// Note on: how hard it was struck, 0...1.
    float velocity;
} PerfectoEvent;

/// The most notes that can be held at once. A note past this takes over a
/// voice: the quietest one already released, or else the one held longest.
int32_t perfecto_kernel_voice_count(void);

/// The most events that can be waiting for their time at once.
int32_t perfecto_kernel_event_capacity(void);

PerfectoKernel *perfecto_kernel_create(void);
void perfecto_kernel_destroy(PerfectoKernel *kernel);

/// Makes the kernel ready to render at `sample_rate`: silent, nothing
/// waiting, time 0.
void perfecto_kernel_prepare(PerfectoKernel *kernel, double sample_rate);

/// Hands the kernel an event. Returns false, and drops the event, if as
/// many as it can hold are already waiting for their frames.
bool perfecto_kernel_send(PerfectoKernel *kernel, const PerfectoEvent *event);

/// Frames rendered so far.
uint64_t perfecto_kernel_time(const PerfectoKernel *kernel);

/// Renders the next `frames` frames into `out`, one array per channel.
/// `in` is the audio input in the same layout; NULL is silence.
void perfecto_kernel_render(PerfectoKernel *kernel,
                            const float *const *in, int32_t in_channels,
                            float *const *out, int32_t out_channels,
                            int32_t frames);

#ifdef __cplusplus
}
#endif

#endif
