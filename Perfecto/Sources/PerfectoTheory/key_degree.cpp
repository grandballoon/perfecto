#include "perfecto/theory/key_degree.hpp"

#include "perfecto/theory/naming.hpp"
#include "perfecto/theory/require.hpp"

#include <algorithm>

namespace perfecto::theory {

const std::array<HeptatonicMode, 7> KeyDegree::parallelModes = {
    HeptatonicMode::lydian, HeptatonicMode::ionian,   HeptatonicMode::mixolydian, HeptatonicMode::dorian,
    HeptatonicMode::aeolian, HeptatonicMode::phrygian, HeptatonicMode::locrian,
};

namespace {

/// The key whose notes are `mode`'s on `tonic`: on that tonic where a scale
/// has the mode's intervals, the relative major otherwise.
Key keyOf(HeptatonicMode mode, PitchClass tonic) {
    for (ScaleType scale : allScaleTypes)
        if (intervals(scale) == intervals(mode)) return {tonic, scale};
    // The mode is the major scale read from one of its steps, so the major
    // key that far below the tonic has the same notes.
    const auto &major = intervals(ScaleType::major);
    for (int step : major) {
        std::vector<int> rotated;
        for (int i : major) rotated.push_back((i - step + 12) % 12);
        std::sort(rotated.begin(), rotated.end());
        if (rotated == intervals(mode)) return {pitchClass(raw(tonic) - step + 12), ScaleType::major};
    }
    PERFECTO_REQUIRE(false, "a parallel mode is a rotation of the major scale");
    return {tonic, ScaleType::major};
}

} // namespace

KeyDegree KeyDegree::onRoot(PitchClass root, const Key &key) {
    if (const auto degree = key.degreeOf(root)) return {key, *degree};
    const auto &home = intervals(key.scale);
    const int offset = key.offsetOf(root);
    // Every note is in one of them: Lydian and Locrian have all twelve
    // between them. The first of the fewest changes is the brighter.
    std::optional<HeptatonicMode> best;
    long bestChanges = 0;
    for (HeptatonicMode mode : parallelModes) {
        const auto &notes = intervals(mode);
        if (std::find(notes.begin(), notes.end(), offset) == notes.end()) continue;
        const long changes = std::count_if(notes.begin(), notes.end(), [&](int n) {
            return std::find(home.begin(), home.end(), n) == home.end();
        });
        if (!best || changes < bestChanges) {
            best = mode;
            bestChanges = changes;
        }
    }
    const Key borrowed = keyOf(*best, key.root);
    const auto degree = borrowed.degreeOf(root);
    PERFECTO_REQUIRE(degree.has_value(), "the borrowed key has the root");
    return {borrowed, *degree};
}

PitchClass KeyDegree::root() const { return chordRootPitchClass(key, degree); }

} // namespace perfecto::theory
