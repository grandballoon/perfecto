#include "PerfectoKernel.h"

#include "Capture.hpp"
#include "EventQueue.hpp"
#include "MixBus.hpp"
#include "RenderGuard.hpp"
#include "Vocoder.hpp"
#include "Voice.hpp"

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstddef>
#include <vector>

namespace {

constexpr std::size_t voiceCount = 64;
constexpr std::size_t eventCapacity = 1024;
constexpr std::size_t soundCount = 128;
constexpr std::size_t captureCount = 4;
constexpr std::size_t sampleCount = 128;
/// Seconds over which a capture is faded out at its end, so a recording
/// stopped mid-sound does not end in a click.
constexpr double captureFade = 0.005;

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
/// Seconds in which a partial of an additive sound covers 63% of the way
/// to how it was last set: quick, and still no click.
constexpr double partialGlide = 0.015;

/// The patch filter's working range, and the brightness filter's from dark
/// to open, in Hz. Both stay under the sample rate's own limit.
constexpr double lowestCutoff = 60;
constexpr double highestCutoff = 18000;
constexpr double darkest = 300;
constexpr double brightest = 20000;

constexpr double twoPi = 6.283185307179586;

/// The slowest and the fastest an operator wanders from its pitch, in
/// cycles a second.
constexpr float slowestDrift = 0.1f;
constexpr float fastestDrift = 0.4f;
/// How far round its cycle each copy of an operator starts from the one
/// before, so the copies never start as one: the golden ratio, which
/// leaves no two of them together.
constexpr double copyPhase = 0.6180339887498949;
/// Seconds within which a note that started after another ended is taken
/// to follow it with no gap, and glides from it.
constexpr double legatoSeconds = 0.03;
/// How near its pitch, in octaves, a gliding note is counted as there.
constexpr double arrived = 1e-4;
/// The furthest a note can be bent from its pitch, in semitones, and how
/// near where it was put a bent note is counted as there.
constexpr float widestBend = 48;
constexpr float bentThere = 1e-3f;

/// The most frames the mix is worked out for at a time; a render call for
/// more is done in pieces.
constexpr int32_t blockFrames = 256;

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
    /// The frame being rendered, for what an event needs to know of when
    /// it is.
    uint64_t now = 0;

    /// The sounds notes name, and the one a number never set plays.
    std::array<perfecto::Sound, soundCount> sounds{};
    std::array<bool, soundCount> isSet{};
    perfecto::Sound plain;
    /// One cycle of a sine, which every partial of an additive sound reads.
    perfecto::Wavetable sine;

    /// What has been recorded from the input, and which one is being
    /// recorded into now (-1: none).
    std::array<perfecto::Capture, captureCount> captures{};
    std::atomic<int32_t> capturing{-1};
    /// Sounds made beforehand, each with the rate it was made at.
    struct Loaded {
        std::vector<float> samples;
        double rate = 48000;
    };
    std::array<Loaded, sampleCount> loaded{};
    std::atomic<uint32_t> capturesEnded{0};
    PerfectoCaptureSource captureSource = PerfectoCaptureInput;

    /// The vocoder, whether it is asked for (from any thread) and in use,
    /// and what it put out in the block being rendered.
    perfecto::Vocoder vocoder;
    std::atomic<bool> vocoderOn{false};
    bool vocoding = false;
    std::array<float, blockFrames> vocoded{};

    /// Where the voices' sound is added up, a block at a time: left and
    /// right of each path (see `Voice::Path`).
    std::array<std::array<float, blockFrames>, perfecto::Voice::pathCount * 2> buses{};
    perfecto::Chorus chorus;
    perfecto::Delay delay;
    perfecto::Reverb reverb;
    perfecto::Limiter limiter;
    /// The chorus's and reverb's settings as asked for, from any thread,
    /// and as the render thread last took them up.
    std::atomic<float> chorusRate{1};
    std::atomic<float> reverbTail{2};
    std::atomic<float> reverbPredelay{0.02f};
    std::atomic<float> reverbDamping{5000};
    std::atomic<float> delayTime{0.375f};
    std::atomic<float> delayFeedback{0.4f};
    float delayTimeInUse = 0;
    float delayFeedbackInUse = -1;
    float chorusRateInUse = 0;
    float reverbTailInUse = 0;
    float reverbPredelayInUse = -1;
    float reverbDampingInUse = 0;

