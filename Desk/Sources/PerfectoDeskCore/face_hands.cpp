#include "perfecto/desk/face_hands.hpp"

#include <algorithm>

namespace perfecto::desk {

FaceHands::Read FaceHands::read(const GamepadFrame &frame, bool reachable) {
    const bool back = frame.isDown(PadButton::back);
    const bool pressed = back && !wasBack_;
    wasBack_ = back;
    if (!reachable) {
        kept_.clear();
        isTimeline_ = false;
        return {frame, false};
    }
    if (pressed) {
        // With RB held in play, Back is the drums' (the kit before). An RB
        // still held from the timeline is not the drums', so Back does nothing.
        if (isTimeline_ || !frame.isDown(PadButton::rb)) {
            isTimeline_ = !isTimeline_;
            kept_.insert(PadButton::back);
        } else if (kept_.contains(PadButton::rb)) {
            kept_.insert(PadButton::back);
        }
    }
    if (isTimeline_ && frame.isDown(PadButton::rb)) kept_.insert(PadButton::rb);
    std::erase_if(kept_, [&](PadButton button) { return !frame.isDown(button); });
    Read out{frame, isTimeline_};
    for (const PadButton button : kept_) out.frame.buttons.erase(button);
    return out;
}

double FaceHands::chordLayer(double rightTrigger, bool isTimeline) {
    if (!isTimeline) chordLayer_ = rightTrigger;
    return chordLayer_;
}

} // namespace perfecto::desk
