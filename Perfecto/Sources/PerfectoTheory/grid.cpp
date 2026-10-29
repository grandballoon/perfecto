#include "perfecto/theory/grid.hpp"

#include "perfecto/theory/naming.hpp"
#include "perfecto/theory/require.hpp"

#include <algorithm>

namespace perfecto::theory::ChordGrid {

HeptatonicMode ownMode(const Key &key, Degree degree) {
    if (const auto mode = ownModeOf(key, degree)) return *mode;
    switch (triadBase(key, degree)) {
    case TriadBase::major: return HeptatonicMode::ionian;
    case TriadBase::minor: return HeptatonicMode::aeolian;
    case TriadBase::dim: return HeptatonicMode::locrian;
    }
    return HeptatonicMode::ionian;
}

std::vector<HeptatonicMode> rows(const Key &key, Degree degree) {
    return rowsAround(ownMode(key, degree), rowCount);
}

ChordColor color(const GridPosition &position, const Key &key, Degree degree) {
    const auto all = rows(key, degree);
    PERFECTO_REQUIRE(position.row >= 0 && position.row < static_cast<int>(all.size()), "grid row out of range");
    const HeptatonicMode mode = all[position.row];
    return ChordColor::grid(position.height,
                            mode == ownMode(key, degree) ? std::nullopt : std::optional<HeptatonicMode>(mode));
}

std::optional<GridPosition> position(const ChordColor &color, const Key &key, Degree degree) {
    const auto *grid = std::get_if<ChordColor::Grid>(&color.value());
    if (!grid) return std::nullopt;
    const HeptatonicMode target = grid->mode.value_or(ownMode(key, degree));
    const auto all = rows(key, degree);
    const auto found = std::find(all.begin(), all.end(), target);
    if (found == all.end()) return std::nullopt;
    return GridPosition{grid->height, static_cast<int>(found - all.begin())};
}

} // namespace perfecto::theory::ChordGrid