    PerfectoKernel() {
        plain.load(perfecto::Sound::plainSine());
        sine.build(plain.patch.operators[0]);
        prepare(sampleRate);
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
        voice.releasedAt = Voice::never;
        // A note starts as it was played: bent and as loud as it was, not
        // on the way there.
        voice.pitchBend = voice.pitchBendGoal = std::clamp(note.bend, -widestBend, widestBend);
        voice.gain = voice.gainGoal = std::clamp(note.level, 0.0f, 1.0f);
        voice.glide = note.from > 0 ? std::log2(note.from / voice.bent()) : 0;
        voice.noise = 0;
        if (patch.noise.from > 0 || patch.noise.to > 0) {
            // Mixed up, so that one note's noise is not the last note's a
            // sample on; and never 0, which noise cannot start from.
            chance();
            voice.noiseState = (chanceState * 2654435761u) | 1u;
        }
        voice.velocity = std::clamp(note.velocity, 0.0f, 1.0f);
        // The wavetable's level is the one that fits the highest the
        // patch takes the operator, so the note keeps it throughout.
        const double sharpest = sound.sharpest();
        for (int i = 0; i < PerfectoOperatorCount; ++i) {
            const double step = voice.pitch() * patch.operators[i].ratio / sampleRate;
            for (int copy = 0; copy < sound.copies; ++copy) {
                voice.phase[i][copy] = copy * copyPhase - std::floor(copy * copyPhase);
                voice.phaseStep[i][copy] = step * sound.tuning[copy];
            }
            voice.tableLevel[i] = Wavetable::level(step * sharpest);
            voice.width[i] = std::clamp(patch.operators[i].pulse_width, Voice::narrowest, Voice::widest);
            voice.widthStep[i] = 0;
            if (patch.drift > 0) {
                voice.driftPhase[i] = chance();
                voice.driftRate[i] = slowestDrift + (fastestDrift - slowestDrift) * chance();
            }
        }
        for (int n = 0; n < PerfectoPartialCount; ++n) {
            Partial &partial = voice.partials[n];
            partial = Partial{};
            partial.take(note.partials[n], true);
        }
        voice.recording = nullptr;
        voice.capture = -1;
        voice.loaded = -1;
        if (patch.sampled && patch.loaded) {
            if (patch.capture >= 0 && static_cast<std::size_t>(patch.capture) < sampleCount) {
                const Loaded &sample = loaded[patch.capture];
                voice.loaded = patch.capture;
                voice.recording = sample.samples.data();
                voice.recordingStart = 0;
                voice.recordingEnd = static_cast<int32_t>(sample.samples.size());
                voice.recordingGain = 1;
                voice.position = 0;
                voice.positionStep = std::pow(2.0, (note.note + voice.pitchBend - patch.root) / 12.0)
                    * sample.rate / sampleRate;
            }
        } else if (patch.sampled && patch.capture >= 0 && static_cast<std::size_t>(patch.capture) < captureCount) {
            const Capture &capture = captures[patch.capture];
            voice.capture = patch.capture;
            voice.recording = capture.data();
            voice.recordingStart = capture.start.load(std::memory_order_relaxed);
            voice.recordingEnd = std::max(voice.recordingStart, capture.end.load(std::memory_order_acquire));
            voice.recordingGain = capture.gain.load(std::memory_order_relaxed);
            voice.position = voice.recordingStart;
            voice.positionStep = std::pow(2.0, (note.note + voice.pitchBend - patch.root) / 12.0)
                * capture.rate.load(std::memory_order_relaxed) / sampleRate;
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
        voice.steeper.clear();
        voice.brightener.clear();
        // A note starts at the brightness it was played with, not on the
        // way to it.
        voice.brightness = voice.brightnessGoal = std::clamp(note.brightness, 0.0f, 1.0f);
        // Centre is full on both sides; to one side, the other falls away.
        const float pan = std::clamp(note.pan, -1.0f, 1.0f);
        voice.side[0] = std::min(1.0f, 1 - pan);
        voice.side[1] = std::min(1.0f, 1 + pan);
        voice.chorus = voice.chorusGoal = std::clamp(note.chorus, 0.0f, 1.0f);
        voice.reverb = voice.reverbGoal = std::clamp(note.reverb, 0.0f, 1.0f);
        voice.vocoder = voice.vocoderGoal = std::clamp(note.vocoder, 0.0f, 1.0f);
        voice.delay = voice.delayGoal = std::clamp(note.delay, 0.0f, 1.0f);
        voice.shares(voice.share, vocoding);
        std::fill(std::begin(voice.shareStep), std::end(voice.shareStep), 0.0f);
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

    /// The pitch a note of `sound` at `hz` glides from: of the notes of
    /// that sound that ended just now, the pitch the nearest one was at.
    /// 0 if the sound has no glide, or the note follows none.
    double glideFrom(const perfecto::Sound &sound, double hz) const {
        if (sound.patch.glide <= 0) return 0;
        const uint64_t legato = static_cast<uint64_t>(legatoSeconds * sampleRate);
        double from = 0;
        double nearest = 0;
        for (const auto &voice : voices) {
            if (voice.sound != &sound || voice.releasedAt == perfecto::Voice::never) continue;
            if (now - voice.releasedAt > legato) continue;
            const double pitch = voice.pitch();
            const double apart = std::abs(std::log2(pitch / hz));
            if (from == 0 || apart < nearest) {
                from = pitch;
                nearest = apart;
            }
        }
        return from;
    }

    void noteOn(const PerfectoEvent &event) {
        using Stage = perfecto::Voice::Stage;
        perfecto::Voice::Waiting note{event.note_id, event.note, event.velocity, event.sound,
                                      event.brightness, event.pan, event.chorus, event.reverb,
                                      event.vocoder, event.delay, event.bend, event.level};
        const PerfectoPatch &patch = sound(event.sound).patch;
        for (int n = 0; n < PerfectoPartialCount; ++n) note.partials[n].strength = patch.operators[0].partials[n];
        const double bend = std::clamp(event.bend, -widestBend, widestBend);
        note.from = glideFrom(sound(event.sound), 440.0 * std::pow(2.0, (event.note + bend - 69) / 12.0));
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
                voice.releasedAt = now;
            } else if (voice.stage == Stage::stolen && voice.waiting.id == event.note_id) {
                // Ended before it began: the voice just finishes fading.
                voice.stage = Stage::released;
            }
        }
    }

