#include "perfecto/theory/voicing.hpp"

#include "perfecto/theory/naming.hpp"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <set>

namespace perfecto::theory {

namespace {

int fold(int note) {
    while (note > Voicing::midiHigh) note -= 12;
    while (note < Voicing::midiLow) note += 12;
    return note;
}

/// Sum of each note's distance to the nearest note in the reference voicing.
int voiceLeadingCost(const std::vector<int> &a, const std::vector<int> &b) {
    int total = 0;
    for (int note : a) {
        int nearest = -1;
        for (int other : b) {
            const int apart = std::abs(note - other);
            if (nearest < 0 || apart < nearest) nearest = apart;
        }
        total += std::max(nearest, 0);
    }
    return total;
}

} // namespace

Voicing::Voicing(const std::vector<int> &notes, std::optional<int> bassNote) {
    std::set<int> folded;
    for (int note : notes) folded.insert(fold(note));
    notes_.assign(folded.begin(), folded.end());
    if (bassNote) bassNote_ = fold(*bassNote);
}

std::vector<int> Inversion::applied(const std::vector<int> &intervals) const {
    constexpr int octave = 12;
    std::vector<int> sorted = intervals;
    std::sort(sorted.begin(), sorted.end());
    // The notes that are inverted, and those kept above them. A chord with
    // nothing within an octave of its root is all inverted.
    std::vector<int> core, upper;
    for (int n : sorted) (n < octave ? core : upper).push_back(n);
    if (core.empty()) std::swap(core, upper);
    if (core.empty() || sorted.size() < 2) return sorted;

    // Whole turns of the inverted notes are octaves; the steps left over
    // each take the lowest of them up one.
    const int count = static_cast<int>(core.size());
    const int turns = static_cast<int>(std::floor(static_cast<double>(steps) / count));
    const int left = steps - turns * count;
    std::vector<int> rolled(core.begin() + left, core.end());
    for (int i = 0; i < left; ++i) rolled.push_back(core[i] + octave);
    for (int &n : rolled) n += turns * octave;
    for (int &n : upper) n += turns * octave;
    if (!upper.empty() && upper.front() <= rolled.back()) {
        const int lift = (rolled.back() - upper.front()) / octave + 1;
        for (int &n : upper) n += lift * octave;
    }
    rolled.insert(rolled.end(), upper.begin(), upper.end());
    return rolled;
}

Voicing computeVoicing(const Key &key, const ChordSpec &spec, Inversion inversion, int octave, bool voiceLeading,
                       const std::optional<Voicing> &previousVoicing) {
    // Same shape the on-screen label is read from, so the notes and the
    // displayed name can never disagree (see naming.hpp).
    const std::vector<int> intervals = chordShape(key, spec).intervals;
    const int chordRoot = raw(key.root) + (octave + 1) * 12 + offset(key.scale, spec.degree);

    // The chord rolled to `inv`, `octaveShift` octaves from its own.
    const auto build = [&](Inversion inv, int octaveShift) {
        std::vector<int> notes = inv.applied(intervals);
        for (int &n : notes) n += chordRoot + octaveShift * 12;
        return notes;
    };

    if (voiceLeading && previousVoicing && !previousVoicing->notes().empty()) {
        const auto &previous = previousVoicing->notes();
        std::vector<int> best = build(inversion, 0);
        int bestCost = voiceLeadingCost(best, previous);
        for (int shift : {-1, 0, 1}) {
            for (Inversion inv : {Inversion::root(), Inversion::first(), Inversion::second()}) {
                std::vector<int> candidate = build(inv, shift);
                const int cost = voiceLeadingCost(candidate, previous);
                if (cost < bestCost) {
                    bestCost = cost;
                    best = std::move(candidate);
                }
            }
        }
        return Voicing(best);
    }
    return Voicing(build(inversion, 0));
}

} // namespace perfecto::theory
