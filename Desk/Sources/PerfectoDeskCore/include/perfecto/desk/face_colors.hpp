// The left hand's colors over Face Chords: the left stick colors the chords
// the face buttons hold, by one of two schemes chosen in the menu
// (`DeskSettings::faceStick`), and LB puts the chords' pinned colors on it.
//
// - The Orchid's chord buttons. Telepathic Instruments' Orchid builds a chord
//   from a row of types (Dim, Min, Maj, Sus) and a row of extensions (6, m7,
//   M7, 9) held with its root (`ChordBuild`). Here each of the eight is a
//   direction of the stick, and Face Chords plays in the Orchid's key mode:
//   with no type held, the triad is the degree's own. Leaning holds one
//   button. Rolling round the rim to another direction, without coming back
//   through the middle, holds that one with it: the direction first leaned
//   to stays held, and whichever the stick is on now is added, as a second
//   finger on the Orchid's buttons. Of two types, the later is played, as on
//   the Orchid. The ring is laid so each direction's neighbours make chords
//   with it: Maj with m7 a dominant seventh, m7 with 9 a ninth, 9 with M7 a
//   major ninth, M7 with Min a minor-major seventh, Min with 6 a minor
//   sixth, 6 with Dim a diminished seventh.
// - Perfecto's joystick table: the phone's joystick, its eight directions in
//   one of its three modes, as it had them (`JoystickMap`).
//
// Pins are the desk's favorites (`Favorites`, the table played), which Twin
// Rings' Y layer and the Favorites tab play and edit too: a chord holds up
// to eight, one to each of the stick's directions, the first at the top and
// on clockwise.
//
// - LB pressed while the stick colors a chord held pins that color to its
//   degree, or takes it out if it is pinned there already.
// - LB held puts the pins on the stick: each direction plays the chord's pin
//   there, and one with none plays the chord plain. Pressed while coloring,
//   the stick keeps the color it pinned until it moves to another direction
//   or comes back to the middle, so nothing jumps.
//
// LB's other uses are the second voice's, read from the face buttons' presses,
// so nothing of either reads the other: with LB held, a face button pressed
// goes to the second voice as before, and the stick plays its chord's pins.
//
// It has no Swift original: like the drums and the timeline it is played
// beside the desk (`Studio`), and hands Face Chords a color for each degree.

#ifndef PERFECTO_DESK_FACE_COLORS_HPP
#define PERFECTO_DESK_FACE_COLORS_HPP

#include "perfecto/desk/face_chords.hpp"
#include "perfecto/desk/gates.hpp"
#include "perfecto/desk/layout.hpp"
#include "perfecto/desk/music.hpp"
#include "perfecto/desk/pad.hpp"

#include <perfecto/theory/chord_color.hpp>

#include <array>
#include <map>
#include <optional>
#include <string>
#include <vector>

namespace perfecto::desk {

/// One of the Orchid's eight chord buttons.
enum class OrchidButton { maj, minorSeventh, ninth, majorSeventh, min, sixth, dim, sus };

/// What its button is marked: "Maj", "m7".
std::string mark(OrchidButton button);

class FaceColors {
public:
    /// The Orchid's buttons round the stick, clockwise from up.
    static constexpr std::array<OrchidButton, 8> ring = {
        OrchidButton::maj, OrchidButton::minorSeventh, OrchidButton::ninth, OrchidButton::majorSeventh,
        OrchidButton::min, OrchidButton::sixth,        OrchidButton::dim,   OrchidButton::sus,
    };

    /// The stick's eight directions, the first at the top and on clockwise.
    static const PieGate &gate();

    /// The joystick's direction at each of the gate's.
    static theory::JoystickDirection direction(int sector);

    /// The color the stick gives in `stick`'s scheme, aimed at `aim` having
    /// first leaned to `anchor`: plain at rest.
    static theory::ChordColor live(FaceStick stick, std::optional<int> anchor, std::optional<int> aim);

    /// The Orchid's buttons held at `anchor` and `aim` (the later), as a
    /// build: of two types the later, and the extensions of both.
    static theory::ChordBuild build(OrchidButton anchor, OrchidButton aim);

    /// What a step did: the colors Face Chords strikes each degree in from
    /// now, and what to feel and show.
    struct Step {
        std::map<theory::Degree, theory::ChordColor> colors;
        std::vector<DeskEffect> effects;
        bool operator==(const Step &) const = default;
    };

    bool operator==(const FaceColors &) const = default;

    /// The direction the stick is on, if it leans.
    std::optional<int> aim() const { return aim_; }
    /// The direction it first leaned to, which the Orchid's buttons hold on.
    std::optional<int> anchor() const { return anchor_; }
    /// Whether LB holds the pins on the stick.
    bool isOnPins() const { return isOnPins_; }

    /// One frame of the hands. `face` is Face Chords as it is before the
    /// desk is stepped, so what it sounds is what LB pins; `reachable`,
    /// whether Face Chords is played now (with the menu closed).
    Step step(const PadInput &input, bool reachable, const FaceChords &face, DeskSettings &settings);

    /// Forgets the stick, as if it were at rest.
    void reset();

    /// The color the stick gives `degree`'s chord now.
    theory::ChordColor color(theory::Degree degree, const DeskSettings &settings) const;

    /// What each of the stick's directions plays on `degree`, or with none,
    /// what it does; a pin's place with no pin in it is empty.
    std::vector<std::optional<Target>> targets(std::optional<theory::Degree> degree,
                                               const DeskSettings &settings) const;

    /// What the left stick and LB do now, over `legend`.
    Legend legend(Legend legend, bool reachable, const DeskSettings &settings) const;

private:
    std::optional<int> aim_;
    std::optional<int> anchor_;
    bool isOnPins_ = false;
    /// LB pressed while coloring: the direction the color is kept on, until
    /// the stick leaves it.
    std::optional<int> keepsLive_;

    /// The color at `aim` given `anchor` (the Orchid's only), in the layer
    /// the stick is in.
    theory::ChordColor colorAt(std::optional<int> anchor, std::optional<int> aim, theory::Degree degree,
                               const DeskSettings &settings) const;
    /// Pins what Face Chords sounds, or takes it out if it is pinned.
    std::vector<DeskEffect> pin(const FaceChords &face, DeskSettings &settings) const;
};

} // namespace perfecto::desk

#endif
