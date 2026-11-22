// Which hand holds what in Face Chords, read before the cores beside the desk.
//
// LB and RB held together are the timeline's layer. Each is kept from the
// others from then until it is let go, so letting go of one does not press
// the other's own use (the pins, the drum pads).
//
// RT is the chords' second layer and LT the compass's outer ring. The desk's
// Face Chords reads its layer from LT, as the Swift core it is compared with
// does, so `Studio` hands it RT there.

#ifndef PERFECTO_DESK_FACE_HANDS_HPP
#define PERFECTO_DESK_FACE_HANDS_HPP

#include "perfecto/desk/pad.hpp"

#include <set>

namespace perfecto::desk {

class FaceHands {
public:
    struct Read {
        /// The frame without the bumpers the timeline's layer has kept.
        GamepadFrame frame;
        /// Whether LB and RB are both held.
        bool isTimeline = false;
        bool operator==(const Read &) const = default;
    };

    bool operator==(const FaceHands &) const = default;

    /// One frame of the hands; with Face Chords out of reach, it is as played.
    Read read(const GamepadFrame &frame, bool reachable);

    /// The chords' layer trigger: RT, which stays where it was while the
    /// timeline's layer is held.
    double chordLayer(double rightTrigger, bool isTimeline);

    bool isTimeline() const { return isTimeline_; }

private:
    std::set<PadButton> kept_;
    bool isTimeline_ = false;
    double chordLayer_ = 0;
};

} // namespace perfecto::desk

#endif
