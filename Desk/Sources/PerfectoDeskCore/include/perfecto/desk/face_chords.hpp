// Face Chords: the key's chords by number on the four face buttons, as a
// guitarist's chart has them. A always plays I; without LT, B, X and Y play
// the other major chords and the diminished (IV, V, vii°), and with LT held
// the minor ones (ii, iii, vi). The map is a value, so a shell can read
// another from a file.
//
// What sounds is always the latest face button held, read in the layer LT is
// in now: pulling or letting go of LT while a button is held is a change of
// chord as a new press is, and with no button held nothing sounds.
//
// A second voice can be added (R3), a line of chords of its own over the
// first: the desk's melody line, in its sound and on its MIDI channel, an
// octave up. Each press goes to one voice or both, chosen as it is pressed,
// and each voice sounds the latest button it holds:
//
// - with one voice, every press is the first's;
// - with LB held, a press is the second's alone;
// - with both voices on (LB double-clicked), a press is both's, but with LB
//   held, or with LT pulled at the same moment (either first, within
//   `together`), the second's alone, over what the first is holding.
//
// A pull of LT that strikes with a face button so is the second voice's: it
// plays that button's LT chord there, and the first voice reads LT as let go
// for as long as the pull is held, so it keeps its chord. Every other pull is
// both voices' layer, as with one. A press already struck on both before the
// pull came is taken back from the first, which returns to what it held.

#ifndef PERFECTO_DESK_FACE_CHORDS_HPP
#define PERFECTO_DESK_FACE_CHORDS_HPP

#include "perfecto/desk/layout.hpp"
#include "perfecto/desk/music.hpp"
#include "perfecto/desk/pad.hpp"

#include <perfecto/theory/key.hpp>

#include <array>
#include <map>
#include <optional>
#include <vector>

namespace perfecto::desk {

class FaceChords {
public:
    /// A degree for each face button, without LT and with it held. A button
    /// a layer leaves out strikes nothing in it.
    struct Map {
        std::map<PadButton, theory::Degree> plain;
        std::map<PadButton, theory::Degree> layered;

        bool operator==(const Map &) const = default;

        /// A I; B IV, X V, Y vii°; with LT, B ii, X iii, Y vi.
        static const Map &standard();

        std::optional<theory::Degree> degree(PadButton button, bool layered) const;
    };

    /// The buttons where they are on the controller, rising clockwise from
    /// the bottom.
    static constexpr std::array<PadButton, 4> faces = {PadButton::a, PadButton::x, PadButton::y, PadButton::b};

    /// Where `button` is in the diamond, as a bearing: A at the bottom.
    static double bearing(PadButton button);

    /// What one voice holds and sounds.
    struct Voice {
        /// The face buttons it holds, the most recent last.
        std::vector<PadButton> held;
        /// What was last struck, or refused: a chord is struck once for it.
        std::optional<std::pair<PadButton, theory::Degree>> struck;
        ChordLine line;
        /// The color it was struck in.
        theory::ChordColor color = theory::ChordColor::base();

        bool operator==(const Voice &) const = default;

        /// The button and degree it sounds now, if it sounds one.
        std::optional<std::pair<PadButton, theory::Degree>> heard() const;
    };

    /// Two presses of LB within this many seconds are a double-click.
    static constexpr double doubleClick = 0.3;
    /// A face button and LT within this many seconds of each other are struck
    /// together.
    static constexpr double together = 0.08;
    /// How far over the first voice the second sounds, in octaves.
    static constexpr int overOctaves = 1;

    explicit FaceChords(Map map = Map::standard());

    bool operator==(const FaceChords &) const = default;

    const Map &map() const { return map_; }
    /// Plays `map` from the next frame; a chord held changes with it.
    void setMap(Map map) { map_ = std::move(map); }

    /// The color each degree's chord is struck in, as the left hand colors
    /// them; a degree not here is plain.
    const std::map<theory::Degree, theory::ChordColor> &colors() const { return colors_; }
    /// Colors the chords from the next step: a chord held takes its new
    /// color tied.
    void setColors(std::map<theory::Degree, theory::ChordColor> colors) { colors_ = std::move(colors); }

    /// Whether LT is held: the second layer.
    bool isLayered() const { return isLayered_; }
    /// The first voice, and the second (silent until it is added).
    const std::array<Voice, 2> &voices() const { return voices_; }
    const ChordLine &line() const { return voices_[0].line; }
    /// Whether the second voice has been added (R3).
    bool hasSecond() const { return hasSecond_; }
    /// Whether a press plays both voices (LB double-clicked).
    bool isTogether() const { return isTogether_; }
    /// Whether the pull of LT held is the second voice's alone.
    bool isOverPull() const { return isOverPull_; }

    /// The button and degree the first voice sounds now, if it sounds one.
    std::optional<std::pair<PadButton, theory::Degree>> heard() const { return voices_[0].heard(); }

    std::vector<DeskEffect> step(const PadInput &input, DeskSettings &settings);

    std::vector<DeskEffect> releaseAll();

    Legend legend(const DeskSettings &settings) const;

private:
    /// A face button pressed, and when: LT pulled soon after, with both
    /// voices on, makes it the second voice's alone.
    struct Press {
        PadButton button;
        double time;
        bool operator==(const Press &) const = default;
    };

    Map map_;
    bool isLayered_ = false;
    std::array<Voice, 2> voices_;
    bool hasSecond_ = false;
    bool isTogether_ = false;
    bool isOverPull_ = false;
    /// When LT was last pulled past halfway.
    double layeredAt_ = 0;
    /// When LB was last pressed, while a second press would be a double-click.
    std::optional<double> lbPressedAt_;
    std::vector<Press> latePresses_;
    std::map<theory::Degree, theory::ChordColor> colors_;

    /// Whether `voice` reads LT as held.
    bool isLayered(size_t voice) const { return isLayered_ && !(voice == 0 && isOverPull_); }
    /// The voices a face button pressed now goes to.
    std::vector<size_t> route(const PadInput &input) const;
    /// Whether a face button pressed now is struck together with LT, as the
    /// second voice's alone.
    bool strikesWithLT(const PadInput &input) const;
    /// What the hands ask `voice` for: its latest press with a chord in its
    /// layer.
    std::optional<std::pair<PadButton, theory::Degree>> wanted(size_t voice) const;
    /// Strikes what `voice` is asked for, if it is not what it sounds.
    std::vector<DeskEffect> settle(size_t voice, const DeskSettings &settings, double time);
    std::vector<DeskEffect> takeAwaySecond();
};

} // namespace perfecto::desk

#endif
