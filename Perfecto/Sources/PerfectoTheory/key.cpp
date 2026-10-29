#include "perfecto/theory/key.hpp"

#include <algorithm>
#include <cmath>
#include <cstdlib>

namespace perfecto::theory {

PitchClass pitchClass(int semitones) { return static_cast<PitchClass>((semitones % 12 + 12) % 12); }

std::string name(PitchClass p) {
    static const std::array<const char *, 12> names = {"C",  "C#", "D",  "D#", "E",  "F",
                                                       "F#", "G",  "G#", "A",  "A#", "B"};
    return names[raw(p)];
}

std::optional<Degree> degree(int number) {
    if (number < 1 || number > 7) return std::nullopt;
    return static_cast<Degree>(number);
}

std::string displayName(ScaleType s) {
    switch (s) {
    case ScaleType::major: return "Major";
    case ScaleType::naturalMinor: return "Natural Minor";
    case ScaleType::harmonicMinor: return "Harmonic Minor";
    case ScaleType::melodicMinor: return "Melodic Minor";
    case ScaleType::majorPentatonic: return "Maj. Pentatonic";
    case ScaleType::minorPentatonic: return "Min. Pentatonic";
    case ScaleType::blues: return "Blues";
    case ScaleType::dorian: return "Dorian";
    case ScaleType::mixolydian: return "Mixolydian";
    case ScaleType::lydian: return "Lydian";
    }
    return "";
}

const std::vector<int> &intervals(ScaleType s) {
    static const std::vector<int> major = {0, 2, 4, 5, 7, 9, 11};
    static const std::vector<int> naturalMinor = {0, 2, 3, 5, 7, 8, 10};
    static const std::vector<int> harmonicMinor = {0, 2, 3, 5, 7, 8, 11};
    static const std::vector<int> melodicMinor = {0, 2, 3, 5, 7, 9, 11};
    static const std::vector<int> majorPentatonic = {0, 2, 4, 7, 9};
    static const std::vector<int> minorPentatonic = {0, 3, 5, 7, 10};
    static const std::vector<int> blues = {0, 3, 5, 6, 7, 10};
    static const std::vector<int> dorian = {0, 2, 3, 5, 7, 9, 10};
    static const std::vector<int> mixolydian = {0, 2, 4, 5, 7, 9, 10};
    static const std::vector<int> lydian = {0, 2, 4, 6, 7, 9, 11};
    switch (s) {
    case ScaleType::major: return major;
    case ScaleType::naturalMinor: return naturalMinor;
    case ScaleType::harmonicMinor: return harmonicMinor;
    case ScaleType::melodicMinor: return melodicMinor;
    case ScaleType::majorPentatonic: return majorPentatonic;
    case ScaleType::minorPentatonic: return minorPentatonic;
    case ScaleType::blues: return blues;
    case ScaleType::dorian: return dorian;
    case ScaleType::mixolydian: return mixolydian;
    case ScaleType::lydian: return lydian;
    }
    return major;
}

bool isHeptatonic(ScaleType s) { return intervals(s).size() == 7; }

int semitones(ScaleType s, int step) {
    const auto &steps = intervals(s);
    const int n = static_cast<int>(steps.size());
    return steps[step % n] + (step / n) * 12;
}

int offset(ScaleType s, Degree degree) { return semitones(s, index(degree)); }

bool Key::has(int note) const {
    const auto &steps = intervals(scale);
    return std::find(steps.begin(), steps.end(), ((note - raw(root)) % 12 + 12) % 12) != steps.end();
}

int Key::noteNearest(double pitch) const {
    const int middle = static_cast<int>(std::floor(pitch));
    // No scale has a gap of more than three semitones; of two as near, the
    // first found, which is the lower.
    std::optional<int> best;
    for (int note = middle - 3; note <= middle + 4; ++note) {
        if (!has(note)) continue;
        if (!best || std::abs(note - pitch) < std::abs(*best - pitch)) best = note;
    }
    return best.value_or(middle);
}

int Key::offsetOf(PitchClass pitch) const { return (raw(pitch) - raw(root) + 12) % 12; }

std::optional<Degree> Key::degreeOf(PitchClass pitch) const {
    const auto &steps = intervals(scale);
    const auto found = std::find(steps.begin(), steps.end(), offsetOf(pitch));
    if (found == steps.end()) return std::nullopt;
    return degree(static_cast<int>(found - steps.begin()) + 1);
}

bool Key::isMinor() const {
    const auto &steps = intervals(scale);
    const auto has = [&](int i) { return std::find(steps.begin(), steps.end(), i) != steps.end(); };
    return has(3) && !has(4);
}

} // namespace perfecto::theory
