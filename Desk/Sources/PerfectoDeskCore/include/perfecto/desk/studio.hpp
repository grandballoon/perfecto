// The desk, the drums, the timeline and the left hand's colors, played
// together from one controller.
//
// Each frame goes to the drums first, which take the buttons they play
// (`Drums`), then to the timeline, which takes what RT holds
// (`Timeline::take`), then to the colors, which read the left stick and LB
// and give Face Chords a color for each degree (`FaceColors`), and the desk
// is stepped with what is left, so the desk knows nothing of them and plays
// as the parity test has it. The timeline
// then hears what the desk sounds, to record it or write it into the chords
// chosen, and gives what plays back. The drums and the timeline are played in
// Face Chords, with the menu closed, and stop when the desk goes to another
// layout; they play on under the menu, so a tempo chosen there is heard.
//
// The timeline does not record the drums yet: it hears the desk's chords
// alone.

#ifndef PERFECTO_DESK_STUDIO_HPP
#define PERFECTO_DESK_STUDIO_HPP

#include "perfecto/desk/desk.hpp"
#include "perfecto/desk/drums.hpp"
#include "perfecto/desk/face_colors.hpp"
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
    /// What a step did: the desk's effects, the drums', and what the
    /// timeline plays back.
    struct Played {
        std::vector<DeskEffect> effects;
        std::vector<DrumEffect> drums;
        std::vector<TimelineEffect> playback;
        bool operator==(const Played &) const = default;

        void append(std::vector<DeskEffect> more);
        void append(Timeline::Out out);
        void append(Played more);
    };

    explicit Studio(Desk desk) : desk_(std::move(desk)) {}

    bool operator==(const Studio &) const = default;

    const Desk &desk() const { return desk_; }
    const Drums &drums() const { return drums_; }
    const Timeline &timeline() const { return timeline_; }
    const FaceColors &colors() const { return colors_; }
    /// The last frame as the hands played it, before the drums and the
    /// timeline took their share.
    const std::optional<GamepadFrame> &frame() const { return frame_; }
    /// When the last frame came.
    double time() const { return frame_ ? frame_->time : 0; }

    /// Whether the hands can play the drums and the timeline now.
    bool reachable() const;

    Played step(const GamepadFrame &frame);

    /// As the desk's own, and the beat and the timeline stop if the layout
    /// changes.
    Played choose(LayoutKind layout);
    Played toggleMenu();
    /// Lets go of everything, and stops the beat and the timeline: the app
    /// is quitting.
    Played letGo();
    /// Does what a mouse chose.
    Played perform(const Action &action);

    void setFaceMap(FaceChords::Map map) { desk_.setFaceMap(std::move(map)); }

    /// What every control does now, the drums' over the timeline's over the
    /// colors' over the desk's.
    Legend legend() const;

private:
    Desk desk_;
    Drums drums_;
    Timeline timeline_;
    FaceColors colors_;
    std::optional<GamepadFrame> frame_;
    /// The last frame as the drums left it, for the timeline's edges.
    std::optional<GamepadFrame> drummed_;
    /// The last frame as the timeline left it, for the colors' edges.
    std::optional<GamepadFrame> taken_;

    /// The beat and the timeline go with Face Chords.
    Played settled(std::vector<DeskEffect> effects);
};

/// The timeline's bar, as `studio` shows it at `time`.
TimelineBar timelineBar(const Timeline &timeline, double time);

/// What `studio` shows: the desk's scene, with the timeline's bar over Face
/// Chords, the drums under it, and their controls in the hand.
Scene scene(const Studio &studio, bool keyboard);

} // namespace perfecto::desk

#endif
