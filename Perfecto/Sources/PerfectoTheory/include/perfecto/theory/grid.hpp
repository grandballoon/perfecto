// The chord grid: the geometry that maps a finger's position to a chord
// color. Columns are stack heights (triad → 13th); rows are a window of
// `byBrightness` around the degree's own mode. The same position means a
// different mode for a different degree, so input surfaces store the
// position and resolve it against the degree that plays.

#ifndef PERFECTO_THEORY_GRID_HPP
#define PERFECTO_THEORY_GRID_HPP

#include "perfecto/theory/chord_color.hpp"
#include "perfecto/theory/key.hpp"
#include "perfecto/theory/modes.hpp"
#include "perfecto/theory/tertian.hpp"

#include <optional>
#include <vector>

namespace perfecto::theory {

/// A cell of the chord grid: a column and a row counted from the top.
struct GridPosition {
    StackHeight height;
    int row;

    bool operator==(const GridPosition &) const = default;
    auto operator<=>(const GridPosition &) const = default;
};

namespace ChordGrid {

/// Rows on screen: the degree's own mode and three brighter and darker.
inline constexpr int rowCount = 7;

/// The mode `degree` stacks through in `key` when no other row is chosen.
/// Scales without seven notes have no diatonic mode, so they use the
/// major-scale mode with the degree's triad quality.
HeptatonicMode ownMode(const Key &key, Degree degree);

/// The modes of the grid's rows, top to bottom, for `degree` in `key`.
std::vector<HeptatonicMode> rows(const Key &key, Degree degree);

/// The color a finger at `position` gives `degree`. The own mode's row
/// resolves to the diatonic color (no mode), so it follows the key.
ChordColor color(const GridPosition &position, const Key &key, Degree degree);

/// Where `color` sits on `degree`'s grid, or none if it isn't on it (a
/// joystick color, or a mode outside this degree's window).
std::optional<GridPosition> position(const ChordColor &color, const Key &key, Degree degree);

} // namespace ChordGrid

} // namespace perfecto::theory

#endif