    void noteChange(const PerfectoEvent &event) {
        using Stage = perfecto::Voice::Stage;
        const float brightness = std::clamp(event.brightness, 0.0f, 1.0f);
        const float chorus = std::clamp(event.chorus, 0.0f, 1.0f);
        const float reverb = std::clamp(event.reverb, 0.0f, 1.0f);
        const float vocoder = std::clamp(event.vocoder, 0.0f, 1.0f);
        const float delay = std::clamp(event.delay, 0.0f, 1.0f);
        const float bend = std::clamp(event.bend, -widestBend, widestBend);
        const float level = std::clamp(event.level, 0.0f, 1.0f);
        for (auto &voice : voices) {
            if (voice.stage == Stage::held && voice.id == event.note_id) {
                voice.brightnessGoal = brightness;
                voice.chorusGoal = chorus;
                voice.reverbGoal = reverb;
                voice.vocoderGoal = vocoder;
                voice.delayGoal = delay;
                voice.pitchBendGoal = bend;
                voice.gainGoal = level;
            } else if (voice.stage == Stage::stolen && voice.waiting.id == event.note_id) {
                voice.waiting.brightness = brightness;
                voice.waiting.chorus = chorus;
                voice.waiting.reverb = reverb;
                voice.waiting.vocoder = vocoder;
                voice.waiting.delay = delay;
                voice.waiting.bend = bend;
                voice.waiting.level = level;
            }
        }
    }

    void partialChange(const PerfectoEvent &event) {
        using Stage = perfecto::Voice::Stage;
        if (event.note < 0 || event.note >= PerfectoPartialCount) return;
        const perfecto::PartialSetting setting{std::max(event.level, 0.0f), event.offset,
                                               std::clamp(event.depth, 0.0f, 1.0f), std::max(event.rate, 0.0f)};
        for (auto &voice : voices) {
            if (voice.stage == Stage::held && voice.id == event.note_id) {
                voice.partials[event.note].take(setting, voice.age == 0);
            } else if (voice.stage == Stage::stolen && voice.waiting.id == event.note_id) {
                voice.waiting.partials[event.note] = setting;
            }
        }
    }

    // MARK: Capture

    void captureStart(int32_t number, int32_t source) {
        using Stage = perfecto::Voice::Stage;
        captureStop();
        if (number < 0 || static_cast<std::size_t>(number) >= captureCount) return;
        captureSource = source == PerfectoCaptureVocoder ? PerfectoCaptureVocoder : PerfectoCaptureInput;
        captures[number].begin(sampleRate);
        capturing.store(number, std::memory_order_release);
        // What the notes playing it were reading is about to be written over.
        for (auto &voice : voices) {
            if (voice.stage == Stage::free || voice.capture != number) continue;
            if (voice.stage == Stage::stolen) {
                start(voice, voice.waiting);
            } else {
                voice.stage = Stage::free;
            }
        }
    }

    void captureStop() {
        const int32_t number = capturing.load(std::memory_order_relaxed);
        if (number < 0) return;
        captures[number].finish();
        capturing.store(-1, std::memory_order_release);
        capturesEnded.fetch_add(1, std::memory_order_release);
    }

    /// The audio input on frame `at` of the render call, its channels
    /// averaged into one.
    static float heard(const float *const *in, int32_t inChannels, int32_t at) {
        if (inChannels < 1) return 0;
        float sample = 0;
        for (int32_t channel = 0; channel < inChannels; ++channel) sample += in[channel][at];
        return inChannels > 1 ? sample / static_cast<float>(inChannels) : sample;
    }

