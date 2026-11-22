#include "perfecto/desk/face_hands.hpp"

namespace perfecto::desk {

FaceHands::Read FaceHands::read(const GamepadFrame &frame, bool reachable) {
    if (!reachable) {
        kept_.clear();
        isTimeline_ = false;
        return {frame, false};
    }
    isTimeline_ = frame.isDown(PadButton::lb) && frame.isDown(PadButton::rb);
    if (isTimeline_) kept_ = {PadButton::lb, PadButton::rb};
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
