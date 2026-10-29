// The color ring on a stick: its angle the mode, its radius the stack
// height. Its sectors go from darkest anticlockwise to brightest clockwise,
// each a note or two from the next, so a step round is the gentlest change
// of color there is. How the ring is turned is the player's choice
// (`RingArrangement`), since each way gives up something the others keep.

#ifndef PERFECTO_DESK_RING_PIE_HPP
#define PERFECTO_DESK_RING_PIE_HPP

#include "perfecto/desk/consonance.hpp"
#include "perfecto/desk/gates.hpp"
#include "perfecto/desk/music.hpp"

#include <perfecto/theory/chord_color.hpp>
#include <perfecto/theory/key.hpp>
#include <perfecto/theory/modes.hpp>
#include <perfecto/theory/step_compass.hpp>
#include <perfecto/theory/tertian.hpp>

#include <array>
#include <optional>
#include <string>
#include <vector>

namespace perfecto::desk {

/// How the color ring is laid round the stick.
enum class RingArrangement : int {
    /// The seven modes of the major scale, turned so the degree's own is at
    /// the top: up is always the chord as the key has it. The ring is
    /// lopsided by as much as the own mode is near an end, so its gap moves
    /// with the degree.
    home,
    /// The seven modes of the major scale, never turned: Dorian at the top
    /// and the gap at the bottom, so a direction is always the same mode.
    /// The key's own chord is wherever its mode is. In brightness order its
    /// sides are mirror images: each mode faces its inversion across the
    /// stick (Lydian and Locrian, Ionian and Phrygian, Mixolydian and
    /// Aeolian), Dorian, its own, at the top.
    fixed,
    /// The degree's own mode at the top with the modes nearest it in
    /// brightness either side, from all three scales' (the chord grid's
    /// rows, `rowsAround`): balanced on every degree, as far as the
    /// brightest and darkest modes allow.
    centred,
};

inline constexpr std::array<RingArrangement, 3> allRingArrangements = {
    RingArrangement::home, RingArrangement::fixed, RingArrangement::centred};

std::string name(RingArrangement arrangement);

/// What it keeps, in a line.
std::string summary(RingArrangement arrangement);

/// The order the ring's sectors go round in, so a direction and a grouping
/// can come to mean a quality.
enum class RingOrder : int {
    /// Darkest anticlockwise to brightest clockwise, each a note from the
    /// next (for the major scale's modes, the circle of fifths).
    brightness,
    /// Major-third modes on one side and minor-third on the other, each
    /// brightest by the seam between them, and the diminished at the far end.
    quality,
    /// By the note that makes each mode itself: Ionian and Aeolian, which
    /// alter nothing, in the middle; modes with a note raised (Lydian ♯4,
    /// Dorian ♮6) clockwise; with a note lowered (Mixolydian ♭7, Phrygian
    /// ♭2) anticlockwise; Locrian, with two, furthest.
    character,
    /// The fewest notes from outside the key at the top, more to either
    /// side, the most by the gap.
    borrowed,
    /// The modes most played at the top (Ionian, Aeolian, Dorian,
    /// Mixolydian, Lydian, Phrygian, Locrian), less played to either side.
    common,
    /// Nearest the chord sounding at the top, further to either side: it
    /// turns as you play.
    nearness,
};

inline constexpr std::array<RingOrder, 6> allRingOrders = {RingOrder::brightness, RingOrder::quality,
                                                           RingOrder::character,  RingOrder::borrowed,
                                                           RingOrder::common,     RingOrder::nearness};

std::string name(RingOrder order);

/// Which of the ring's cells can be reached; the rest keep their places,
/// dimmed, so a direction still means what it did.
enum class RingFilter : int {
    all,
    /// Only chords whose every note is in the key.
    inKey,
    /// Only modes with a major third.
    majorThird,
    /// Only modes with a minor third.
    minorThird,
    /// Only chords with no tone a semitone over another.
    noClash,
};

inline constexpr std::array<RingFilter, 5> allRingFilters = {RingFilter::all, RingFilter::inKey,
                                                             RingFilter::majorThird, RingFilter::minorThird,
                                                             RingFilter::noClash};

std::string name(RingFilter filter);

/// A cell of the ring: a mode and a stack height. It names what it plays,
/// not where it is, so a cell kept stays kept whichever way the ring is
/// turned.
struct RingCell {
    theory::HeptatonicMode mode;
    theory::StackHeight height;