    /// Records `frames` frames, from frame `from` of the block (which is
    /// `offset` frames into the render call), if a capture is being
    /// recorded into.
    void record(const float *const *in, int32_t inChannels, int32_t offset, int32_t from, int32_t frames) {
        const int32_t number = capturing.load(std::memory_order_relaxed);
        if (number < 0) return;
        perfecto::Capture &capture = captures[number];
        for (int32_t i = from; i < from + frames; ++i) {
            const float sample = captureSource == PerfectoCaptureVocoder ? vocoded[i] : heard(in, inChannels, offset + i);
            if (!capture.record(sample)) {
                captureStop();
                return;
            }
        }
    }

    void apply(const PerfectoEvent &event) {
        switch (event.type) {
        case PerfectoEventNoteOn:       noteOn(event); break;
        case PerfectoEventNoteOff:      noteOff(event); break;
        case PerfectoEventNoteChange:   noteChange(event); break;
        case PerfectoEventCaptureStart: captureStart(event.note, event.sound); break;
        case PerfectoEventCaptureStop:  captureStop(); break;
        case PerfectoEventPartialChange: partialChange(event); break;
        }
    }

    // MARK: Rendering

    /// Works out the values of `voice` that move slowly, for its next
    /// `controlFrames` frames.
    void control(perfecto::Voice &voice) {
        const PerfectoPatch &patch = voice.sound->patch;
        const double seconds = voice.age / sampleRate;
        const double ceiling = 0.45 * sampleRate;
        // Where the LFO is: -1...1, less while it is still coming up.
        const PerfectoLfo &lfo = patch.lfo;
        const double swing = lfo.rate > 0
            ? std::sin(twoPi * lfo.rate * seconds) * (seconds < lfo.rise ? seconds / lfo.rise : 1)
            : 0;
        // A gliding note covers a share of what is left of the way to its
        // pitch each time, and is there once it is near enough.
        const bool gliding = voice.glide != 0;
        if (gliding && voice.age > 0) {
            voice.glide *= std::exp(-(controlFrames / sampleRate) / patch.glide);
            if (std::abs(voice.glide) < arrived || patch.glide <= 0) voice.glide = 0;
        }
        // A bent note covers a share of the way to where it was last put,
        // as its other settings do, so a finger that slides is heard as a
        // slide and not as steps. A recording is played as much faster.
        const bool bending = voice.pitchBend != voice.pitchBendGoal;
        if (bending) {
            const float before = voice.pitchBend;
            voice.pitchBend += (voice.pitchBendGoal - voice.pitchBend) * brightnessRate;
            if (std::abs(voice.pitchBendGoal - voice.pitchBend) < bentThere) voice.pitchBend = voice.pitchBendGoal;
            if (voice.recording) voice.positionStep *= std::pow(2.0, (voice.pitchBend - before) / 12.0);
        }
        if (lfo.pitch != 0 || patch.drift > 0 || gliding || bending) {
            const double pitch = voice.pitch();
            for (int i = 0; i < PerfectoOperatorCount; ++i) {
                // A modulator that wandered from its carrier would change
                // the sound and not only its pitch.
                const int wanderer = patch.modulates ? 0 : i;
                const double wander = patch.drift
                    * std::sin(twoPi * (voice.driftRate[wanderer] * seconds + voice.driftPhase[wanderer]));
                const double plain = pitch * patch.operators[i].ratio / sampleRate;
                const double step = plain * std::pow(2.0, (lfo.pitch * swing + wander) / 1200);
                for (int copy = 0; copy < voice.sound->copies; ++copy) {
                    voice.phaseStep[i][copy] = step * voice.sound->tuning[copy];
                }
                // The wavetable's level follows a glide or a bend, which
                // can cross octaves; nothing else moves the pitch far
                // enough to.
                if (gliding || bending) voice.tableLevel[i] = perfecto::Wavetable::level(plain * voice.sound->sharpest());
            }
        }
        if (patch.additive) tunePartials(voice);
        voice.noise = patch.level * static_cast<float>(valueOf(patch.noise, seconds));
        if (lfo.pulse_width != 0) {
            // A width moves there evenly over these frames, as an edge
            // that jumped would be heard.
            for (int i = 0; i < PerfectoOperatorCount; ++i) {
                const float width = std::clamp(patch.operators[i].pulse_width + lfo.pulse_width * static_cast<float>(swing),
                                               perfecto::Voice::narrowest, perfecto::Voice::widest);
                voice.widthStep[i] = (width - voice.width[i]) / controlFrames;
            }
        }
        if (patch.modulates) {
            voice.bend = static_cast<float>(valueOf(patch.index, seconds) / twoPi);
        }
        if (patch.filtered) {
            const double cutoff = std::clamp(valueOf(patch.cutoff, seconds) * voice.bent() * std::pow(2.0, lfo.cutoff * swing),
                                             lowestCutoff, std::min(highestCutoff, ceiling));
            // Resonance 0 is flat; 1 rings. A steep filter is two in a
            // row, tuned so that together they are flat up to the cutoff,
            // with the second doing the ringing.
            if (patch.steep) {
                voice.filter.tune(cutoff, sampleRate, 0.5412);
                voice.steeper.tune(cutoff, sampleRate, 1.3066 * std::pow(14.0, patch.resonance));
            } else {
                voice.filter.tune(cutoff, sampleRate, 0.7071 * std::pow(25.0, patch.resonance));
            }
        }
        // The note's own settings glide to where they were last put, and
        // its share of each path moves there evenly over these frames.
        voice.chorus += (voice.chorusGoal - voice.chorus) * brightnessRate;
        voice.reverb += (voice.reverbGoal - voice.reverb) * brightnessRate;
        voice.vocoder += (voice.vocoderGoal - voice.vocoder) * brightnessRate;
        voice.delay += (voice.delayGoal - voice.delay) * brightnessRate;
        voice.gain += (voice.gainGoal - voice.gain) * brightnessRate;
        float shares[perfecto::Voice::pathCount];
        voice.shares(shares, vocoding);
        for (int path = 0; path < perfecto::Voice::pathCount; ++path) {
            voice.shareStep[path] = (shares[path] - voice.share[path]) / controlFrames;
        }
        voice.brightness += (voice.brightnessGoal - voice.brightness) * brightnessRate;
        voice.brightener.tune(std::min(darkest * std::pow(brightest / darkest, voice.brightness), ceiling),
                              sampleRate, 0.7071);
    }

