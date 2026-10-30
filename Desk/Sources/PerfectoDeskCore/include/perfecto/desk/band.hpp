// The desk and the drums, played together from one controller.
//
// Each frame goes to the drums first, which take the buttons they play
// (`Drums`), and the desk is stepped with what is left, so the desk knows
// nothing of the drums and plays as the parity test has it. The drums are
// played in Face Chords, with the menu closed, and the beat stops when the
// desk goes to another layout; it plays on under the menu, so a tempo chosen
// there is heard.

#ifndef PERFECTO_DESK_BAND_HPP
#define PERFECTO_DESK_BAND_HPP

#include "perfecto/desk/desk.hpp"
#include "perfecto/desk/drums.hpp"
#include "perfecto/desk/pad.hpp"

#include <optional>
#include <vector>

namespace perfecto::desk {

struct Action;

class Band {
public:
    /// What a step did: the desk's effects, and the drums'.
    struct Played {
        std::vector<DeskEffect> effects;
        std::vector<DrumEffect> drums;
        bool operator==(const Played &) const = default;
    };

    /// The desk, and the drums with the kits the shell has.
    explicit Band(Desk desk, Drums drums = Drums()) : desk_(std::move(desk)), drums_(std::move(drums)) {}

    const Desk &desk() const { return desk_; }
    const Drums &drums() const { return drums_; }
    /// The last frame as the hands played it, before the drums took theirs.
    const std::optional<GamepadFrame> &frame() const { return frame_; }

    /// Whether the hands can play the drums now.
    bool reachable() const;

    Played step(const GamepadFrame &frame);

    /// As the desk's own, and the beat stops if the layout changes.
    Played choose(LayoutKind layout);
    Played toggleMenu();
    /// Lets go of everything, and stops the beat: the app is quitting.
    Played letGo();
    /// Does what a mouse chose at `time`: the drums' pattern or kit here,
    /// the rest by the desk (`perform` in scene.hpp).
    Played perform(const Action &action, double time);

    void setFaceMap(FaceChords::Map map) { desk_.setFaceMap(std::move(map)); }

    /// What every control does now, the drums' over the desk's.
    Legend legend() const;

private:
    Desk desk_;
    Drums drums_;
    std::optional<GamepadFrame> frame_;

    /// The beat goes with Face Chords.
    Played settled(std::vector<DeskEffect> effects);
};

} // namespace perfecto::desk

#endif
