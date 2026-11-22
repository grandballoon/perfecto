// Which hand holds what in Face Chords, read before the cores beside the desk.
//
// The timeline is a state the hands are in or not: Back goes into it and comes
// out, and in it every button is the timeline's alone. RB + Back in play stays
// the drums' (the kit before). Back, and an RB pressed in the timeline, are
// kept from the others until let go, so neither reaches the desk's layouts or
// the drum pads.
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
        /// The frame without the buttons kept from the others.
        GamepadFrame frame;
        /// Whether the hands are in the timeline.
        bool isTimeline = false;
        bool operator==(const Read &) const = default;
    };

    bool operator==(const FaceHands &) const = default;

    /// One frame of the hands; with Face Chords out of reach, it is as played.
    Read read(const GamepadFrame &frame, bool reachable);

    /// The chords' layer trigger: RT, which stays where it was while the
    /// hands are in the timeline.
    double chordLayer(double rightTrigger, bool isTimeline);

    bool isTimeline() const { return isTimeline_; }

    /// Back to playing: recording or writing has begun, and the face buttons
    /// are for the chords.
    void leave() { isTimeline_ = false; }

private:
    std::set<PadButton> kept_;
    bool isTimeline_ = false;
    bool wasBack_ = false;
    double chordLayer_ = 0;
};

} // namespace perfecto::desk

#endif