    bool operator==(const RingCell &) const = default;
    auto operator<=>(const RingCell &) const = default;
};

/// The ring for one degree of one key, as its arrangement, order and filter
/// lay it.
class RingPie {
public:
    struct Sector {
        theory::HeptatonicMode mode;
        /// Degrees clockwise from up.
        double bearing;
        /// Whether it is the degree's own mode: the chord as the key has it.
        bool isOwn;

        bool operator==(const Sector &) const = default;
    };

    /// The sectors the stick can reach, and the pie it chooses among them by.
    struct Gate {
        PieGate gate;
        /// Indices of `sectors`.
        std::vector<int> sectors;

        bool operator==(const Gate &) const = default;
    };

    /// Degrees of the stick a sector takes: seven in 300°, with a gap where
    /// the ring's two ends would meet.
    static constexpr double sectorSpan = 300.0 / 7;

    RingArrangement arrangement;
    RingOrder order;
    RingFilter filter;
    /// In the order they go round, anticlockwise end first.
    std::vector<Sector> sectors;
    theory::HeptatonicMode own;

    /// (Swift's defaults: order brightness, filter all, near nothing, the
    /// guard off.)
    RingPie(RingArrangement arrangement, RingOrder order, RingFilter filter, const theory::Key &key,
            theory::Degree degree, const std::optional<DeskChord> &sounding = std::nullopt,
            const ConsonanceGuard &consonance = ConsonanceGuard());

    /// In brightness order, unfiltered.
    RingPie(RingArrangement arrangement, const theory::Key &key, theory::Degree degree)
        : RingPie(arrangement, RingOrder::brightness, RingFilter::all, key, degree) {}

    bool operator==(const RingPie &) const = default;

    /// The modes most played, most first.
    static const std::array<theory::HeptatonicMode, 7> popularity;

    /// How far a mode is from the plain major or minor scale of its third:
    /// notes raised count up, notes lowered count down, so Lydian is 1,
    /// Mixolydian -1 and Locrian -2.
    static int alteration(theory::HeptatonicMode mode);

    /// Where the gap is: midway round the long way between the ring's ends.
    double gap() const;

    /// Whether the filter lets `cell` be reached.
    bool allows(const RingCell &cell) const;

    /// The sectors the stick can reach (those with a cell the filter lets
    /// through), as indices of `sectors`, and the pie it chooses among them by.
    Gate gate(bool extended) const;

    /// The mode `steps` sectors brighter than the own mode (below 0,
    /// darker), held at the ring's ends; the own mode is counted from the
    /// top for a ring it is not on. For a ring in brightness order.
    theory::HeptatonicMode mode(int steps) const;

    /// Whether the ring reaches `steps` sectors from the own mode.
    bool reaches(int steps) const { return clamped(steps) == steps; }

    /// `steps` held to what the ring reaches from the own mode either way.
    int clamped(int steps) const;

    /// The color a cell plays: thirds stacked to its height through its
    /// mode, the own mode's as the key has it (so it follows the key).
    theory::ChordColor color(const RingCell &cell) const;

    /// The cell a stick at `sector` (an index of `sectors`) in ring `band`
    /// chooses, if the filter lets it be reached.
    std::optional<RingCell> cell(int sector, int band, bool extended) const;

    /// The heights the stick's three rings reach: the 7th to the 11th, or
    /// with the extension held, the 9th to the 13th.
    static std::array<theory::StackHeight, 3> heights(bool extended);

private:
    theory::Key key_;
    theory::Degree degree_;
    /// The consonance guard, which leaves out what it will not play as the
    /// filter does.
    ConsonanceGuard consonance_;

    /// The sector of the own mode, or the top one for a ring without it.
    int ownIndex() const;
};

/// The step compass on a stick: its four kinds of step at the cardinals,
/// each kind's first choice and its second a little clockwise of it.
/// Up adds a tone, right raises one, down takes one away, left lowers one.
namespace CompassPie {

const std::vector<theory::CompassPlace> &places();

const PieGate &gate();

/// The chord the place at `index` makes from `chord`, if it has one.
std::optional<DeskChord> chord(int index, const DeskChord &from, theory::ColorStepRanking ranking);

/// What the place at `index` does, by its tones: "+7", "3→4".
std::optional<std::string> edit(int index, const DeskChord &from, theory::ColorStepRanking ranking);

} // namespace CompassPie

} // namespace perfecto::desk

#endif