    /// Works out the partials of `voice`, whose sound is additive, for its
    /// next `controlFrames` frames: each glides on towards how it was set,
    /// its swing moves on, and its strength moves there evenly over the
    /// frames. A note's first frames start where they are set.
    void tunePartials(perfecto::Voice &voice) {
        const double pitch = voice.pitch();
        const double ceiling = 0.45 * sampleRate;
        const float level = voice.sound->patch.level;
        const bool first = voice.age == 0;
        for (int n = 0; n < PerfectoPartialCount; ++n) {
            perfecto::Partial &partial = voice.partials[n];
            if (!first) {
                partial.strength += (partial.strengthGoal - partial.strength) * partialRate;
                partial.offset += (partial.offsetGoal - partial.offset) * partialRate;
                partial.depth += (partial.depthGoal - partial.depth) * partialRate;
                partial.swing += partial.rate * controlFrames / sampleRate;
                partial.swing -= std::floor(partial.swing);
            }
            const double hz = pitch * (n + 1) + partial.offset;
            partial.step = hz / sampleRate;
            const float swung = partial.depth > 0
                ? 1 - partial.depth * static_cast<float>(0.5 - 0.5 * std::cos(twoPi * partial.swing))
                : 1;
            const float gain = hz > 0 && hz < ceiling ? level * partial.strength * swung : 0;
            if (first) {
                partial.gain = gain;
                partial.gainStep = 0;
            } else {
                partial.gainStep = (gain - partial.gain) / controlFrames;
            }
        }
    }

    /// One frame of a voice whose sound is additive: its partials, added.
    float additive(perfecto::Voice &voice) {
        float sample = 0;
        for (auto &partial : voice.partials) {
            if (partial.gain != 0 || partial.gainStep != 0) sample += partial.gain * sine.read(perfecto::Wavetable::levels - 1, partial.phase);
            // Never negative, so dropping the whole cycles wraps it.
            const double phase = partial.phase + partial.step;
            partial.phase = phase - static_cast<int>(phase);
            partial.gain += partial.gainStep;
        }
        return sample;
    }

    /// One frame of a voice playing a capture, read between the
    /// recording's frames along a curve through the four nearest. The
    /// voice's recording is over (`recording` is null) after its last.
    float recorded(perfecto::Voice &voice) {
        const int32_t at = static_cast<int32_t>(voice.position);
        if (at >= voice.recordingEnd) {
            voice.recording = nullptr;
            return 0;
        }
        const int32_t first = voice.recordingStart;
        const int32_t last = voice.recordingEnd - 1;
        const float *data = voice.recording;
        const float a = data[std::max(at - 1, first)];
        const float b = data[at];
        const float c = data[std::min(at + 1, last)];
        const float d = data[std::min(at + 2, last)];
        const float t = static_cast<float>(voice.position - at);
        const float sample = b + 0.5f * t * (c - a + t * (2 * a - 5 * b + 4 * c - d + t * (3 * (b - c) + d - a)));
        const float left = static_cast<float>((voice.recordingEnd - voice.position) / captureFadeFrames);
        voice.position += voice.positionStep;
        return sample * voice.recordingGain * std::min(left, 1.0f) * voice.sound->patch.level;
    }

