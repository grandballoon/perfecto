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

/// One note's loudness at full velocity. Notes simply add; holding the sum
/// under full scale is the master limiter's job, which the skeleton does
/// not have yet.
constexpr float noteLevel = 0.2f;

/// Seconds a note takes to reach its level, die away after it ends, and be
/// faded out when its voice is taken. None is short enough to click.
constexpr double attackSeconds = 0.003;
constexpr double releaseSeconds = 0.05;
constexpr double stealSeconds = 0.003;

constexpr double twoPi = 6.283185307179586;

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

    // MARK: Notes

    float step(double seconds) const {
        return static_cast<float>(noteLevel / (seconds * sampleRate));
    }

    void start(perfecto::Voice &voice, uint64_t id, int32_t note, float velocity) {
        voice.stage = perfecto::Voice::Stage::held;
        voice.id = id;
        voice.startedAt = ++notesStarted;
        voice.phase = 0;
        voice.phaseStep = 440.0 * std::pow(2.0, (note - 69) / 12.0) / sampleRate;
        voice.target = noteLevel * std::clamp(velocity, 0.0f, 1.0f);
        voice.levelStep = step(attackSeconds);
    }

    /// The voice a new note takes: a free one, else the quietest of those
    /// dying away, else the one held longest.
    perfecto::Voice &voiceForNewNote() {
        using Stage = perfecto::Voice::Stage;
        perfecto::Voice *quietest = nullptr;
        perfecto::Voice *oldest = nullptr;
        for (auto &voice : voices) {
            if (voice.stage == Stage::free) return voice;
            if (voice.stage == Stage::released && (!quietest || voice.level < quietest->level)) quietest = &voice;
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
        auto &voice = voiceForNewNote();
        if (voice.stage == Stage::free) {
            start(voice, event.note_id, event.note, event.velocity);
            return;
        }
        // Whatever the voice is sounding is faded out first, so taking it
        // never clicks; the new note starts when that is done.
        voice.stage = Stage::stolen;
        voice.startedAt = ++notesStarted;
        voice.waiting = {event.note_id, event.note, event.velocity};
        voice.target = 0;
        voice.levelStep = step(stealSeconds);
    }

    void noteOff(const PerfectoEvent &event) {
        using Stage = perfecto::Voice::Stage;
        for (auto &voice : voices) {
            if (voice.stage == Stage::held && voice.id == event.note_id) {
                voice.stage = Stage::released;
                voice.target = 0;
                voice.levelStep = step(releaseSeconds);
            } else if (voice.stage == Stage::stolen && voice.waiting.id == event.note_id) {
                // Ended before it began: the voice just finishes fading.
                voice.stage = Stage::released;
            }
        }
    }

    void apply(const PerfectoEvent &event) {
        switch (event.type) {
        case PerfectoEventNoteOn:  noteOn(event); break;
        case PerfectoEventNoteOff: noteOff(event); break;
        }
    }

    // MARK: Rendering

    /// Adds `voice`'s next `frames` frames to `out`.
    void render(perfecto::Voice &voice, float *out, int32_t frames) {
        using Stage = perfecto::Voice::Stage;
        for (int32_t i = 0; i < frames; ++i) {
            if (voice.stage == Stage::free) return;
            out[i] += voice.level * static_cast<float>(std::sin(twoPi * voice.phase));
            voice.phase += voice.phaseStep;
            if (voice.phase >= 1) voice.phase -= 1;

            if (voice.level < voice.target) {
                voice.level = std::min(voice.level + voice.levelStep, voice.target);
            } else if (voice.level > voice.target) {
                voice.level = std::max(voice.level - voice.levelStep, voice.target);
            }
            if (voice.level == 0 && voice.target == 0) {
                if (voice.stage == Stage::stolen) {
                    start(voice, voice.waiting.id, voice.waiting.note, voice.waiting.velocity);
                } else if (voice.stage == Stage::released) {
                    voice.stage = Stage::free;
                }
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
    kernel->sampleRate = sampleRate;
    kernel->time.store(0);
    kernel->mailbox.clear();
    kernel->agenda.clear();
    kernel->waiting.store(0);
    kernel->voices.fill(perfecto::Voice{});
    kernel->notesStarted = 0;
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
    kernel->render(out, outChannels, frames);
}
