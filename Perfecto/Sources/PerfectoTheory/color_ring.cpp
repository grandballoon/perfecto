#include "perfecto/theory/color_ring.hpp"

#include "perfecto/theory/grid.hpp"
#include "perfecto/theory/require.hpp"

#include <algorithm>

namespace perfecto::theory::ColorRing {

namespace {

std::optional<int> indexOf(HeptatonicMode mode) {
    const auto &all = modes();
    const auto found = std::find(all.begin(), all.end(), mode);
    if (found == all.end()) return std::nullopt;
    return static_cast<int>(found - all.begin());
}

} // namespace

const std::vector<HeptatonicMode> &modes() {
    static const std::vector<HeptatonicMode> ring = [] {
        std::vector<HeptatonicMode> major;
        for (HeptatonicMode mode : byBrightness())
            if (family(mode) == ScaleFamily::major) major.push_back(mode);
        std::reverse(major.begin(), major.end());
        return major;
    }();
    return ring;
}

int turn(ColorRingArrangement arrangement, const Key &key, Degree degree) {
    if (arrangement != ColorRingArrangement::home) return 0;
    const auto own = indexOf(ChordGrid::ownMode(key, degree));
    return own ? topSector - *own : 0;
}

HeptatonicMode mode(const ColorRingPosition &position, const Key &key, Degree degree) {
    return position.mode.value_or(ChordGrid::ownMode(key, degree));
}

ColorRingPosition position(StackHeight height, int sector, ColorRingArrangement arrangement, const Key &key,
                           Degree degree) {
    PERFECTO_REQUIRE(sector >= 0 && sector < static_cast<int>(modes().size()), "ring sector out of range");
    const HeptatonicMode m = modes()[sector];
    const bool own = arrangement == ColorRingArrangement::home && m == ChordGrid::ownMode(key, degree);
    return {height, own ? std::nullopt : std::optional<HeptatonicMode>(m)};
}

std::optional<int> sector(const ColorRingPosition &position, const Key &key, Degree degree) {
    return indexOf(mode(position, key, degree));
}

ChordColor color(const ColorRingPosition &position, const ToneMarks &marks, const Key &key, Degree degree) {
    const HeptatonicMode own = ChordGrid::ownMode(key, degree);
    const auto m = position.mode == own ? std::nullopt : position.mode;
    return ChordColor::tertian(position.height, m, marks);
}

} // namespace perfecto::theory::ColorRing
