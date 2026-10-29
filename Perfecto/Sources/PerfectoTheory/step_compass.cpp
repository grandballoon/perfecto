#include "perfecto/theory/step_compass.hpp"

#include "perfecto/theory/grid.hpp"
#include "perfecto/theory/naming.hpp"
#include "perfecto/theory/require.hpp"

#include <algorithm>
#include <functional>

namespace perfecto::theory {

CompassPlace::CompassPlace(ColorStepKind kind, int rank) : kind_(kind), rank_(rank) {
    PERFECTO_REQUIRE(rank >= StepCompass::firstRank && rank <= StepCompass::lastRank,
                     "the compass has a first and a second choice");
}

const std::vector<CompassPlace> &CompassPlace::all() {
    static const std::vector<CompassPlace> places = [] {
        std::vector<CompassPlace> out;
        for (ColorStepKind kind : allColorStepKinds)
            for (int rank = StepCompass::firstRank; rank <= StepCompass::lastRank; ++rank) out.emplace_back(kind, rank);
        return out;
    }();
    return places;
}

std::string ColorStep::editName() const {
    static const char *names[] = {"1", "♭2", "2", "♭3", "3", "4", "♭5", "5", "♭6", "6", "♭7", "7"};
    switch (kind) {
    case ColorStepKind::add: return std::string("+") + names[*to];
    case ColorStepKind::takeAway: return std::string("−") + names[*from];
    case ColorStepKind::raise:
    case ColorStepKind::lower:
        return std::string(names[*from]) + "→" + (kind == ColorStepKind::raise && from == 7 ? "♯5" : names[*to]);
    }
    return {};
}

ChordTones chordTones(const Key &key, const ChordSpec &spec) { return ChordTones(chordShape(key, spec).intervals); }

namespace StepCompass {

namespace {

std::vector<ColorStep> neighbours(const ChordTones &tones, const std::function<bool(int)> &inKey) {
    const std::vector<int> &have = tones.pitchClasses();
    const auto make = [&](ColorStepKind kind, const std::vector<int> &next, std::optional<int> from,
                          std::optional<int> to) {
        ChordTones made(next);
        ColorFit fit = ColorFit::inKey;
        if (!std::all_of(made.pitchClasses().begin(), made.pitchClasses().end(), inKey)) fit = ColorFit::borrowed;
        else if (to && made.has((*to + 11) % 12)) fit = ColorFit::avoid;
        return ColorStep{kind, std::move(made), from, to, fit};
    };
    const auto without = [&](int tone) {
        std::vector<int> out;
        for (int t : have)
            if (t != tone) out.push_back(t);
        return out;
    };

    std::vector<ColorStep> out;
    for (int added = 1; added < 12; ++added) {
        if (tones.has(added)) continue;
        std::vector<int> next = have;
        next.push_back(added);
        out.push_back(make(ColorStepKind::add, next, std::nullopt, added));
    }
    // A chord keeps two notes at least.
    if (have.size() > 2) {
        for (int tone : have)
            if (tone != 0) out.push_back(make(ColorStepKind::takeAway, without(tone), tone, std::nullopt));
    }
    for (int tone : have) {
        if (tone == 0) continue;
        for (int offset : {1, -1}) {
            const int moved = (tone + offset + 12) % 12;
            if (moved == 0 || tones.has(moved)) continue;
            std::vector<int> next = without(tone);
            next.push_back(moved);
            out.push_back(make(offset > 0 ? ColorStepKind::raise : ColorStepKind::lower, next, tone, moved));
        }
    }
    return out;
}

/// The commonest chord qualities, most played first: the joystick's
/// staples, then the 9ths and the jazz colors.
const std::vector<std::string> &common() {
    static const std::vector<std::string> qualities = {
        "maj", "min",  "7",    "maj7", "min7",    "sus4", "sus2",   "add9",   "6",         "min6",
        "min add9", "dim", "aug", "min7♭5", "5", "9", "min9", "maj9", "7sus4", "6/9",
        "min6/9", "dim7", "min(maj7)", "7♭9", "7♯9", "add11", "min add11",
    };
    return qualities;
}

int role(int tone) {
    if (tone == 3 || tone == 4) return 0; // the 3rd
    if (tone >= 6 && tone <= 8) return 1; // the 5th
    if (tone >= 9 && tone <= 11) return 2; // the 7th (or a 6th)
    return 3;                              // a tension, or a suspension
}

/// Where a step comes within its kind by theory, before its fit is counted:
/// the degree's own stack tones in the order they are added (7th, 9th, 13th,
/// 11th) before other adds; the 3rd moved before the 5th, the 7th and a
/// tension; the 5th taken away before a tension, the 7th and the 3rd.
int order(const ColorStep &step, const std::vector<int> &own) {
    switch (step.kind) {
    case ColorStepKind::add: {
        const int stack[] = {own[6], own[1], own[5], own[3]};
        for (int i = 0; i < 4; ++i)
            if (stack[i] == *step.to) return i;
        return 10 + *step.to;
    }
    case ColorStepKind::raise:
    case ColorStepKind::lower: return role(*step.from);
    case ColorStepKind::takeAway: {
        static const int byRole[] = {3, 0, 2, 1};
        return byRole[role(*step.from)];
    }
    }
    return 0;
}

std::vector<int> sortKey(const ColorStep &step, const std::vector<int> &own, ColorStepRanking ranking) {
    std::vector<int> theory = {static_cast<int>(step.fit), order(step, own), step.from.value_or(step.to.value_or(0))};
    if (ranking == ColorStepRanking::theory) return theory;
    const std::string quality = step.tones.slash() ? "slash" : step.tones.name();
    const auto &qualities = common();
    const auto found = std::find(qualities.begin(), qualities.end(), quality);
    theory.insert(theory.begin(), static_cast<int>(found - qualities.begin()));
    return theory;
}

} // namespace

ChordTones base(const Key &key, Degree degree) { return chordTones(key, ChordSpec{degree, ChordColor::base()}); }

std::map<ColorStepKind, std::vector<ColorStep>> steps(const ChordTones &tones, const Key &key, Degree degree,
                                                      ColorStepRanking ranking) {
    const int root = offset(key.scale, degree);
    const std::vector<int> &own = intervals(ChordGrid::ownMode(key, degree));
    const std::vector<int> &scale = intervals(key.scale);
    const auto inKey = [&](int tone) {
        return std::find(scale.begin(), scale.end(), (root + tone) % 12) != scale.end();
    };
    std::map<ColorStepKind, std::vector<ColorStep>> byKind;
    for (ColorStepKind kind : allColorStepKinds) byKind[kind];
    for (ColorStep &s : neighbours(tones, inKey)) byKind[s.kind].push_back(std::move(s));
    for (auto &[kind, choices] : byKind) {
        std::stable_sort(choices.begin(), choices.end(), [&](const ColorStep &a, const ColorStep &b) {
            return sortKey(a, own, ranking) < sortKey(b, own, ranking);
        });
    }
    return byKind;
}

std::optional<ColorStep> step(const CompassPlace &place, const ChordTones &tones, const Key &key, Degree degree,
                              ColorStepRanking ranking) {
    const auto all = steps(tones, key, degree, ranking);
    const auto &choices = all.at(place.kind());
    const size_t index = static_cast<size_t>(place.rank() - 1);
    if (index >= choices.size()) return std::nullopt;
    return choices[index];
}

ChordTones walk(const std::vector<CompassPlace> &places, const Key &key, Degree degree, ColorStepRanking ranking) {
    ChordTones tones = base(key, degree);
    for (const CompassPlace &place : places)
        if (auto next = step(place, tones, key, degree, ranking)) tones = next->tones;
    return tones;
}

} // namespace StepCompass

} // namespace perfecto::theory
