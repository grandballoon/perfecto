#include "perfecto/theory/color_steps.hpp"

#include "perfecto/theory/naming.hpp"

#include <algorithm>
#include <cstdlib>
#include <set>

namespace perfecto::theory {

namespace {

int classOf(int semitones) { return ((semitones % 12) + 12) % 12; }

/// A chord has at most seven notes, so every pairing can be tried.
int cheapest(const std::vector<int> &gone, const std::vector<int> &come) {
    if (gone.empty()) return static_cast<int>(come.size());
    if (come.empty()) return static_cast<int>(gone.size());
    const int first = gone.front();
    const std::vector<int> rest(gone.begin() + 1, gone.end());
    int best = 1 + cheapest(rest, come);
    for (size_t i = 0; i < come.size(); ++i) {
        const int apart = std::abs(first - come[i]);
        const int move = std::min(std::min(apart, 12 - apart), 2);
        std::vector<int> others = come;
        others.erase(others.begin() + static_cast<std::ptrdiff_t>(i));
        best = std::min(best, move + cheapest(rest, others));
    }
    return best;
}

} // namespace

int colorSteps(const std::vector<int> &a, const std::vector<int> &b) {
    std::set<int> as, bs;
    for (int n : a) as.insert(classOf(n));
    for (int n : b) bs.insert(classOf(n));
    std::vector<int> gone, come;
    std::set_difference(as.begin(), as.end(), bs.begin(), bs.end(), std::back_inserter(gone));
    std::set_difference(bs.begin(), bs.end(), as.begin(), as.end(), std::back_inserter(come));
    return cheapest(gone, come);
}

int colorSteps(const ChordColor &a, const ChordColor &b, const Key &key, Degree degree) {
    return colorSteps(chordShape(key, ChordSpec{degree, a}).intervals, chordShape(key, ChordSpec{degree, b}).intervals);
}

} // namespace perfecto::theory
