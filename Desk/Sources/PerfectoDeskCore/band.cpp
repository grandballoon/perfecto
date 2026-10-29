#include "perfecto/desk/band.hpp"

#include "perfecto/desk/scene.hpp"

namespace perfecto::desk {

bool Band::reachable() const { return desk_.layout() == LayoutKind::faceChords && !desk_.menu(); }

Band::Played Band::step(const GamepadFrame &frame) {
    const GamepadFrame previous = frame_ ? *frame_ : GamepadFrame{.time = frame.time};
    frame_ = frame;
    Drums::Step drummed = drums_.step(PadInput(frame, previous), reachable(), desk_.settings);
    Played out = settled(desk_.step(drummed.frame));
    out.effects.insert(out.effects.end(), drummed.effects.begin(), drummed.effects.end());
    out.drums = std::move(drummed.drums);
    return out;
}

Band::Played Band::choose(LayoutKind layout) { return settled(desk_.choose(layout)); }

Band::Played Band::toggleMenu() { return settled(desk_.toggleMenu()); }

Band::Played Band::letGo() {
    drums_.stop();
    return {desk_.letGo(), {}};
}

Band::Played Band::perform(const Action &action) { return settled(desk::perform(desk_, action)); }

Legend Band::legend() const { return drums_.legend(desk_.legend(), reachable()); }

Band::Played Band::settled(std::vector<DeskEffect> effects) {
    if (desk_.layout() != LayoutKind::faceChords) drums_.stop();
    return {std::move(effects), {}};
}

} // namespace perfecto::desk
