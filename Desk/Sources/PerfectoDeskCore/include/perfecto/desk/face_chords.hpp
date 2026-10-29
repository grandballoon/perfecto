// Face Chords: the key's chords by number on the four face buttons, as a
// guitarist's chart has them. A always plays I; without LT, B, X and Y play
// the other major chords and the diminished (IV, V, vii°), and with LT held
// the minor ones (ii, iii, vi). The map is a value, so a shell can read
// another from a file.
//
// What sounds is always the latest face button held, read in the layer LT is
// in now: pulling or letting go of LT while a button is held is a change of
// chord as a new press is, and with no button held nothing sounds.

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

    explicit FaceChords(Map map = Map::standard()) : map_(std::move(map)) {}

    bool operator==(const FaceChords &) const = default;

    const Map &map() const { return map_; }
    /// Plays `map` from the next frame; a chord held changes with it.
    void setMap(Map map) { map_ = std::move(map); }

    /// Whether LT is held: the second layer.
    bool isLayered() const { return isLayered_; }
    /// The face buttons held, the most recent last.
    const std::vector<PadButton> &held() const { return held_; }
    const ChordLine &line() const { return line_; }

    /// The button and degree heard now, if one is.
    std::optional<std::pair<PadButton, theory::Degree>> heard() const;

    std::vector<DeskEffect> step(const PadInput &input, DeskSettings &settings);

    std::vector<DeskEffect> releaseAll();

    Legend legend(const DeskSettings &settings) const;

private:
    /// What the hands ask for: the latest press with a chord in this layer.
    struct Wanted {
        PadButton button;
        theory::Degree degree;
        bool operator==(const Wanted &) const = default;
    };

    Map map_;
    bool isLayered_ = false;
    std::vector<PadButton> held_;
    /// What was last struck, or refused: a chord is struck once for it.
    std::optional<Wanted> struck_;
    ChordLine line_;

    std::optional<Wanted> wanted() const;
};

} // namespace perfecto::desk

#endif
