// A sound as the kernel holds it: its patch, and the patch's waves built
// into tables a voice can read without doing any arithmetic on harmonics.

#ifndef PERFECTO_SOUND_HPP
#define PERFECTO_SOUND_HPP

#include "PerfectoKernel.h"

#include <vector>

namespace perfecto {

/// One cycle of a wave, several times over: each level holds half the
/// partials of the one before, so a note of any pitch has a level whose
/// partials all fall under half the sample rate and none folds back as a
/// false tone. Level 0 has `maxPartial` partials and the last has one.
class Wavetable {
public:
    static constexpr int levels = 11;
    static constexpr int size = 2048;
    static constexpr int maxPartial = 1 << (levels - 1);

    /// Builds the tables for `op`'s wave. Allocates.
    void build(const PerfectoOperator &op);

    /// The level for a wave moving `phaseStep` cycles a frame: the fullest
    /// one with nothing over half the sample rate.
    static int level(double phaseStep);

    /// The wave at `phase` (0..<1) on `level`, between its two nearest samples.
    float read(int level, double phase) const {
        const double at = phase * size;
        const int index = static_cast<int>(at);
        const float *table = samples.data() + level * (size + 1) + index;
        return table[0] + static_cast<float>(at - index) * (table[1] - table[0]);
    }

private:
    /// Each level is `size` samples and the first again, so reading
    /// between the last sample and the first needs no wrapping.
    std::vector<float> samples;
};

struct Sound {
    PerfectoPatch patch{};
    Wavetable waves[PerfectoOperatorCount];
    /// Each operator's share of the patch's level.
    float gains[PerfectoOperatorCount] = {0, 0};

    /// Takes `patch`, with anything out of range brought into it. Allocates.
    void load(const PerfectoPatch &patch);

    /// The sound a number never set plays: a sine that starts and ends
    /// without a click.
    static PerfectoPatch plainSine();
};

}

#endif
