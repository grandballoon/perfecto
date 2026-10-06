#include "PerfectoKernel.h"

#include "EventQueue.hpp"
#include "RenderGuard.hpp"
#include "Voice.hpp"

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstddef>

namespace {

constexpr std::size_t voiceCount = 64;
constexpr std::size_t eventCapacity = 1024;
constexpr std::size_t soundCount = 64;

/// Seconds a voice takes to fade out when its note is taken. Short, but
/// not short enough to click.
constexpr double stealSeconds = 0.003;
/// The shortest an attack, decay or release may be, so none clicks.
constexpr double shortestSeconds = 0.002;
/// The level a note dying away is counted as silent at: 80 dB down.
constexpr float silent = 1e-4f;

/// A voice works out its slow-moving values (sweeps, filter tunings, the
/// glide of its brightness) once every this many frames of its note.
constexpr uint32_t controlFrames = 16;
/// Seconds in which a change of brightness covers 63% of the way: long
/// enough that a sliding finger is heard as a sweep and not as steps.
constexpr double brightnessGlide = 0.01;

/// The patch filter's working range, and the brightness filter's from dark
/// to open, in Hz. Both stay under the sample rate's own limit.
constexpr double lowestCutoff = 60;
constexpr double highestCutoff = 18000;
constexpr double darkest = 300;
constexpr double brightest = 20000;

constexpr double twoPi = 6.283185307179586;

double valueOf(const PerfectoSweep &sweep, double seconds) {
    if (sweep.time <= 0 || seconds >= sweep.time) return sweep.to;
    return sweep.from + (sweep.to - sweep.from) * seconds / sweep.time;
}

/// The share of the way to its goal a level moves each frame, to cover 63%
/// of it in `seconds`.
float rate(double seconds, double sampleRate) {
    return static_cast<float>(1 - std::exp(-1 / (std::max(seconds, shortestSeconds) * sampleRate)));
}

}

struct PerfectoKernel {
    double sampleRate = 48000;
    std::atomic<uint64_t> time{0};

    /// Events on their way to the render thread, and there waiting for
    /// their frames. `waiting` counts both, so neither can overflow.
    perfecto::Mailbox<eventCapacity> mailbox;
    perfecto::Agenda<eventCapacity> agenda;
    std::atomic<std::size_t> waiting{0};
    std::array<perfecto::Voice, voiceCount> voices{};
    uint64_t notesStarted = 0;

    /// The sounds notes name, and the one a number never set plays.
    std::array<perfecto::Sound, soundCount> sounds{};
    std::array<bool, soundCount> isSet{};
    perfecto::Sound plain;

    PerfectoKernel() {
        plain.load(perfecto::Sound::plainSine());
    }

    const perfecto::Sound &sound(int32_t number) const {
        const bool known = number >= 0 && static_cast<std::size_t>(number) < soundCount && isSet[number];
        return known ? sounds[number] : plain;
    }

    // MARK: Notes

    void start(perfecto::Voice &voice, const perfecto::Voice::Waiting &note) {
        using namespace perfecto;
        const Sound &sound = this->sound(note.sound);
        const PerfectoPatch &patch = sound.patch;
        voice.stage = Voice::Stage::held;
        voice.id = note.id;
        voice.startedAt = ++notesStarted;
        voice.sound = &sound;
        voice.hz = 440.0 * std::pow(2.0, (note.note - 69) / 12.0);
        voice.age = 0;
        voice.velocity = std::clamp(note.velocity, 0.0f, 1.0f);
        for (int i = 0; i < PerfectoOperatorCount; ++i) {
            voice.phase[i] = 0;
            voice.phaseStep[i] = voice.hz * patch.operators[i].ratio / sampleRate;
            voice.tableLevel[i] = Wavetable::level(voice.phaseStep[i]);
        }
        voice.envelope = Voice::Envelope::attack;
        voice.level = 0;
        // The attack heads past full level and stops there, so it arrives
        // on time and does not creep up to it.
        voice.attackRate = static_cast<float>(
            1 - std::exp(-std::log(attackGoal / (attackGoal - 1))
                         / (std::max<double>(patch.attack, shortestSeconds) * sampleRate)));
        voice.decayRate = rate(patch.decay, sampleRate);
        voice.releaseRate = rate(patch.release, sampleRate);
        voice.fade = 1;
        voice.fadeStep = 0;
        voice.filter.clear();
        voice.brightener.clear();
        // A note starts at the brightness it was played with, not on the
        // way to it.
        voice.brightness = voice.brightnessGoal = std::clamp(note.brightness, 0.0f, 1.0f);
    }

