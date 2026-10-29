// The color ring: the chord grid's colors round a circle, a band to each
// stack of thirds (the triad innermost) and a sector to each mode of the
// major scale, darkest to brightest. Each sector is one note from the next,
// so touching colors are almost always one step apart (`colorSteps`); the
// darkest and the brightest are five notes apart, so the ring has a gap
// where they would meet. Geometry is the view's: here the ring is sectors.

#ifndef PERFECTO_THEORY_COLOR_RING_HPP
#define PERFECTO_THEORY_COLOR_RING_HPP

#include "perfecto/theory/chord_color.hpp"
#include "perfecto/theory/key.hpp"
#include "perfecto/theory/modes.hpp"
#include "perfecto/theory/tertian.hpp"
#include "perfecto/theory/tone_marks.hpp"

#include <optional>
#include <vector>

namespace perfecto::theory {

/// How the ring is turned: the same colors either way.
enum class ColorRingArrangement {
    /// Never turned: a sector is always the same mode, so a place on the
    /// ring is always the same chord shape. Dorian, the middle of the
    /// order, is at the top.
    fixed,
    /// Turned so the held degree's own mode is at the top: the top is
    /// always the chord as the key has it.
    home,
};

/// A cell of the ring: a stack height, and the mode it stacks through; none
/// is the degree's own mode, so the cell follows the degree and the key, as
/// the chord grid's own row does.
struct ColorRingPosition {
    StackHeight height;
    std::optional<HeptatonicMode> mode;

    bool operator==(const ColorRingPosition &) const = default;
    auto operator<=>(const ColorRingPosition &) const = default;
};

namespace ColorRing {

/// The sectors' modes in order round the ring, darkest first: the major
/// scale's seven of `byBrightness`.
const std::vector<HeptatonicMode> &modes();

/// The sector at the top of a ring that is not turned.
inline constexpr int topSector = 3;

/// How many sectors `arrangement` turns the ring clockwise for `degree` in
/// `key`. A home ring is not turned for a degree whose own mode is not on
/// the ring (a key of harmonic minor).
int turn(ColorRingArrangement arrangement, const Key &key, Degree degree);

/// The mode a cell stacks through, for `degree` in `key`.
HeptatonicMode mode(const ColorRingPosition &position, const Key &key, Degree degree);

/// The cell of `height` in sector `sector` (an index of `modes`), for
/// `degree` in `key`. On a home ring the own mode's cell has no mode, so it
/// stays the own mode's whatever degree is played; on a fixed ring a sector
/// is always its mode.
ColorRingPosition position(StackHeight height, int sector, ColorRingArrangement arrangement, const Key &key,
                           Degree degree);

/// The sector a cell is in for `degree` in `key`, or none if its mode is not
/// on the ring.
std::optional<int> sector(const ColorRingPosition &position, const Key &key, Degree degree);

/// The color a cell plays with `marks` on: a grid color, which the own
/// mode's cell plays with no mode so it follows the key.
ChordColor color(const ColorRingPosition &position, const ToneMarks &marks, const Key &key, Degree degree);

} // namespace ColorRing

} // namespace perfecto::theory

#endif
