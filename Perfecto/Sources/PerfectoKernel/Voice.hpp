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
    /// The paths a voice's sound takes: straight to the output, and into
    /// the chorus, the reverb and the vocoder.
    enum Path { dry = 0, toChorus, toReverb, toVocoder, pathCount };

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

    /// For a sound that is a capture: the recording, where the voice is in
    /// it (in its frames) and how far it moves a frame, the frame it ends
    /// before, and the level it is played at. `recording` is null otherwise.
    const float *recording = nullptr;
    double position = 0;
    double positionStep = 0;
    int32_t recordingStart = 0;
    int32_t recordingEnd = 0;
    float recordingGain = 1;
    /// Which capture, so the voice can be ended when it is recorded over.
    int32_t capture = -1;

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
    /// What that makes the voice's share of each path, and how far each
    /// moves a frame.
    float share[pathCount] = {1, 0, 0, 0};
    float shareStep[pathCount] = {0, 0, 0, 0};

    /// The shares of each path for `chorus`, `reverb` and `vocoder`. Chorus
    /// at its fullest is as much copy as sound; reverb takes from both; and
    /// what goes to the vocoder, while it is on (`vocoding`), is taken from
    /// all three, since it is heard only as the vocoder shapes it.
    void shares(float out[pathCount], bool vocoding) const {
        const float sent = vocoding ? vocoder : 0;
        out[dry] = (1 - sent) * (1 - reverb) * (1 - 0.5f * chorus);
        out[toChorus] = (1 - sent) * (1 - reverb) * 0.5f * chorus;
        out[toReverb] = (1 - sent) * reverb;
        out[toVocoder] = sent;
    }

    /// How loud the voice is now, for choosing which to give up.
    float loudness() const { return level * velocity * (sound ? sound->patch.level : 0); }
};

}

#endif
