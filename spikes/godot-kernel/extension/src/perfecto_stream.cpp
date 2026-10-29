#include "perfecto_stream.h"

#include <godot_cpp/classes/audio_server.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>
#include <chrono>
#include <cmath>

using namespace godot;

namespace perfecto_godot {

namespace {

/// The most frames the kernel renders in one call; a longer ask is split.
constexpr int32_t scratchFrames = 4096;

int64_t now_ns() {
    return std::chrono::duration_cast<std::chrono::nanoseconds>(
               std::chrono::steady_clock::now().time_since_epoch())
        .count();
}

float number(const Dictionary &d, const char *key) { return float(double(d.get(key, 0.0))); }

PerfectoSweep sweep(const Dictionary &d) {
    return {number(d, "from"), number(d, "to"), number(d, "time")};
}

PerfectoOperator op(const Dictionary &d) {
    PerfectoOperator o{};
    o.wave = PerfectoWave(int(d.get("wave", 0)));
    o.pulse_width = number(d, "pulse_width");
    const Array partials = d.get("partials", Array());
    for (int i = 0; i < PerfectoPartialCount && i < partials.size(); ++i) o.partials[i] = float(double(partials[i]));
    o.ratio = number(d, "ratio");
    o.level = number(d, "level");
    return o;
}

PerfectoPatch patch(const Dictionary &d) {
    PerfectoPatch p{};
    const Array ops = d.get("operators", Array());
    for (int i = 0; i < PerfectoOperatorCount && i < ops.size(); ++i) p.operators[i] = op(ops[i]);
    p.modulates = bool(d.get("modulates", false));
    p.index = sweep(d.get("index", Dictionary()));
    p.unison = int32_t(int(d.get("unison", 0)));
    p.spread = number(d, "spread");
    p.drift = number(d, "drift");
    p.noise = sweep(d.get("noise", Dictionary()));
    p.glide = number(d, "glide");
    p.filtered = bool(d.get("filtered", false));
    p.cutoff = sweep(d.get("cutoff", Dictionary()));
    p.resonance = number(d, "resonance");
    p.steep = bool(d.get("steep", false));
    p.drive = number(d, "drive");
    const Dictionary lfo = d.get("lfo", Dictionary());
    p.lfo = {number(lfo, "rate"), number(lfo, "rise"), number(lfo, "pitch"), number(lfo, "pulse_width"),
             number(lfo, "cutoff")};
    p.attack = number(d, "attack");
    p.decay = number(d, "decay");
    p.sustain = number(d, "sustain");
    p.release = number(d, "release");
    p.level = number(d, "level");
    p.sampled = bool(d.get("sampled", false));
    p.capture = int32_t(int(d.get("capture", 0)));
    p.root = number(d, "root");
    p.additive = bool(d.get("additive", false));
    return p;
}

PerfectoEvent event(PerfectoEventType type, int64_t id, uint64_t frame) {
    PerfectoEvent e{};
    e.type = type;
    e.note_id = uint64_t(id);
    e.time = frame;
    e.brightness = 1;
    e.level = 1;
    return e;
}

} // namespace

PerfectoStream::PerfectoStream()
    : kernel(perfecto_kernel_create()), left(scratchFrames), right(scratchFrames) {}

PerfectoStream::~PerfectoStream() { perfecto_kernel_destroy(kernel); }

Ref<AudioStreamPlayback> PerfectoStream::_instantiate_playback() const {
    auto *self = const_cast<PerfectoStream *>(this);
    self->prepare(AudioServer::get_singleton()->get_mix_rate());
    Ref<PerfectoPlayback> playback;
    playback.instantiate();
    playback->stream = Ref<PerfectoStream>(self);
    return playback;
}

void PerfectoStream::prepare(double sample_rate) {
    rate = sample_rate;
    perfecto_kernel_prepare(kernel, sample_rate);
}

void PerfectoStream::set_sound(int sound, const Dictionary &d) {
    const PerfectoPatch p = patch(d);
    if (sound >= int(patches.size())) patches.resize(sound + 1);
    patches[sound] = p;
    perfecto_kernel_set_sound(kernel, sound, &p);
}

int PerfectoStream::sound_count() const { return perfecto_kernel_sound_count(); }

void PerfectoStream::set_mix(float chorus_rate, float reverb_tail, float reverb_predelay, float reverb_damping,
                             float delay_time, float delay_feedback) {
    perfecto_kernel_set_chorus_rate(kernel, chorus_rate);
    perfecto_kernel_set_reverb_tail(kernel, reverb_tail);
    perfecto_kernel_set_reverb_predelay(kernel, reverb_predelay);
    perfecto_kernel_set_reverb_damping(kernel, reverb_damping);
    perfecto_kernel_set_delay_time(kernel, delay_time);
    perfecto_kernel_set_delay_feedback(kernel, delay_feedback);
}

bool PerfectoStream::send(const PerfectoEvent &e) {
    if (e.time == 0) sent_at.store(now_ns(), std::memory_order_release);
    return perfecto_kernel_send(kernel, &e);
}

bool PerfectoStream::note_on(int64_t id, int note, float velocity, int sound, float pan, float reverb,
                             int64_t frame) {
    if (frame < 0) {
        frame = frame_now() + lead;
        sent_at.store(now_ns(), std::memory_order_release);
        stamped.store(frame, std::memory_order_release);
    }
    PerfectoEvent e = event(PerfectoEventNoteOn, id, uint64_t(frame));
    e.note = note;
    e.velocity = velocity;
    e.sound = sound;
    e.pan = pan;
    e.reverb = reverb;
    return send(e);
}

bool PerfectoStream::note_off(int64_t id, int64_t frame) {
    const PerfectoEvent e = event(PerfectoEventNoteOff, id, uint64_t(frame));
    return perfecto_kernel_send(kernel, &e);
}

bool PerfectoStream::note_change(int64_t id, float brightness, float level, float reverb) {
    PerfectoEvent e = event(PerfectoEventNoteChange, id, 0);
    e.brightness = brightness;
    e.level = level;
    e.reverb = reverb;
    return perfecto_kernel_send(kernel, &e);
}

int64_t PerfectoStream::time() const { return int64_t(perfecto_kernel_time(kernel)); }

int64_t PerfectoStream::frame_now() const {
    for (;;) {
        const uint32_t seq = clock_seq.load(std::memory_order_acquire);
        if (seq & 1) continue;
        const int64_t start = clock_start.load(std::memory_order_acquire);
        const uint64_t frame = clock_frame.load(std::memory_order_acquire);
        if (clock_seq.load(std::memory_order_acquire) != seq) continue;
        if (!start) return 0;
        return int64_t(frame) + int64_t(double(now_ns() - start) * rate / 1e9);
    }
}

/// How long the latest note waited for its frame to be rendered, if this
/// render is the one: -1 if no note is waiting on it, -2 if its frame had
/// already been rendered (it is late, and sounds at once).
int64_t PerfectoStream::waited(int64_t start, uint64_t frame, int32_t frames) {
    const int64_t target = stamped.load(std::memory_order_acquire);
    if (target >= 0) {
        if (target >= int64_t(frame + frames)) return -1;
        stamped.store(-1, std::memory_order_release);
        const int64_t sent = sent_at.exchange(0, std::memory_order_acq_rel);
        if (target < int64_t(frame)) return -2;
        return start + int64_t(double(target - int64_t(frame)) / rate * 1e9) - sent;
    }
    const int64_t sent = sent_at.exchange(0, std::memory_order_acq_rel);
    return sent ? start - sent : -1;
}

int PerfectoStream::latency_frames() const { return perfecto_kernel_latency(kernel); }

void PerfectoStream::render(AudioFrame *buffer, int32_t frames) {
    const int64_t start = now_ns();
    const uint64_t frame = perfecto_kernel_time(kernel);
    clock_seq.fetch_add(1, std::memory_order_acq_rel);
    clock_start.store(start, std::memory_order_release);
    clock_frame.store(frame, std::memory_order_release);
    clock_seq.fetch_add(1, std::memory_order_acq_rel);
    const int64_t wait = waited(start, frame, frames);
    for (int32_t done = 0; done < frames;) {
        const int32_t n = std::min(frames - done, scratchFrames);
        float *out[2] = {left.data(), right.data()};
        perfecto_kernel_render(kernel, nullptr, 0, out, 2, n);
        for (int32_t i = 0; i < n; ++i) buffer[done + i] = {left[i], right[i]};
        done += n;
    }
    const int64_t end = now_ns();
    ring.push({start, end - start, frame, frames, wait});
}

Dictionary PerfectoStream::take_mix_stats() {
    int64_t calls = 0, frames = 0, minFrames = INT64_MAX, maxFrames = 0;
    int64_t renderSum = 0, renderMax = 0, lastStart = 0, intervalMax = 0, intervalMin = INT64_MAX;
    double loadMax = 0;
    int64_t late = 0;
    Array waits;
    ring.drain([&](const MixRecord &r) {
        ++calls;
        frames += r.frames;
        minFrames = std::min<int64_t>(minFrames, r.frames);
        maxFrames = std::max<int64_t>(maxFrames, r.frames);
        renderSum += r.render;
        renderMax = std::max(renderMax, r.render);
        loadMax = std::max(loadMax, double(r.render) / (r.frames / rate * 1e9));
        if (lastStart) {
            intervalMax = std::max(intervalMax, r.start - lastStart);
            intervalMin = std::min(intervalMin, r.start - lastStart);
        }
        lastStart = r.start;
        if (r.waited >= 0) waits.push_back(r.waited / 1e6);
        if (r.waited == -2) ++late;
    });
    Dictionary d;
    d["calls"] = calls;
    d["frames"] = frames;
    d["block_min"] = calls ? minFrames : 0;
    d["block_max"] = maxFrames;
    d["interval_min_ms"] = intervalMin == INT64_MAX ? 0.0 : intervalMin / 1e6;
    d["interval_max_ms"] = intervalMax / 1e6;
    d["render_mean_us"] = calls ? renderSum / 1e3 / calls : 0.0;
    d["render_max_us"] = renderMax / 1e3;
    d["load"] = frames ? double(renderSum) / (frames / rate * 1e9) : 0.0;
    d["load_max"] = loadMax;
    d["waits_ms"] = waits;
    d["late"] = late;
    return d;
}

Dictionary PerfectoStream::benchmark(int sound, int voices, double seconds, int block) const {
    PerfectoKernel *k = perfecto_kernel_create();
    const double sampleRate = 48000;
    perfecto_kernel_prepare(k, sampleRate);
    if (sound < int(patches.size())) perfecto_kernel_set_sound(k, sound, &patches[sound]);
    for (int v = 0; v < voices; ++v) {
        PerfectoEvent e = event(PerfectoEventNoteOn, v + 1, 0);
        e.note = 36 + (v * 7) % 60;
        e.velocity = 0.7f;
        e.sound = sound;
        e.pan = (v % 2 ? 0.3f : -0.3f);
        e.reverb = 0.16f;
        perfecto_kernel_send(k, &e);
    }
    std::vector<float> l(block), r(block);
    float *out[2] = {l.data(), r.data()};
    const int64_t total = int64_t(seconds * sampleRate);
    // A first second unmeasured, so attacks and caches settle.
    for (int64_t f = 0; f < int64_t(sampleRate); f += block) perfecto_kernel_render(k, nullptr, 0, out, 2, block);
    int64_t worst = 0;
    const int64_t start = now_ns();
    for (int64_t f = 0; f < total; f += block) {
        const int64_t t = now_ns();
        perfecto_kernel_render(k, nullptr, 0, out, 2, block);
        worst = std::max(worst, now_ns() - t);
    }
    const int64_t elapsed = now_ns() - start;
    perfecto_kernel_destroy(k);
    Dictionary d;
    d["ns_per_frame"] = double(elapsed) / total;
    d["load"] = double(elapsed) / (seconds * 1e9);
    d["worst_block_load"] = double(worst) / (block / sampleRate * 1e9);
    return d;
}

void PerfectoStream::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_sound", "sound", "patch"), &PerfectoStream::set_sound);
    ClassDB::bind_method(D_METHOD("sound_count"), &PerfectoStream::sound_count);
    ClassDB::bind_method(D_METHOD("set_mix", "chorus_rate", "reverb_tail", "reverb_predelay", "reverb_damping",
                                  "delay_time", "delay_feedback"),
                         &PerfectoStream::set_mix);
    ClassDB::bind_method(D_METHOD("note_on", "id", "note", "velocity", "sound", "pan", "reverb", "frame"),
                         &PerfectoStream::note_on);
    ClassDB::bind_method(D_METHOD("note_off", "id", "frame"), &PerfectoStream::note_off);
    ClassDB::bind_method(D_METHOD("note_change", "id", "brightness", "level", "reverb"), &PerfectoStream::note_change);
    ClassDB::bind_method(D_METHOD("time"), &PerfectoStream::time);
    ClassDB::bind_method(D_METHOD("frame_now"), &PerfectoStream::frame_now);
    ClassDB::bind_method(D_METHOD("set_lead_frames", "frames"), &PerfectoStream::set_lead_frames);
    ClassDB::bind_method(D_METHOD("latency_frames"), &PerfectoStream::latency_frames);
    ClassDB::bind_method(D_METHOD("sample_rate"), &PerfectoStream::sample_rate);
    ClassDB::bind_method(D_METHOD("take_mix_stats"), &PerfectoStream::take_mix_stats);
    ClassDB::bind_method(D_METHOD("benchmark", "sound", "voices", "seconds", "block"), &PerfectoStream::benchmark);
}

int32_t PerfectoPlayback::_mix(AudioFrame *buffer, float, int32_t frames) {
    if (!playing || stream.is_null()) {
        std::fill(buffer, buffer + frames, AudioFrame{0, 0});
        return frames;
    }
    stream->render(buffer, frames);
    return frames;
}

} // namespace perfecto_godot
