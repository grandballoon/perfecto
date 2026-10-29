#include "perfecto/desk/voice_leading.hpp"

#include <algorithm>

namespace perfecto::desk::VoiceLeading {

using namespace theory;

const PieGate &gate() {
    static const PieGate pie = PieGate::even(8);
    return pie;
}

const PieGate &bassGate() {
    static const PieGate pie({0, 180}, 60);
    return pie;
}

namespace {

std::optional<std::vector<int>> ordered(const std::vector<int> &notes) {
    for (size_t i = 0; i + 1 < notes.size(); ++i)
        if (!(notes[i] < notes[i + 1])) return std::nullopt;
    if (!std::all_of(notes.begin(), notes.end(), [](int note) { return range.contains(note); })) return std::nullopt;
    return notes;
}

/// `pitches` as tones above `root`, ascending.
std::vector<int> above(const std::set<int> &pitches, int root) {
    std::vector<int> tones;
    for (int pitch : pitches) tones.push_back((pitch - root + 12) % 12);
    std::sort(tones.begin(), tones.end());
    return tones;
}

} // namespace

std::optional<std::vector<int>> moved(const std::vector<int> &notes, const VoiceMove &move) {
    if (notes.size() < 3) return std::nullopt;
    std::vector<int> next = notes;
    const Motion motion = moves[static_cast<size_t>(move.direction)];
    next[next.size() - 1] += motion.top * move.shell;
    next[next.size() - 2] += motion.middle * move.shell;
    return ordered(next);
}

std::optional<std::vector<int>> bassMoved(const std::vector<int> &notes, const VoiceMove &move) {
    if (notes.size() < 2) return std::nullopt;
    std::vector<int> next = notes;
    next[0] += (move.direction == 0 ? 1 : -1) * move.shell;
    return ordered(next);
}

const std::vector<std::vector<int>> &consonant() {
    static const std::vector<std::vector<int>> qualities = {
        {0, 4, 7}, {0, 3, 7}, {0, 5, 7},
        {0, 4, 7, 10}, {0, 4, 7, 11}, {0, 3, 7, 10}, {0, 3, 6, 10}, {0, 5, 7, 10},
        {0, 2, 4, 7}, {0, 2, 3, 7},
        {0, 3, 6}, {0, 4, 8}, {0, 3, 6, 9},
        {0, 2, 4, 7, 10}, {0, 2, 4, 7, 11}, {0, 2, 3, 7, 10}, {0, 2, 4, 7, 9}, {0, 2, 5, 7, 10},
    };
    return qualities;
}

bool isConsonant(const std::set<int> &pitches) {
    if (pitches.size() < 3) return false;
    const auto &qualities = consonant();
    return std::any_of(pitches.begin(), pitches.end(), [&](int root) {
        return std::find(qualities.begin(), qualities.end(), above(pitches, root)) != qualities.end();
    });
}

std::optional<DeskChord> chord(const std::vector<int> &notes, const Key &key) {
    std::set<int> pitches;
    for (int note : notes) pitches.insert(((note % 12) + 12) % 12);
    if (pitches.size() < 3) return std::nullopt;
    const int bass = (((notes.empty() ? 0 : notes.front()) % 12) + 12) % 12;
    const auto &qualities = consonant();
    // Swift goes through a `Set`, in no defined order, and keeps the first of
    // equal scores; two roots can score alike only on a chord that divides
    // the octave evenly, and there the bass is always among them and scores
    // lower, so the order never changes the answer.
    std::optional<int> bestScore, bestRoot;
    for (int root : pitches) {
        const auto found = std::find(qualities.begin(), qualities.end(), above(pitches, root));
        if (found == qualities.end()) continue;
        const int rank = static_cast<int>(found - qualities.begin());
        // The bass as the root wins a tie of plainness, and is worth a step of it.
        const int score = rank * 2 + (root == bass ? 0 : 1);
        if (!bestScore || score < *bestScore) {
            bestScore = score;
            bestRoot = root;
        }
    }
    if (!bestRoot) return std::nullopt;
    return DeskChord::onRoot(pitchClass(*bestRoot), ChordTones(above(pitches, *bestRoot)), key, notes);
}

std::optional<DeskChord> neighbour(const std::vector<int> &notes, const VoiceMove &move, const Key &key) {
    const auto next = moved(notes, move);
    if (!next) return std::nullopt;
    return chord(*next, key);
}

std::optional<DeskChord> bassNeighbour(const std::vector<int> &notes, const VoiceMove &move, const Key &key) {
    const auto next = bassMoved(notes, move);
    if (!next) return std::nullopt;
    return chord(*next, key);
}

} // namespace perfecto::desk::VoiceLeading
