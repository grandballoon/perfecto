#include "perfecto/theory/tone_marks.hpp"

#include "perfecto/theory/require.hpp"

#include <algorithm>

namespace perfecto::theory {

namespace {

/// Which third of the stack a tone is: the 3rd is the first above the root.
int stackIndex(ChordTone tone) { return (raw(tone) - 1) / 2; }

/// The semitones above the root a mark can take the tone to, each of which
/// has a name: a 7th lowered to 9 is a 6th, and one raised past 11 would be
/// the root.
bool inRange(ChordTone tone, int semitones) {
    int low = 0, high = 0;
    switch (tone) {
    case ChordTone::third: low = 2, high = 5; break;
    case ChordTone::fifth: low = 6, high = 8; break;
    case ChordTone::seventh: low = 9, high = 11; break;
    case ChordTone::ninth: low = 13, high = 15; break;
    case ChordTone::eleventh: low = 16, high = 18; break;
    case ChordTone::thirteenth: low = 20, high = 22; break;
    }
    return semitones >= low && semitones <= high;
}

std::string joined(const std::vector<std::string> &parts, const std::string &separator) {
    std::string out;
    for (std::size_t i = 0; i < parts.size(); ++i) out += (i ? separator : "") + parts[i];
    return out;
}

} // namespace

std::string name(ChordTone tone, int semitones) {
    if (tone == ChordTone::third) {
        if (semitones == 2) return "sus2";
        if (semitones == 3) return "♭3";
        if (semitones == 4) return "3";
        if (semitones == 5) return "sus4";
    }
    if (tone == ChordTone::seventh) {
        if (semitones == 9) return "6";
        if (semitones == 10) return "♭7";
        if (semitones == 11) return "maj7";
    }
    int natural = 0;
    switch (tone) {
    case ChordTone::fifth: natural = 7; break;
    case ChordTone::ninth: natural = 14; break;
    case ChordTone::eleventh: natural = 17; break;
    case ChordTone::thirteenth: natural = 21; break;
    default: PERFECTO_REQUIRE(false, "a tone with no name there");
    }
    const int offset = semitones - natural;
    return std::string(offset < 0 ? "♭" : offset > 0 ? "♯" : "") + std::to_string(raw(tone));
}

int ToneMarks::move(ChordTone tone) const {
    const auto found = moves_.find(tone);
    return found == moves_.end() ? 0 : found->second;
}

void ToneMarks::toggleMove(ChordTone tone, int offset) {
    PERFECTO_REQUIRE(offset == 1 || offset == -1, "a mark moves a tone one semitone");
    if (move(tone) == offset) moves_.erase(tone);
    else moves_[tone] = offset;
}

void ToneMarks::toggleSkip(ChordTone tone) {
    if (!skips_.erase(tone)) skips_.insert(tone);
}

void ToneMarks::setMove(ChordTone tone, int offset) {
    PERFECTO_REQUIRE(offset >= -1 && offset <= 1, "a mark moves a tone one semitone");
    if (offset == 0) moves_.erase(tone);
    else moves_[tone] = offset;
}

void ToneMarks::setSkip(ChordTone tone, bool isOn) {
    if (isOn) skips_.insert(tone);
    else skips_.erase(tone);
}

std::vector<StackedTone> stackedTones(const std::vector<int> &mode, StackHeight height) {
    PERFECTO_REQUIRE(mode.size() == 7 && mode.front() == 0, "a mode is seven intervals from 0");
    std::vector<StackedTone> out;
    for (int i = 0; i < raw(height) - 1; ++i) {
        const ChordTone tone = allChordTones[i];
        const int step = 2 * stackIndex(tone);
        out.push_back({tone, mode[step % 7] + (step / 7) * 12});
    }
    return out;
}

std::set<ChordTone> droppedTones(const std::vector<int> &mode, StackHeight height) {
    const auto tones = stackedTones(mode, height);
    if (tones.size() <= 4 || tones[0].semitones != 4 || tones[4].semitones != 17) return {};
    return {height == StackHeight::eleventh ? ChordTone::third : ChordTone::eleventh};
}

std::vector<MarkedTone> markedTones(const std::vector<int> &mode, StackHeight height, const ToneMarks &marks) {
    const auto dropped = droppedTones(mode, height);
    std::vector<StackedTone> present;
    for (const auto &t : stackedTones(mode, height))
        if ((dropped.count(t.tone) > 0) == marks.skips(t.tone)) present.push_back(t);
    std::vector<int> sounding;
    for (const auto &t : present) sounding.push_back(t.semitones);
    for (std::size_t i = 0; i < present.size(); ++i) {
        const int offset = marks.move(present[i].tone);
        if (offset == 0) continue;
        const int target = present[i].semitones + offset;
        std::set<int> others = {0};
        for (std::size_t j = 0; j < sounding.size(); ++j)
            if (j != i) others.insert(sounding[j] % 12);
        if (inRange(present[i].tone, target) && !others.count(target % 12)) sounding[i] = target;
    }
    std::vector<MarkedTone> out;
    for (std::size_t i = 0; i < present.size(); ++i) out.push_back({present[i].tone, present[i].semitones, sounding[i]});
    return out;
}

std::vector<int> markedStack(const std::vector<int> &mode, StackHeight height, const ToneMarks &marks) {
    std::vector<int> out = {0};
    for (const auto &t : markedTones(mode, height, marks)) out.push_back(t.sounding);
    return out;
}

std::vector<std::string> markNames(const std::vector<int> &mode, StackHeight height, const ToneMarks &marks) {
    const auto dropped = droppedTones(mode, height);
    const auto sounding = markedTones(mode, height, marks);
    std::vector<std::string> out;
    for (const auto &entry : stackedTones(mode, height)) {
        if (marks.skips(entry.tone)) {
            out.push_back((dropped.count(entry.tone) ? "add " : "no ") + std::to_string(raw(entry.tone)));
            continue;
        }
        const auto marked = std::find_if(sounding.begin(), sounding.end(),
                                         [&](const MarkedTone &t) { return t.tone == entry.tone; });
        if (marked != sounding.end() && marked->isMoved()) out.push_back(name(entry.tone, marked->sounding));
    }
    return out;
}

std::string markedChordName(HeptatonicMode mode, StackHeight height, const ToneMarks &marks) {
    const std::string stack = tertianChordName(mode, height);
    const auto added = markNames(intervals(mode), height, marks);
    return added.empty() ? stack : stack + "(" + joined(added, ", ") + ")";
}

std::vector<ToneMarkOption> toneMarkOptions(const std::vector<int> &mode, StackHeight height,
                                            const ToneMarks &marks) {
    const auto stacked = stackedTones(mode, height);
    const auto dropped = droppedTones(mode, height);
    const auto sounding = markedTones(mode, height, marks);
    std::vector<ToneMarkOption> out;
    for (ChordTone tone : allChordTones) {
        const auto entry =
            std::find_if(stacked.begin(), stacked.end(), [&](const StackedTone &t) { return t.tone == tone; });
        if (entry == stacked.end()) {
            out.push_back({tone, false, false, false, std::nullopt, std::nullopt, 0});
            continue;
        }
        const auto here =
            std::find_if(sounding.begin(), sounding.end(), [&](const MarkedTone &t) { return t.tone == tone; });
        const bool present = here != sounding.end();
        std::set<int> others = {0};
        for (const auto &t : sounding)
            if (t.tone != tone) others.insert(t.sounding % 12);
        const auto moveName = [&](int offset) -> std::optional<std::string> {
            const int target = entry->semitones + offset;
            if (!present || !inRange(tone, target) || others.count(target % 12)) return std::nullopt;
            return name(tone, target);
        };
        out.push_back({tone, true, !present, dropped.count(tone) > 0, moveName(1), moveName(-1),
                       present ? here->sounding - here->stacked : 0});
    }
    return out;
}

} // namespace perfecto::theory
