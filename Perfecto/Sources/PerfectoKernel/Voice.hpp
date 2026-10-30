// One note's sound: the state of a voice, and the pieces it is made of.
// A voice is plain numbers, there are a fixed number of them, and none is
// ever created or destroyed.

#ifndef PERFECTO_VOICE_HPP
#define PERFECTO_VOICE_HPP

#include "Sound.hpp"

#include <cmath>
#include <cstdint>

namespace perfecto {

/// A low-pass filter (12 dB an octave) that stays stable however fast its
/// cutoff is moved, so a patch can sweep it and a finger can play it.
struct Lowpass {
    float s1 = 0;
    float s2 = 0;
    float a1 = 0;
    float a2 = 0;
    float a3 = 0;

    /// Sets the cutoff, in Hz, and how sharply it peaks there (`q`: 0.707
    /// is flat, higher rings).
    void tune(double cutoff, double sampleRate, double q) {
        const double g = std::tan(3.141592653589793 * cutoff / sampleRate);
        const double k = 1 / q;
        const double first = 1 / (1 + g * (g + k));
        a1 = static_cast<float>(first);
        a2 = static_cast<float>(g * first);
        a3 = static_cast<float>(g * g * first);
    }

    float run(float in) {
        const float v3 = in - s2;
        const float v1 = a1 * s1 + a2 * v3;
        const float v2 = s2 + a2 * s1 + a3 * v3;
        s1 = 2 * v1 - s1;
        s2 = 2 * v2 - s2;
        return v2;
    }

    void clear() { s1 = s2 = 0; }
};

/// How one partial of an additive sound is set (`PerfectoEventPartialChange`).
struct PartialSetting {
    float strength = 0;
    float offset = 0;
    float depth = 0;
    float rate = 0;
};

/// One partial of a voice playing an additive sound: where its sine is and
/// how far it moves a frame, and how it is set now and where it is going.
struct Partial {
    double phase = 0;
    double step = 0;
    float strength = 0;
    float strengthGoal = 0;
    float offset = 0;
    float offsetGoal = 0;
    float depth = 0;
    float depthGoal = 0;
    float rate = 0;
    /// Where its swing is, in cycles from its loudest.
    double swing = 0;
    /// What it is multiplied by now, all of the above and the patch's
    /// level, and how far that moves a frame.
    float gain = 0;
    float gainStep = 0;

    /// Takes `setting`, at once or on the way there.
    void take(const PartialSetting &setting, bool atOnce) {
        strengthGoal = setting.strength;
        offsetGoal = setting.offset;
        depthGoal = setting.depth;
        rate = setting.rate;
        if (atOnce) {
            strength = strengthGoal;
            offset = offsetGoal;
            depth = depthGoal;
        }
    }
};

struct Voice {
    /// The paths a voice's sound takes: straight to the output, and into
    /// the chorus, the reverb, the vocoder and the delay.
    enum Path { dry = 0, toChorus, toReverb, toVocoder, toDelay, pathCount };

    enum class Stage : uint8_t {
        /// Silent and free to take a note.
        free,
        /// Sounding a note that has not been ended.
        held,
        /// Dying away after its note ended.
        released,
        /// Being faded out fast to make way for `waiting`.
        stolen,
    };

    /// Where a note is in its envelope.
    enum class Envelope : uint8_t { attack, decay, release };

    /// A note taking over a voice, started once the voice has faded out.
    struct Waiting {
        uint64_t id = 0;
        int32_t note = 0;
        float velocity = 0;
        int32_t sound = 0;
        float brightness = 1;
        float pan = 0;
        float chorus = 0;
        float reverb = 0;
        float vocoder = 0;
        float delay = 0;
        float bend = 0;
        float level = 1;
        /// The pitch the note glides from, in Hz; 0 is its own.
        double from = 0;
        /// For an additive sound: how each partial is set.
        PartialSetting partials[PerfectoPartialCount] = {};
    };

    /// A frame no note was released on.
    static constexpr uint64_t never = ~uint64_t{0};

    Stage stage = Stage::free;
    uint64_t id = 0;
    /// When the voice last started a note, as a count of notes started.
    uint64_t startedAt = 0;
    Waiting waiting;

    const Sound *sound = nullptr;
    /// The note's frequency, and frames since it started.
    double hz = 0;
    uint32_t age = 0;
    /// The frame the note was ended on, for a note that follows it to
    /// glide from; `never` until it is.
    uint64_t releasedAt = never;
    /// How far the note still is from its pitch, in octaves, while it
    /// glides there (`PerfectoPatch::glide`).
    double glide = 0;
    /// How far the note is bent from its pitch, in semitones, now and
    /// where it is going.
    float pitchBend = 0;
    float pitchBendGoal = 0;
    /// The patch's noise: how loud it is now, and what the next sample of
    /// it is made from.
    float noise = 0;
    uint32_t noiseState = 1;
    float velocity = 0;

