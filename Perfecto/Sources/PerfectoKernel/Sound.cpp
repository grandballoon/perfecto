#include "Sound.hpp"

#include <algorithm>
#include <cmath>

namespace perfecto {

namespace {

constexpr double pi = 3.141592653589793;

/// Partial `n` of a wave, as a cosine part and a sine part.
struct Partial {
    double cosine = 0;
    double sine = 0;
};

/// The Fourier series of each wave. A wave's steady offset is left out: it
/// cannot be heard and only takes room under full scale.
Partial partial(const PerfectoOperator &op, int n) {
    const bool odd = n % 2 == 1;
    switch (op.wave) {
    case PerfectoWaveSine:
        return {0, n == 1 ? 1.0 : 0.0};
    case PerfectoWaveTriangle:
        return {0, odd ? (n % 4 == 1 ? 1 : -1) * 8 / (pi * pi * n * n) : 0};
    case PerfectoWaveSquare:
        return {0, odd ? 4 / (pi * n) : 0};
    case PerfectoWaveSawtooth:
        return {0, -2 / (pi * n)};
    case PerfectoWavePulse: {
        // With its offset gone, a pulse of width w swings between
        // 2(1 - w) and -2w; it is scaled so the larger of the two is 1.
        const double width = std::clamp(static_cast<double>(op.pulse_width), 0.01, 0.99);
        const double scale = 1 / (pi * n * std::max(width, 1 - width));
        return {scale * std::sin(2 * pi * n * width), scale * (1 - std::cos(2 * pi * n * width))};
    }
    case PerfectoWavePartials:
        return {0, n <= PerfectoPartialCount ? op.partials[n - 1] : 0};
    }
    return {};
}

}

void Wavetable::build(const PerfectoOperator &op) {
    // One cycle of a sine, to read every partial from: partial n at sample
    // i is the sine at sample n·i, wrapped.
    std::vector<double> sine(size);
    for (int i = 0; i < size; ++i) sine[i] = std::sin(2 * pi * i / size);

    // From the level with fewest partials to the one with most, each built
    // on the one before by adding the partials it lacks.
    std::vector<double> cycle(size, 0.0);
    samples.assign(static_cast<std::size_t>(levels) * (size + 1), 0.0f);
    int built = 0;
    for (int level = levels - 1; level >= 0; --level) {
        const int partials = maxPartial >> level;
        for (int n = built + 1; n <= partials; ++n) {
            const Partial part = partial(op, n);
            if (part.cosine == 0 && part.sine == 0) continue;
            for (int i = 0; i < size; ++i) {
                const int at = (n * i) % size;
                cycle[i] += part.sine * sine[at] + part.cosine * sine[(at + size / 4) % size];
            }
        }
        built = partials;
        float *table = samples.data() + level * (size + 1);
        for (int i = 0; i < size; ++i) table[i] = static_cast<float>(cycle[i]);
        table[size] = table[0];
    }

    // A wave given as partials peaks wherever they happen to add up; it is
    // scaled to peak at 1 like the named waves, every level by the same
    // amount so a note's level does not change its loudness.
    if (op.wave == PerfectoWavePartials) {
        float peak = 0;
        for (int i = 0; i < size; ++i) peak = std::max(peak, std::abs(samples[i]));
        if (peak > 0) for (float &sample : samples) sample /= peak;
    }
}

int Wavetable::level(double phaseStep) {
    const double fit = 0.5 / std::max(phaseStep, 1e-9);
    int level = 0;
    while (level < levels - 1 && (maxPartial >> level) > fit) ++level;
    return level;
}

void Sound::load(const PerfectoPatch &given) {
    patch = given;
    patch.resonance = std::clamp(patch.resonance, 0.0f, 1.0f);
    patch.sustain = std::clamp(patch.sustain, 0.0f, 1.0f);
    patch.level = std::max(patch.level, 0.0f);
    patch.root = std::clamp(patch.root, 0.0f, 127.0f);
    float total = 0;
    for (int i = 0; i < PerfectoOperatorCount; ++i) {
        auto &op = patch.operators[i];
        op.level = std::max(op.level, 0.0f);
        op.ratio = std::max(op.ratio, 0.0f);
        waves[i].build(op);
        // A modulator is not heard, so the carrier has the whole level.
        if (!(patch.modulates && i == 1)) total += op.level;
    }
    for (int i = 0; i < PerfectoOperatorCount; ++i) {
        const bool heard = !(patch.modulates && i == 1);
        gains[i] = heard && total > 0 ? patch.level * patch.operators[i].level / total : 0;
    }
}

PerfectoPatch Sound::plainSine() {
    PerfectoPatch patch{};
    patch.operators[0].wave = PerfectoWaveSine;
    patch.operators[0].ratio = 1;
    patch.operators[0].level = 1;
    patch.attack = 0.003f;
    patch.decay = 0.05f;
    patch.sustain = 1;
    patch.release = 0.006f;
    patch.level = 0.2f;
    return patch;
}

}