    /// Operator `i` of `voice`'s sound at `phase` (0..<1).
    static float wave(const perfecto::Voice &voice, int i, double phase) {
        const perfecto::Sound &sound = *voice.sound;
        const float sample = sound.waves[i].read(voice.tableLevel[i], phase);
        if (sound.patch.operators[i].wave != PerfectoWavePulse) return sample;
        double behind = phase - voice.width[i];
        if (behind < 0) behind += 1;
        return perfecto::Voice::pulse(sample, sound.waves[i].read(voice.tableLevel[i], behind), voice.width[i]);
    }

    /// One frame of `voice`'s sources.
    float source(perfecto::Voice &voice) {
        const perfecto::Sound &sound = *voice.sound;
        if (sound.patch.sampled) return voice.recording ? recorded(voice) : 0;
        if (sound.patch.additive) return additive(voice);
        float sample = 0;
        for (int copy = 0; copy < sound.copies; ++copy) {
            if (sound.patch.modulates) {
                double bent = voice.phase[0][copy] + voice.bend * wave(voice, 1, voice.phase[1][copy]);
                bent -= std::floor(bent);
                sample += sound.gains[0] * wave(voice, 0, bent);
            } else {
                for (int i = 0; i < PerfectoOperatorCount; ++i) {
                    if (sound.gains[i] == 0) continue;
                    sample += sound.gains[i] * wave(voice, i, voice.phase[i][copy]);
                }
            }
        }
        for (int i = 0; i < PerfectoOperatorCount; ++i) {
            for (int copy = 0; copy < sound.copies; ++copy) {
                // Never negative, so dropping the whole cycles wraps it.
                const double phase = voice.phase[i][copy] + voice.phaseStep[i][copy];
                voice.phase[i][copy] = phase - static_cast<int>(phase);
            }
            voice.width[i] += voice.widthStep[i];
        }
        if (voice.noise > 0) sample += voice.noise * voice.hiss();
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

    /// Adds `voice`'s next `frames` frames to the buses, from `offset`.
    void render(perfecto::Voice &voice, int32_t offset, int32_t frames) {
        using Voice = perfecto::Voice;
        using Stage = Voice::Stage;
        for (int32_t i = offset; i < offset + frames; ++i) {
            if (voice.stage == Stage::free) return;
            if (voice.age % controlFrames == 0) control(voice);

            float sample = source(voice);
            if (voice.sound->patch.sampled && !voice.recording && voice.stage != Stage::stolen) {
                // Its recording is over (or was never there): so is the note.
                voice.stage = Stage::free;
                return;
            }
            if (voice.sound->patch.filtered) {
                sample = voice.filter.run(sample);
                if (voice.sound->patch.steep) sample = voice.steeper.run(sample);
            }
            if (voice.sound->driveIn > 0) {
                sample = voice.sound->driveOut * perfecto::Sound::soften(sample * voice.sound->driveIn);
            }
            sample = voice.brightener.run(sample * voice.level * voice.velocity) * voice.fade;
            for (int path = 0; path < Voice::pathCount; ++path) {
                const float sent = sample * voice.share[path];
                buses[path * 2][i] += sent * voice.side[0];
                buses[path * 2 + 1][i] += sent * voice.side[1];
                voice.share[path] += voice.shareStep[path];
            }
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

    /// Adds up what the voices made of `frames` frames, from frame `from`
    /// of the block, through the chorus, the reverb, the vocoder and the
    /// limiter, into `out` (the block is `offset` frames into it).
    void mix(const float *const *in, int32_t inChannels,
             float *const *out, int32_t outChannels, int32_t offset, int32_t from, int32_t frames) {
        using Voice = perfecto::Voice;
        for (int32_t i = from; i < from + frames; ++i) {
            float left = buses[Voice::dry * 2][i];
            float right = buses[Voice::dry * 2 + 1][i];
            float wetLeft, wetRight;
            chorus.run(buses[Voice::toChorus * 2][i], buses[Voice::toChorus * 2 + 1][i], wetLeft, wetRight);
            left += wetLeft;
            right += wetRight;
            delay.run(buses[Voice::toDelay * 2][i], buses[Voice::toDelay * 2 + 1][i], wetLeft, wetRight);
            left += wetLeft;
            right += wetRight;
            reverb.run(buses[Voice::toReverb * 2][i], buses[Voice::toReverb * 2 + 1][i], wetLeft, wetRight);
            left += wetLeft;
            right += wetRight;
            if (vocoding) {
                // The notes sent to it go in as one, and it comes out in the centre.
                const float carrier = 0.5f * (buses[Voice::toVocoder * 2][i] + buses[Voice::toVocoder * 2 + 1][i]);
                vocoded[i] = vocoder.run(heard(in, inChannels, offset + i), carrier);
                left += vocoded[i];
                right += vocoded[i];
            }
            limiter.run(left, right);
            if (outChannels == 1) {
                out[0][offset + i] = 0.5f * (left + right);
            } else {
                out[0][offset + i] = left;
                out[1][offset + i] = right;
            }
        }
    }

    /// Renders the next `frames` frames, at most a block, to `out` from `offset`.
    void renderBlock(const float *const *in, int32_t inChannels,
                     float *const *out, int32_t outChannels, int32_t offset, int32_t frames) {
        const uint64_t start = time.load(std::memory_order_relaxed);
        for (auto &bus : buses) std::fill(bus.begin(), bus.begin() + frames, 0.0f);

        int32_t frame = 0;
        while (frame < frames) {
            now = start + static_cast<uint64_t>(frame);
            while (!agenda.empty() && agenda.next().time <= now) {
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
            for (auto &voice : voices) render(voice, frame, until - frame);
            mix(in, inChannels, out, outChannels, offset, frame, until - frame);
            record(in, inChannels, offset, frame, until - frame);
            frame = until;
        }

        for (int32_t channel = 2; channel < outChannels; ++channel) {
            std::fill(out[channel] + offset, out[channel] + offset + frames, 0.0f);
        }
        time.store(start + static_cast<uint64_t>(frames), std::memory_order_release);
    }

    void render(const float *const *in, int32_t inChannels,
                float *const *out, int32_t outChannels, int32_t frames) {
        if (outChannels < 1 || frames < 1) return;

        agenda.compact();
        PerfectoEvent event;
        while (mailbox.pop(event)) agenda.add(event);

        const float rate = chorusRate.load(std::memory_order_relaxed);
        if (rate != chorusRateInUse) chorus.setRate(chorusRateInUse = rate);
        const float tail = reverbTail.load(std::memory_order_relaxed);
        if (tail != reverbTailInUse) reverb.setTail(reverbTailInUse = tail);
        const float predelay = reverbPredelay.load(std::memory_order_relaxed);
        if (predelay != reverbPredelayInUse) reverb.setPredelay(reverbPredelayInUse = predelay);
        const float damping = reverbDamping.load(std::memory_order_relaxed);
        if (damping != reverbDampingInUse) reverb.setDamping(reverbDampingInUse = damping);
        const float echo = delayTime.load(std::memory_order_relaxed);
        if (echo != delayTimeInUse) delay.setTime(delayTimeInUse = echo);
        const float fed = delayFeedback.load(std::memory_order_relaxed);
        if (fed != delayFeedbackInUse) delay.setFeedback(delayFeedbackInUse = fed);
        // With nothing to hear, the vocoder has nothing to shape notes by.
        const bool wanted = vocoderOn.load(std::memory_order_relaxed) && in && inChannels > 0;
        if (wanted != vocoding) {
            vocoding = wanted;
            vocoder.clear();
            vocoded.fill(0);
        }

        for (int32_t done = 0; done < frames; done += blockFrames) {
            renderBlock(in, inChannels, out, outChannels, done, std::min(blockFrames, frames - done));
        }
    }

    /// The level an attack heads for, past full, so it gets there on time.
    static constexpr float attackGoal = 1.3f;
    /// The share of the way to its goal a note's brightness glides each
    /// time its slow values are worked out.
    float brightnessRate = 0;
    /// The share of the way to how it was set a partial glides each time.
    float partialRate = 0;
    /// Frames a capture is faded out over at its end.
    float captureFadeFrames = 1;

    /// What the next number of `chance` is made from. It starts from the
    /// same place each time the kernel is readied, so the same events make
    /// the same sound.
    static constexpr uint32_t firstChance = 0x9E3779B9;
    uint32_t chanceState = firstChance;

    /// A number from 0 up to 1 that nothing predicts, for what should
    /// differ from note to note.
    float chance() {
        chanceState ^= chanceState << 13;
        chanceState ^= chanceState >> 17;
        chanceState ^= chanceState << 5;
        return static_cast<float>(chanceState >> 8) / 16777216.0f;
    }

    void prepare(double rate) {
        // A recording cut short by the engine stopping is kept as far as it got.
        captureStop();
        sampleRate = rate;
        captureFadeFrames = static_cast<float>(captureFade * rate);
        brightnessRate = static_cast<float>(1 - std::exp(-(controlFrames / rate) / brightnessGlide));
        partialRate = static_cast<float>(1 - std::exp(-(controlFrames / rate) / partialGlide));
        time.store(0);
        mailbox.clear();
        agenda.clear();
        waiting.store(0);
        voices.fill(perfecto::Voice{});
        notesStarted = 0;
        now = 0;
        chanceState = firstChance;
        chorus.prepare(rate);
        delay.prepare(rate);
        reverb.prepare(rate);
        limiter.prepare(rate);
        vocoder.prepare(rate);
        vocoding = false;
        vocoded.fill(0);
        chorusRateInUse = reverbTailInUse = reverbDampingInUse = delayTimeInUse = 0;
        delayFeedbackInUse = -1;
        reverbPredelayInUse = -1;
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

int32_t perfecto_kernel_capture_count(void) { return static_cast<int32_t>(captureCount); }

int32_t perfecto_kernel_capture_capacity(void) { return perfecto::Capture::capacity; }

namespace {

const perfecto::Capture *captureNumbered(const PerfectoKernel *kernel, int32_t capture) {
    const bool known = capture >= 0 && static_cast<std::size_t>(capture) < captureCount;
    return known ? &kernel->captures[capture] : nullptr;
}

}

int32_t perfecto_kernel_capturing(const PerfectoKernel *kernel) {
    return kernel->capturing.load(std::memory_order_acquire);
}

uint32_t perfecto_kernel_captures_ended(const PerfectoKernel *kernel) {
    return kernel->capturesEnded.load(std::memory_order_acquire);
}

int32_t perfecto_kernel_capture_length(const PerfectoKernel *kernel, int32_t capture) {
    const auto *found = captureNumbered(kernel, capture);
    return found ? found->length() : 0;
}

double perfecto_kernel_capture_rate(const PerfectoKernel *kernel, int32_t capture) {
    const auto *found = captureNumbered(kernel, capture);
    return found ? found->rate.load(std::memory_order_relaxed) : 0;
}

int32_t perfecto_kernel_capture_read(const PerfectoKernel *kernel, int32_t capture, float *out, int32_t room) {
    const auto *found = captureNumbered(kernel, capture);
    return found ? found->read(out, room) : 0;
}

void perfecto_kernel_capture_load(PerfectoKernel *kernel, int32_t capture,
                                  const float *samples, int32_t frames, double sampleRate) {
    if (captureNumbered(kernel, capture)) kernel->captures[capture].load(samples, frames, sampleRate);
}

int32_t perfecto_kernel_sample_count(void) { return static_cast<int32_t>(sampleCount); }

void perfecto_kernel_sample_load(PerfectoKernel *kernel, int32_t sample,
                                 const float *samples, int32_t frames, double sampleRate) {
    if (sample < 0 || static_cast<std::size_t>(sample) >= sampleCount) return;
    auto &loaded = kernel->loaded[sample];
    loaded.samples.assign(samples, samples + std::max(frames, 0));
    loaded.rate = sampleRate;
    // What the voices playing it were reading is gone; a voice being taken
    // for a note starts that note now, on what is there.
    using Stage = perfecto::Voice::Stage;
    for (auto &voice : kernel->voices) {
        if (voice.stage == Stage::free || voice.loaded != sample) continue;
        if (voice.stage == Stage::stolen) kernel->start(voice, voice.waiting);
        else voice.stage = Stage::free;
    }
}

int32_t perfecto_kernel_sample_length(const PerfectoKernel *kernel, int32_t sample) {
    if (sample < 0 || static_cast<std::size_t>(sample) >= sampleCount) return 0;
    return static_cast<int32_t>(kernel->loaded[sample].samples.size());
}

void perfecto_kernel_set_chorus_rate(PerfectoKernel *kernel, float hz) {
    kernel->chorusRate.store(std::clamp(hz, 0.05f, 10.0f), std::memory_order_relaxed);
}

void perfecto_kernel_set_reverb_tail(PerfectoKernel *kernel, float seconds) {
    kernel->reverbTail.store(std::clamp(seconds, 0.1f, 30.0f), std::memory_order_relaxed);
}

void perfecto_kernel_set_reverb_predelay(PerfectoKernel *kernel, float seconds) {
    kernel->reverbPredelay.store(std::clamp(seconds, 0.0f, 0.2f), std::memory_order_relaxed);
}

void perfecto_kernel_set_reverb_damping(PerfectoKernel *kernel, float hz) {
    kernel->reverbDamping.store(std::clamp(hz, 500.0f, 20000.0f), std::memory_order_relaxed);
}

void perfecto_kernel_set_delay_time(PerfectoKernel *kernel, float seconds) {
    kernel->delayTime.store(seconds, std::memory_order_relaxed);
}

void perfecto_kernel_set_delay_feedback(PerfectoKernel *kernel, float share) {
    kernel->delayFeedback.store(share, std::memory_order_relaxed);
}

void perfecto_kernel_set_vocoder(PerfectoKernel *kernel, bool on) {
    kernel->vocoderOn.store(on, std::memory_order_relaxed);
}

int32_t perfecto_kernel_latency(const PerfectoKernel *kernel) {
    return static_cast<int32_t>(kernel->limiter.latency());
}

uint64_t perfecto_kernel_time(const PerfectoKernel *kernel) {
    return kernel->time.load(std::memory_order_acquire);
}

void perfecto_kernel_render(PerfectoKernel *kernel,
                            const float *const *in, int32_t inChannels,
                            float *const *out, int32_t outChannels,
                            int32_t frames) {
    perfecto::RenderGuard guard;
    perfecto::FlushToZero flush;
    kernel->render(in, inChannels, out, outChannels, frames);
}
