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

struct Voice {
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
    };

    Stage stage = Stage::free;
    uint64_t id = 0;
    /// When the voice last started a note, as a count of notes started.
    uint64_t startedAt = 0;
    Waiting waiting;

    const Sound *sound = nullptr;
    /// The note's frequency, and frames since it started.
    double hz = 0;
    uint32_t age = 0;
    float velocity = 0;

    /// Each operator: where it is in its cycle (0..<1), how far it moves a
    /// frame, and the level of its wavetable that fits under half the
    /// sample rate at that speed.
    double phase[PerfectoOperatorCount] = {0, 0};
    double phaseStep[PerfectoOperatorCount] = {0, 0};
    int tableLevel[PerfectoOperatorCount] = {0, 0};
    /// How far the second operator bends the first one's phase, in cycles.
    float bend = 0;

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

    /// The patch's filter, and the note's own brightness after it.
    Lowpass filter;
    Lowpass brightener;
    float brightness = 1;
    float brightnessGoal = 1;

    /// How loud the voice is now, for choosing which to give up.
    float loudness() const { return level * velocity * (sound ? sound->patch.level : 0); }
};

}

#endif