    /// The voice a new note takes: a free one, else the quietest of those
    /// dying away, else the one held longest.
    perfecto::Voice &voiceForNewNote() {
        using Stage = perfecto::Voice::Stage;
        perfecto::Voice *quietest = nullptr;
        perfecto::Voice *oldest = nullptr;
        for (auto &voice : voices) {
            if (voice.stage == Stage::free) return voice;
            if (voice.stage == Stage::released && (!quietest || voice.loudness() < quietest->loudness())) quietest = &voice;
            if (voice.stage == Stage::held && (!oldest || voice.startedAt < oldest->startedAt)) oldest = &voice;
        }
        if (quietest) return *quietest;
        if (oldest) return *oldest;
        // Every voice is already being taken: the note waiting longest loses its place.
        return *std::min_element(voices.begin(), voices.end(), [](const auto &a, const auto &b) {
            return a.startedAt < b.startedAt;
        });
    }

    void noteOn(const PerfectoEvent &event) {
        using Stage = perfecto::Voice::Stage;
        const perfecto::Voice::Waiting note{event.note_id, event.note, event.velocity, event.sound, event.brightness};
        auto &voice = voiceForNewNote();
        if (voice.stage == Stage::free) {
            start(voice, note);
            return;
        }
        // Whatever the voice is sounding is faded out first, so taking it
        // never clicks; the new note starts when that is done.
        voice.stage = Stage::stolen;
        voice.startedAt = ++notesStarted;
        voice.waiting = note;
        voice.fadeStep = static_cast<float>(1 / (stealSeconds * sampleRate));
    }

    void noteOff(const PerfectoEvent &event) {
        using Stage = perfecto::Voice::Stage;
        for (auto &voice : voices) {
            if (voice.stage == Stage::held && voice.id == event.note_id) {
                voice.stage = Stage::released;
                voice.envelope = perfecto::Voice::Envelope::release;
            } else if (voice.stage == Stage::stolen && voice.waiting.id == event.note_id) {
                // Ended before it began: the voice just finishes fading.
                voice.stage = Stage::released;
            }
        }
    }

    void noteChange(const PerfectoEvent &event) {
        using Stage = perfecto::Voice::Stage;
        const float brightness = std::clamp(event.brightness, 0.0f, 1.0f);
        for (auto &voice : voices) {
            if (voice.stage == Stage::held && voice.id == event.note_id) {
                voice.brightnessGoal = brightness;
            } else if (voice.stage == Stage::stolen && voice.waiting.id == event.note_id) {
                voice.waiting.brightness = brightness;
            }
        }
    }

    void apply(const PerfectoEvent &event) {
        switch (event.type) {
        case PerfectoEventNoteOn:     noteOn(event); break;
        case PerfectoEventNoteOff:    noteOff(event); break;
        case PerfectoEventNoteChange: noteChange(event); break;
        }
    }

    // MARK: Rendering

    /// Works out the values of `voice` that move slowly, for its next
    /// `controlFrames` frames.
    void control(perfecto::Voice &voice) {
        const PerfectoPatch &patch = voice.sound->patch;
        const double seconds = voice.age / sampleRate;
        const double ceiling = 0.45 * sampleRate;
        if (patch.modulates) {
            voice.bend = static_cast<float>(valueOf(patch.index, seconds) / twoPi);
        }
        if (patch.filtered) {
            const double cutoff = std::clamp(valueOf(patch.cutoff, seconds) * voice.hz,
                                             lowestCutoff, std::min(highestCutoff, ceiling));
            // Resonance 0 is flat; 1 rings.
            voice.filter.tune(cutoff, sampleRate, 0.7071 * std::pow(25.0, patch.resonance));
        }
        voice.brightness += (voice.brightnessGoal - voice.brightness) * brightnessRate;
        voice.brightener.tune(std::min(darkest * std::pow(brightest / darkest, voice.brightness), ceiling),
                              sampleRate, 0.7071);
    }

    /// One frame of `voice`'s sources.
    float source(perfecto::Voice &voice) {
        const perfecto::Sound &sound = *voice.sound;
        float sample = 0;
        if (sound.patch.modulates) {
            const float modulator = sound.waves[1].read(voice.tableLevel[1], voice.phase[1]);
            double bent = voice.phase[0] + voice.bend * modulator;
            bent -= std::floor(bent);
            sample = sound.gains[0] * sound.waves[0].read(voice.tableLevel[0], bent);
        } else {
            for (int i = 0; i < PerfectoOperatorCount; ++i) {
                if (sound.gains[i] == 0) continue;
                sample += sound.gains[i] * sound.waves[i].read(voice.tableLevel[i], voice.phase[i]);
            }
        }
        for (int i = 0; i < PerfectoOperatorCount; ++i) {
            voice.phase[i] += voice.phaseStep[i];
            voice.phase[i] -= std::floor(voice.phase[i]);
        }
        return sample;
    }

    /// Moves `voice`'s envelope on a frame. False once a note dying away
    /// has reached silence.
    bool advance(perfecto::Voice &voice) {
        using Envelope = perfecto::Voice::Envelope;
        switch (voice.envelope) {
        case Envelope::attack:
            voice.level += (attackGoal - voice.level) * voice.attackRate;
            if (voice.level >= 1) {
                voice.level = 1;
                voice.envelope = Envelope::decay;
            }
            return true;
        case Envelope::decay:
            voice.level += (voice.sound->patch.sustain - voice.level) * voice.decayRate;
            return true;
        case Envelope::release:
            voice.level -= voice.level * voice.releaseRate;
            return voice.level >= silent;
        }
        return true;
    }

