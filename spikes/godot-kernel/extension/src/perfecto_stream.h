// The kernel as a Godot audio stream: Godot's mixing thread calls the
// playback's `_mix`, which renders the kernel straight into Godot's buffer.
// Nothing written in a script ever runs on that thread.
//
//     game thread                         Godot's mixing thread
//     GDScript → note_on/off/change ──→   PerfectoPlayback::_mix
//                (perfecto_kernel_send)      → perfecto_kernel_render
//                                            → one MixRecord per call ──→ stats
//
// The stream owns the kernel and the patches it was given. It has one
// playback at a time: the kernel has one clock.

#ifndef PERFECTO_STREAM_H
#define PERFECTO_STREAM_H

#include "PerfectoKernel.h"
#include "mix_ring.h"

#include <godot_cpp/classes/audio_stream.hpp>
#include <godot_cpp/classes/audio_stream_playback.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include <atomic>
#include <vector>

namespace perfecto_godot {

class PerfectoStream : public godot::AudioStream {
    GDCLASS(PerfectoStream, godot::AudioStream)

public:
    PerfectoStream();
    ~PerfectoStream() override;

    godot::Ref<godot::AudioStreamPlayback> _instantiate_playback() const override;
    godot::String _get_stream_name() const override { return "Perfecto kernel"; }
    bool _is_monophonic() const override { return true; }

    // Sounds: a preset's patch, as `dump-presets` writes it.
    void set_sound(int sound, const godot::Dictionary &patch);
    int sound_count() const;

    // The mix every note shares.
    void set_mix(float chorus_rate, float reverb_tail, float reverb_predelay, float reverb_damping,
                 float delay_time, float delay_feedback);

    // Notes. `frame` 0 is as soon as possible; -1 is the lead from now
    // (`set_lead_frames`), so every note so sent is as late as every other.
    bool note_on(int64_t id, int note, float velocity, int sound, float pan, float reverb, int64_t frame);
    bool note_off(int64_t id, int64_t frame);
    bool note_change(int64_t id, float brightness, float level, float reverb);

    // The kernel's clock and what the mixing thread has done since asked.
    int64_t time() const;
    /// The kernel frame being heard about now, by the latest render's
    /// start, as the game thread can best tell it.
    int64_t frame_now() const;
    void set_lead_frames(int frames) { lead = frames; }
    int latency_frames() const;
    double sample_rate() const { return rate; }
    godot::Dictionary take_mix_stats();

    // Renders `seconds` of `voices` held notes of `sound` offline, on a
    // kernel of its own, and says what it cost.
    godot::Dictionary benchmark(int sound, int voices, double seconds, int block) const;

    // For the playback.
    void prepare(double sample_rate);
    void render(godot::AudioFrame *buffer, int32_t frames);

protected:
    static void _bind_methods();

private:
    PerfectoKernel *kernel;
    std::vector<PerfectoPatch> patches;
    double rate = 0;
    /// Planar scratch for the kernel, set aside before rendering starts.
    std::vector<float> left, right;
    MixRing ring;
    /// When the latest note was sent (steady clock, ns), for the mixing
    /// thread to say how long it waited for a render: 0 once taken.
    std::atomic<int64_t> sent_at{0};
    /// The frame the latest note sent with the lead was stamped for: -1
    /// once its render has taken it.
    std::atomic<int64_t> stamped{-1};
    int64_t lead = 0;
    /// When the latest render began and at what frame, for `frame_now`:
    /// written under `clock_seq`, odd while being written.
    std::atomic<uint32_t> clock_seq{0};
    std::atomic<int64_t> clock_start{0};
    std::atomic<uint64_t> clock_frame{0};
    bool send(const PerfectoEvent &event);
    int64_t waited(int64_t start, uint64_t frame, int32_t frames);
};

class PerfectoPlayback : public godot::AudioStreamPlayback {
    GDCLASS(PerfectoPlayback, godot::AudioStreamPlayback)

public:
    void _start(double from_pos) override { playing = true; }
    void _stop() override { playing = false; }
    bool _is_playing() const override { return playing; }
    int32_t _mix(godot::AudioFrame *buffer, float rate_scale, int32_t frames) override;

    godot::Ref<PerfectoStream> stream;

protected:
    static void _bind_methods() {}

private:
    bool playing = false;
};

} // namespace perfecto_godot

#endif