    /// Each copy of each operator: where it is in its cycle (0..<1) and
    /// how far it moves a frame. And each operator: the level of its
    /// wavetable that fits under half the sample rate at its fastest.
    double phase[PerfectoOperatorCount][PerfectoUnisonCount] = {};
    double phaseStep[PerfectoOperatorCount][PerfectoUnisonCount] = {};
    int tableLevel[PerfectoOperatorCount] = {0, 0};
    /// How each operator wanders from its pitch (the patch's `drift`):
    /// where in its cycle the wander starts, and its cycles a second.
    float driftPhase[PerfectoOperatorCount] = {0, 0};
    float driftRate[PerfectoOperatorCount] = {0, 0};
    /// For an operator whose wave is a pulse: the share of each cycle it
    /// is high for, and how far that moves a frame.
    float width[PerfectoOperatorCount] = {0.5f, 0.5f};
    float widthStep[PerfectoOperatorCount] = {0, 0};
    /// How far the second operator bends the first one's phase, in cycles.
    float bend = 0;

    /// For an additive sound: its partials.
    Partial partials[PerfectoPartialCount] = {};

    /// For a sound that is a capture: the recording, where the voice is in
    /// it (in its frames) and how far it moves a frame, the frame it ends
    /// before, and the level it is played at. `recording` is null otherwise.
    const float *recording = nullptr;
    double position = 0;
    double positionStep = 0;
    int32_t recordingStart = 0;
    int32_t recordingEnd = 0;
    float recordingGain = 1;
    /// Which capture, so the voice can be ended when it is recorded over,
    /// or which loaded sample, so it can be ended when another is loaded.
    int32_t capture = -1;
    int32_t loaded = -1;

    Envelope envelope = Envelope::attack;
    /// The envelope's level now, 0...1, and the share of the way to its
    /// goal it moves each frame in each part.
    float level = 0;
    float attackRate = 0;
    float decayRate = 0;
    float releaseRate = 0;

    /// 1 while the voice sounds; run down to 0 when it is taken.
    float fade = 1;
    float fadeStep = 0;

    /// The patch's filter (two in a row when it is steep), and the note's
    /// own brightness after it.
    Lowpass filter;
    Lowpass steeper;
    Lowpass brightener;
    float brightness = 1;
    float brightnessGoal = 1;

    /// How much of the voice goes left and right.
    float side[2] = {1, 1};
    /// How much chorus and reverb the note has now, and is gliding to.
    float chorus = 0;
    float chorusGoal = 0;
    float reverb = 0;
    float reverbGoal = 0;
    /// How much of the note is for the vocoder, now and where it is going.
    float vocoder = 0;
    float vocoderGoal = 0;
    /// How much of the note is echoed, now and where it is going.
    float delay = 0;
    float delayGoal = 0;
    /// How loud the note is beside itself played whole, now and where it
    /// is going.
    float gain = 1;
    float gainGoal = 1;
    /// What that makes the voice's share of each path, and how far each
    /// moves a frame.
    float share[pathCount] = {1, 0, 0, 0, 0};
    float shareStep[pathCount] = {0, 0, 0, 0, 0};

    /// The shares of each path for `chorus`, `reverb` and `vocoder`. Chorus
    /// at its fullest is as much copy as sound; reverb takes from both; and
    /// what goes to the vocoder, while it is on (`vocoding`), is taken from
    /// all three, since it is heard only as the vocoder shapes it. What is
    /// echoed is sent to the delay as well, and taken from nothing. Every
    /// path has the note as loud as it is played (`gain`).
    void shares(float out[pathCount], bool vocoding) const {
        const float sent = vocoding ? vocoder : 0;
        out[dry] = gain * (1 - sent) * (1 - reverb) * (1 - 0.5f * chorus);
        out[toChorus] = gain * (1 - sent) * (1 - reverb) * 0.5f * chorus;
        out[toReverb] = gain * (1 - sent) * reverb;
        out[toVocoder] = gain * sent;
        out[toDelay] = gain * (1 - sent) * delay;
    }

    /// The narrowest and the widest a pulse may be.
    static constexpr float narrowest = 0.01f;
    static constexpr float widest = 0.99f;

    /// A pulse that is high for `width` of each cycle, at `phase`, from
    /// the sawtooth `saw` is at `phase` and the one it is `width` of a
    /// cycle behind. With its offset gone a pulse swings between
    /// 2(1 - width) and -2·width; it is scaled so the larger of the two is 1.
    static float pulse(float saw, float behind, float width) {
        return (behind - saw) * 0.5f / std::max(width, 1 - width);
    }

    /// The pitch the voice is at, on its way to its note's.
    double pitch() const { return hz * std::pow(2.0, glide + pitchBend / 12.0); }

    /// The pitch of the voice's note as it is bent now, whatever it glides
    /// there from.
    double bent() const { return hz * std::pow(2.0, pitchBend / 12.0); }

    /// The next sample of noise, from -1 to 1.
    float hiss() {
        noiseState ^= noiseState << 13;
        noiseState ^= noiseState >> 17;
        noiseState ^= noiseState << 5;
        return static_cast<float>(static_cast<int32_t>(noiseState)) / 2147483648.0f;
    }

    /// How loud the voice is now, for choosing which to give up.
    float loudness() const { return level * velocity * gain * (sound ? sound->patch.level : 0); }
};

}

#endif
