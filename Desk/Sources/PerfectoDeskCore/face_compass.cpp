#include "perfecto/desk/face_compass.hpp"

#include <array>
#include <cstdlib>

namespace perfecto::desk::FaceCompass {

using namespace theory;

namespace {

constexpr std::array<ColorStepKind, 4> kinds = {ColorStepKind::add, ColorStepKind::raise, ColorStepKind::takeAway,
                                                ColorStepKind::lower};

} // namespace

const PieGate &gate() {
    static const PieGate gate = PieGate::even(static_cast<int>(kinds.size()));
    return gate;
}

CompassPlace place(int direction, bool isOuter) {
    return CompassPlace(kinds[static_cast<size_t>(direction)], isOuter ? StepCompass::lastRank : StepCompass::firstRank);
}

std::string name(const CompassPlace &place) {
    const std::string kind = [&] {
        switch (place.kind()) {
        case ColorStepKind::add: return "Add";
        case ColorStepKind::raise: return "Raise";
        case ColorStepKind::lower: return "Lower";
        case ColorStepKind::takeAway: return "Take away";
        }
        return "";
    }();
    return place.rank() == StepCompass::firstRank ? kind : kind + " 2nd";
}

std::optional<ColorStep> step(const CompassPlace &place, const Key &key, Degree degree, ColorStepRanking ranking,
                              KeyAssist assist) {
    const auto all = StepCompass::steps(StepCompass::base(key, degree), key, degree, ranking);
    const auto &choices = all.at(place.kind());
    const int count = static_cast<int>(choices.size());
    const int wanted = place.rank() - 1;
    if (assist != KeyAssist::assist) {
        if (wanted >= count) return std::nullopt;
        return choices[static_cast<size_t>(wanted)];
    }
    // Outward from the place, the better-ranked of two as near first.
    for (int distance = 0; distance < count + wanted; ++distance)
        for (const int at : {wanted - distance, wanted + distance})
            if (at >= 0 && at < count && choices[static_cast<size_t>(at)].fit != ColorFit::borrowed)
                return choices[static_cast<size_t>(at)];
    return std::nullopt;
}

ChordColor color(const CompassPlace &place, const Key &key, Degree degree, ColorStepRanking ranking, KeyAssist assist) {
    const auto found = step(place, key, degree, ranking, assist);
    return found ? ChordColor::tones(found->tones) : ChordColor::base();
}

ChordFit shownFit(ChordFit fit, KeyAssist assist) {
    if (assist == KeyAssist::normal) return ChordFit::inKey;
    return fit == ChordFit::borrowed ? ChordFit::borrowed : ChordFit::inKey;
}

} // namespace perfecto::desk::FaceCompass
