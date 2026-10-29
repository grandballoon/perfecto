// Model 2, Petals and depth: strike with the face buttons, so rhythm is
// crisp, and bend the mode with the triggers. The left stick chooses the
// degree; the face button pressed strikes it at one of four stack heights,
// laid out as a diamond rising clockwise from A; LT darkens the mode a
// sector at a time and RT brightens it. It is the color ring again, read
// on other surfaces: its bands on the buttons, its sectors on the triggers.
//
// The diamond on screen always shows the four chords the buttons would
// strike, at the triggers' depth now, so a change is read before it is
// struck.

#ifndef PERFECTO_DESK_PETALS_HPP
#define PERFECTO_DESK_PETALS_HPP

#include "perfecto/desk/layout.hpp"
#include "perfecto/desk/music.hpp"
#include "perfecto/desk/pad.hpp"

#include <perfecto/theory/chord_tones.hpp>
#include <perfecto/theory/key.hpp>
#include <perfecto/theory/tertian.hpp>

#include <array>
#include <map>
#include <optional>
#include <string>
#include <type_traits>
#include <utility>
#include <variant>
#include <vector>

namespace perfecto::desk {

class Petals {
public:
    /// The four marks LB puts on the buttons: the joystick's staples, each a
    /// step from the triad.
    enum class Mark { sus4, sixth, add9, raisedFifth };

    static constexpr std::array<Mark, 4> allMarks = {Mark::sus4, Mark::sixth, Mark::add9, Mark::raisedFifth};

    /// A face button's chord: a height, or with LB a mark.
    class Petal {
    public:
        struct Height {
            theory::StackHeight height;
            bool operator==(const Height &) const = default;
        };
        struct Mark {
            Petals::Mark mark;
            bool operator==(const Mark &) const = default;
        };

        using Value = std::variant<Height, Mark>;

        template <class Alternative>
            requires std::is_constructible_v<Value, Alternative>
        Petal(Alternative alternative) : value_(std::move(alternative)) {}

        static Petal height(theory::StackHeight height) { return Height{height}; }
        static Petal mark(Petals::Mark mark) { return Mark{mark}; }

        const Value &value() const { return value_; }

        bool operator==(const Petal &) const = default;

    private:
        Value value_;
    };

    /// The voicing the right stick bends to.
    struct Bend {
        int octaves = 0;
        int roll = 0;
        bool operator==(const Bend &) const = default;
    };

    /// The buttons in the diamond, rising clockwise from the bottom.
    static constexpr std::array<PadButton, 4> diamond = {PadButton::a, PadButton::x, PadButton::y, PadButton::b};
    static const std::map<PadButton, theory::StackHeight> &heights();
    static const std::map<PadButton, Mark> &marks();

    Petals();

    /// Swift's own `==`, which leaves out the sector the left stick is on.
    bool operator==(const Petals &other) const;

    theory::Degree degree() const { return degree_; }
    /// How far each trigger is pulled, in sectors.
    int darker() const { return darker_; }
    int brighter() const { return brighter_; }
    bool holds() const { return holds_; }
    const ChordLine &line() const { return line_; }
    std::optional<ArpeggioRate> arpeggio() const { return arpeggio_; }
    /// The voicing the right stick bends to, and whether it has been kept
    /// and so is not bent again until the stick comes back.
    Bend bend() const { return bend_; }
    bool isMarking() const { return isMarking_; }
    bool isOnEffects() const { return isOnEffects_; }

    /// Sectors from the degree's own mode: the deeper trigger wins.
    int shift() const { return brighter_ > darker_ ? brighter_ : -darker_; }

    std::vector<DeskEffect> step(const PadInput &input, DeskSettings &settings);

    std::vector<DeskEffect> releaseAll();

    /// The voicing a stick at `stick` bends to: across is the inversion, up
    /// and down the octave. (Swift's `bend(of:)`.)
    static Bend bendOf(const Stick &stick);

    /// The chord `petal` strikes now.
    DeskChord chord(const Petal &petal, const DeskSettings &settings) const;

    // What the screen shows

    std::vector<Target> degreeTargets(const DeskSettings &settings) const;

    /// The diamond: what each face button would strike now, in `diamond`'s
    /// order.
    std::vector<Target> petalTargets(const DeskSettings &settings) const;

    /// The mode at each depth either way, darkest first, for the triggers'
    /// scale.
    std::vector<Target> depthTargets(const DeskSettings &settings) const;

    Legend legend(const DeskSettings &settings) const;

private:
    struct Press {
        PadButton button;
        Petal petal;
        bool operator==(const Press &) const = default;
    };

    theory::Degree degree_ = theory::Degree::I;
    std::optional<int> degreeSector_;
    int darker_ = 0;
    int brighter_ = 0;
    /// The face buttons held, the most recent last: it is the one heard.
    std::vector<Press> presses_;
    bool holds_ = false;
    ChordLine line_;
    std::optional<ArpeggioRate> arpeggio_;
    Bend bend_;
    bool bendKept_ = false;
    bool isMarking_ = false;
    bool isOnEffects_ = false;

    /// RB's layer: A and X the arpeggio, Y voice leading, B hold.
    std::vector<DeskEffect> effect(PadButton button, DeskSettings &settings, double time);
};

/// "▲3 sus4", "+6", "+9", "▲5".
std::string name(Petals::Mark mark);

/// The mark put on `triad`'s tones.
theory::ChordTones applied(Petals::Mark mark, const theory::ChordTones &triad);

} // namespace perfecto::desk

#endif
