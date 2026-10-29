#include "perfecto/theory/chord_color.hpp"

namespace perfecto::theory {

ChordColor ChordColor::tertian(StackHeight height, std::optional<HeptatonicMode> mode, const ToneMarks &marks) {
    if (marks.isEmpty()) return grid(height, mode);
    return marked(height, mode, marks);
}

bool ChordColor::isBase() const {
    if (const auto *j = std::get_if<Joystick>(&value_)) return j->direction == JoystickDirection::center;
    if (const auto *g = std::get_if<Grid>(&value_)) return g->height == StackHeight::triad && !g->mode;
    if (const auto *b = std::get_if<Built>(&value_)) return !b->type() && b->extensions().empty();
    return false;
}

std::optional<JoystickDirection> ChordColor::direction(JoystickMode mode) const {
    const auto *j = std::get_if<Joystick>(&value_);
    if (!j || j->mode != mode || j->direction == JoystickDirection::center) return std::nullopt;
    return j->direction;
}

} // namespace perfecto::theory
