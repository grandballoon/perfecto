// The desk and the timeline, played together from one controller.
//
// Each frame goes to the timeline first, which takes what RT holds
// (`Timeline::take`), and the desk is stepped with what is left, so the desk
// knows nothing of the timeline and plays as the parity test has it. The
// timeline then hears what the desk sounds, to record it or write it into
// the chords chosen, and gives what plays back. It is played in Face Chords,
// with the menu closed, and stops when the desk goes to another layout; it
// plays on under the menu, so a tempo chosen there is heard.
//
// The drums are composed with the desk the same way (`Band`, on their own
// branch): when both are here, the drums take their buttons first, then the
// timeline, then the desk, and the timeline hears the drums' hits as it hears
// the desk's chords.

#ifndef PERFECTO_DESK_STUDIO_HPP
#define PERFECTO_DESK_STUDIO_HPP

#include "perfecto/desk/desk.hpp"
#include "perfecto/desk/pad.hpp"
#include "perfecto/desk/scene.hpp"
#include "perfecto/desk/timeline.hpp"

#include <optional>
#include <vector>

namespace perfecto::desk {

/// What each voice of the desk's chords is sounding, in Face Chords.
Heard heard(const Desk &desk);

class Studio {
public:
    /// What a step did: the desk's effects, and what the timeline plays back.
    struct Played {
        std::vector<DeskEffect> effects;
        std::vector<TimelineEffect> playback;
        bool operator==(const Played &) const = default;

        void append(std::vector<DeskEffect> more);
        void append(Timeline::Out out);
        void append(Played more);
    };

    explicit Studio(Desk desk) : desk_(std::move(desk)) {}

    bool operator==(const Studio &) const = default;

    const Desk &desk() const { return desk_; }
    const Timeline &timeline() const { return timeline_; }
    /// The last frame as the hands played it, before the timeline took its share.
    const std::optional<GamepadFrame> &frame() const { return frame_; }
    /// When the last frame came.
    double time() const { return frame_ ? frame_->time : 0; }

    /// Whether the hands can play the timeline now.
    bool reachable() const;

    Played step(const GamepadFrame &frame);

    /// As the desk's own, and the timeline stops if the layout changes.
    Played choose(LayoutKind layout);
    Played toggleMenu();
    /// Lets go of everything, and stops the timeline: the app is quitting.
    Played letGo();
    /// Does what a mouse chose.
    Played perform(const Action &action);

    void setFaceMap(FaceChords::Map map) { desk_.setFaceMap(std::move(map)); }

    /// What every control does now, the timeline's over the desk's.
    Legend legend() const;

private:
    Desk desk_;
    Timeline timeline_;
    std::optional<GamepadFrame> frame_;

    /// The timeline goes with Face Chords.
    Played settled(std::vector<DeskEffect> effects);
};

/// The timeline's bar, as `studio` shows it at `time`.
TimelineBar timelineBar(const Timeline &timeline, double time);

/// What `studio` shows: the desk's scene, with the timeline's bar over Face
/// Chords and its controls in the hand.
Scene scene(const Studio &studio, bool keyboard);

} // namespace perfecto::desk

#endif
