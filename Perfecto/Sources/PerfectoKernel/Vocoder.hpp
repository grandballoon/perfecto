// The vocoder: one sound (the carrier: notes) shaped by another (the
// modulator: a voice at the mic). Both are split into the same bands of
// pitch, and how loud the voice is in each band, moment by moment, is how
// much of the notes' band is let through. What comes out has the notes'
// pitches and the voice's vowels and consonants.

#ifndef PERFECTO_VOCODER_HPP
#define PERFECTO_VOCODER_HPP

#include <algorithm>
#include <array>
#include <cmath>

namespace perfecto {

/// Lets through what is near one pitch, as loud as it came in, and less of
/// everything further from it (12 dB an octave either side, in the end).
struct Bandpass {
    float s1 = 0;
    float s2 = 0;
    float a1 = 0;
    float a2 = 0;
    float a3 = 0;
    float k = 1;

    /// Sets the pitch, in Hz, and how narrow the band is around it (`q`:
    /// the pitch over the width let through).
    void tune(double hz, double sampleRate, double q) {
        const double g = std::tan(3.141592653589793 * hz / sampleRate);
        k = static_cast<float>(1 / q);
        const double first = 1 / (1 + g * (g + 1 / q));
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
        return k * v1;
    }

    void clear() { s1 = s2 = 0; }
};

class Vocoder {
public:
    static constexpr int bands = 20;

    /// Readies it to run at `sampleRate`, silent.
    void prepare(double sampleRate) {
        const double top = std::min(highest, 0.4 * sampleRate);
        const double step = std::pow(top / lowest, 1.0 / (bands - 1));
        // Bands that meet where each has fallen to about half.
        const double q = 1 / (std::sqrt(step) - 1 / std::sqrt(step));
        for (int band = 0; band < bands; ++band) {
            const double hz = lowest * std::pow(step, band);
            for (auto &stage : voice[band]) stage.tune(hz, sampleRate, q);
            for (auto &stage : notes[band]) stage.tune(hz, sampleRate, q);
        }
        rise = static_cast<float>(1 - std::exp(-1 / (riseSeconds * sampleRate)));
        fall = static_cast<float>(1 - std::exp(-1 / (fallSeconds * sampleRate)));
        clear();
    }

    void clear() {
        for (int band = 0; band < bands; ++band) {
            for (auto &stage : voice[band]) stage.clear();
            for (auto &stage : notes[band]) stage.clear();
        }
        level.fill(0);
    }

    /// One frame: `carrier` as `modulator` shapes it.
    float run(float modulator, float carrier) {
        float out = 0;
        for (int band = 0; band < bands; ++band) {
            const float heard = std::abs(voice[band][1].run(voice[band][0].run(modulator)));
            // The level follows the voice up fast, so consonants are
            // crisp, and down slower, so a vowel does not flutter.
            level[band] += (heard - level[band]) * (heard > level[band] ? rise : fall);
            out += notes[band][1].run(notes[band][0].run(carrier)) * level[band];
        }
        return out * makeup;
    }

private:
    /// The bands run from the bottom of a voice to the top of its consonants, in Hz.
    static constexpr double lowest = 120;
    static constexpr double highest = 7500;
    static constexpr double riseSeconds = 0.002;
    static constexpr double fallSeconds = 0.02;
    /// A band of the notes is turned down by the voice's level in it,
    /// which even for a loud voice is small: this brings the whole back up,
    /// so that notes under a voice speaking close to the mic come out
    /// about as loud as they went in.
    static constexpr float makeup = 40;

    std::array<std::array<Bandpass, 2>, bands> voice{};
    std::array<std::array<Bandpass, 2>, bands> notes{};
    std::array<float, bands> level{};
    float rise = 0;
    float fall = 0;
};

}

#endif