    /// Adds `voice`'s next `frames` frames to `out`.
    void render(perfecto::Voice &voice, float *out, int32_t frames) {
        using Stage = perfecto::Voice::Stage;
        for (int32_t i = 0; i < frames; ++i) {
            if (voice.stage == Stage::free) return;
            if (voice.age % controlFrames == 0) control(voice);

            float sample = source(voice);
            if (voice.sound->patch.filtered) sample = voice.filter.run(sample);
            sample = voice.brightener.run(sample * voice.level * voice.velocity);
            out[i] += sample * voice.fade;
            ++voice.age;

            const bool sounding = advance(voice);
            if (voice.fadeStep > 0) {
                voice.fade -= voice.fadeStep;
                if (voice.fade <= 0) {
                    if (voice.stage == Stage::stolen) {
                        start(voice, voice.waiting);
                    } else {
                        voice.stage = Stage::free;
                    }
                }
            } else if (!sounding) {
                voice.stage = Stage::free;
            }
        }
    }

    void render(float *const *out, int32_t outChannels, int32_t frames) {
        if (outChannels < 1 || frames < 1) return;
        const uint64_t start = time.load(std::memory_order_relaxed);

        agenda.compact();
        PerfectoEvent event;
        while (mailbox.pop(event)) agenda.add(event);

        float *mix = out[0];
        std::fill(mix, mix + frames, 0.0f);

        int32_t frame = 0;
        while (frame < frames) {
            while (!agenda.empty() && agenda.next().time <= start + static_cast<uint64_t>(frame)) {
                apply(agenda.next());
                agenda.removeNext();
                waiting.fetch_sub(1, std::memory_order_release);
            }
            // Render up to the next event's frame, or to the end.
            int32_t until = frames;
            if (!agenda.empty()) {
                const uint64_t due = agenda.next().time - start;
                if (due < static_cast<uint64_t>(frames)) until = static_cast<int32_t>(due);
            }
            for (auto &voice : voices) render(voice, mix + frame, until - frame);
            frame = until;
        }

        for (int32_t channel = 1; channel < outChannels; ++channel) {
            std::copy(mix, mix + frames, out[channel]);
        }
        time.store(start + static_cast<uint64_t>(frames), std::memory_order_release);
    }

    /// The level an attack heads for, past full, so it gets there on time.
    static constexpr float attackGoal = 1.3f;
    /// The share of the way to its goal a note's brightness glides each
    /// time its slow values are worked out.
    float brightnessRate = 0;

    void prepare(double rate) {
        sampleRate = rate;
        brightnessRate = static_cast<float>(1 - std::exp(-(controlFrames / rate) / brightnessGlide));
        time.store(0);
        mailbox.clear();
        agenda.clear();
        waiting.store(0);
        voices.fill(perfecto::Voice{});
        notesStarted = 0;
    }
};

// MARK: The C interface

int32_t perfecto_kernel_voice_count(void) { return static_cast<int32_t>(voiceCount); }

int32_t perfecto_kernel_event_capacity(void) { return static_cast<int32_t>(eventCapacity); }

PerfectoKernel *perfecto_kernel_create(void) {
    return new PerfectoKernel();
}

void perfecto_kernel_destroy(PerfectoKernel *kernel) {
    delete kernel;
}

void perfecto_kernel_prepare(PerfectoKernel *kernel, double sampleRate) {
    kernel->prepare(sampleRate);
}

int32_t perfecto_kernel_sound_count(void) { return static_cast<int32_t>(soundCount); }

void perfecto_kernel_set_sound(PerfectoKernel *kernel, int32_t sound, const PerfectoPatch *patch) {
    if (sound < 0 || static_cast<std::size_t>(sound) >= soundCount) return;
    kernel->sounds[sound].load(*patch);
    kernel->isSet[sound] = true;
}

bool perfecto_kernel_send(PerfectoKernel *kernel, const PerfectoEvent *event) {
    if (kernel->waiting.load(std::memory_order_acquire) >= eventCapacity) return false;
    kernel->waiting.fetch_add(1, std::memory_order_release);
    return kernel->mailbox.push(*event);
}

uint64_t perfecto_kernel_time(const PerfectoKernel *kernel) {
    return kernel->time.load(std::memory_order_acquire);
}

void perfecto_kernel_render(PerfectoKernel *kernel,
                            const float *const *in, int32_t inChannels,
                            float *const *out, int32_t outChannels,
                            int32_t frames) {
    // The input is not used yet: capture and the vocoder read it.
    (void)in;
    (void)inChannels;
    perfecto::RenderGuard guard;
    perfecto::FlushToZero flush;
    kernel->render(out, outChannels, frames);
}
