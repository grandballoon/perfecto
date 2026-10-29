#include "perfecto/theory/modes.hpp"

#include "perfecto/theory/require.hpp"
#include "perfecto/theory/tertian.hpp"

#include <algorithm>
#include <numeric>
#include <set>

namespace perfecto::theory {

namespace {

struct Rotation {
    ScaleType parent;
    int step;
};

Rotation rotation(HeptatonicMode m) {
    const int i = static_cast<int>(m);
    const ScaleType parents[] = {ScaleType::major, ScaleType::melodicMinor, ScaleType::harmonicMinor};
    return {parents[i / 7], i % 7};
}

ScaleType parent(ScaleFamily f) {
    switch (f) {
    case ScaleFamily::major: return ScaleType::major;
    case ScaleFamily::harmonicMinor: return ScaleType::harmonicMinor;
    case ScaleFamily::melodicMinor: return ScaleType::melodicMinor;
    }
    return ScaleType::major;
}

} // namespace

std::string displayName(HeptatonicMode m) {
    switch (m) {
    case HeptatonicMode::ionian: return "Ionian";
    case HeptatonicMode::dorian: return "Dorian";
    case HeptatonicMode::phrygian: return "Phrygian";
    case HeptatonicMode::lydian: return "Lydian";
    case HeptatonicMode::mixolydian: return "Mixolydian";
    case HeptatonicMode::aeolian: return "Aeolian";
    case HeptatonicMode::locrian: return "Locrian";
    case HeptatonicMode::melodicMinor: return "Melodic Minor";
    case HeptatonicMode::dorianFlat2: return "Dorian ♭2";
    case HeptatonicMode::lydianAugmented: return "Lydian Augmented";
    case HeptatonicMode::lydianDominant: return "Lydian Dominant";
    case HeptatonicMode::mixolydianFlat6: return "Mixolydian ♭6";
    case HeptatonicMode::locrianNatural2: return "Locrian ♮2";
    case HeptatonicMode::altered: return "Altered";
    case HeptatonicMode::harmonicMinor: return "Harmonic Minor";
    case HeptatonicMode::locrianNatural6: return "Locrian ♮6";
    case HeptatonicMode::ionianSharp5: return "Ionian ♯5";
    case HeptatonicMode::dorianSharp4: return "Dorian ♯4";
    case HeptatonicMode::phrygianDominant: return "Phrygian Dominant";
    case HeptatonicMode::lydianSharp2: return "Lydian ♯2";
    case HeptatonicMode::ultralocrian: return "Ultralocrian";
    }
    return "";
}

std::string displayName(ScaleFamily f) {
    switch (f) {
    case ScaleFamily::major: return "Major";
    case ScaleFamily::harmonicMinor: return "Harmonic Minor";
    case ScaleFamily::melodicMinor: return "Melodic Minor";
    }
    return "";
}

ScaleFamily family(HeptatonicMode m) {
    const ScaleType p = rotation(m).parent;
    for (ScaleFamily f : allScaleFamilies)
        if (parent(f) == p) return f;
    return ScaleFamily::major;
}

int number(HeptatonicMode m) { return rotation(m).step + 1; }

const std::vector<int> &intervals(HeptatonicMode m) {
    static const auto table = [] {
        std::array<std::vector<int>, allHeptatonicModes.size()> all;
        for (HeptatonicMode mode : allHeptatonicModes) {
            const auto [parent, step] = rotation(mode);
            const int root = semitones(parent, step);
            std::vector<int> steps;
            for (int i = 0; i < 7; ++i) steps.push_back(semitones(parent, step + i) - root);
            all[static_cast<int>(mode)] = steps;
        }
        return all;
    }();
    return table[static_cast<int>(m)];
}

std::optional<HeptatonicMode> modeWith(const std::vector<int> &steps) {
    for (HeptatonicMode m : allHeptatonicModes)
        if (intervals(m) == steps) return m;
    return std::nullopt;
}

std::optional<HeptatonicMode> ownModeOf(const Key &key, Degree degree) {
    const auto steps = diatonicMode(key, degree);
    if (!steps) return std::nullopt;
    return modeWith(*steps);
}

const std::vector<HeptatonicMode> &byBrightness() {
    static const std::vector<HeptatonicMode> order = [] {
        const auto brightness = [](HeptatonicMode m) {
            const auto &s = intervals(m);
            return std::accumulate(s.begin(), s.end(), 0);
        };
        const auto changes = [](HeptatonicMode a, HeptatonicMode b) {
            int n = 0;
            for (int i = 0; i < 7; ++i) n += intervals(a)[i] != intervals(b)[i];
            return n;
        };
        const auto higher = [](HeptatonicMode a, HeptatonicMode b) {
            return std::lexicographical_compare(intervals(b).begin(), intervals(b).end(), intervals(a).begin(),
                                                intervals(a).end());
        };
        std::set<int, std::greater<>> levels;
        for (HeptatonicMode m : allHeptatonicModes) levels.insert(brightness(m));
        std::vector<HeptatonicMode> order;
        for (int level : levels) {
            std::vector<HeptatonicMode> remaining;
            for (HeptatonicMode m : allHeptatonicModes)
                if (brightness(m) == level) remaining.push_back(m);
            while (!remaining.empty()) {
                // The first of the least, as Swift's `min(by:)` takes it.
                const auto precedes = [&](HeptatonicMode a, HeptatonicMode b) {
                    if (order.empty()) return higher(a, b);
                    const int ca = changes(order.back(), a), cb = changes(order.back(), b);
                    return ca != cb ? ca < cb : higher(a, b);
                };
                auto next = remaining.begin();
                for (auto it = remaining.begin() + 1; it != remaining.end(); ++it)
                    if (precedes(*it, *next)) next = it;
                order.push_back(*next);
                remaining.erase(next);
            }
        }
        return order;
    }();
    return order;
}

std::vector<HeptatonicMode> rowsAround(HeptatonicMode center, int count) {
    const auto &all = byBrightness();
    const int size = static_cast<int>(all.size());
    PERFECTO_REQUIRE(count >= 1 && count <= size, "row count out of range");
    const int middle = static_cast<int>(std::find(all.begin(), all.end(), center) - all.begin());
    const int start = std::min(std::max(middle - count / 2, 0), size - count);
    return {all.begin() + start, all.begin() + start + count};
}

std::vector<HeptatonicMode> modes(ScaleFamily f) {
    std::vector<HeptatonicMode> out;
    for (HeptatonicMode m : allHeptatonicModes)
        if (family(m) == f) out.push_back(m);
    std::sort(out.begin(), out.end(), [](auto a, auto b) { return number(a) < number(b); });
    return out;
}

const std::vector<HeptatonicMode> &allModesByFamily() {
    static const std::vector<HeptatonicMode> all = [] {
        std::vector<HeptatonicMode> out;
        for (ScaleFamily f : allScaleFamilies) {
            const auto these = modes(f);
            out.insert(out.end(), these.begin(), these.end());
        }
        return out;
    }();
    return all;
}

} // namespace perfecto::theory
