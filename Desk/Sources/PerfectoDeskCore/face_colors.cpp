#include "perfecto/desk/face_colors.hpp"

#include <perfecto/theory/joystick.hpp>

#include <algorithm>
#include <set>

namespace perfecto::desk {

using namespace theory;

namespace {

std::optional<ChordType> type(OrchidButton button) {
    switch (button) {
    case OrchidButton::maj: return ChordType::major;
    case OrchidButton::min: return ChordType::minor;
    case OrchidButton::dim: return ChordType::diminished;
    case OrchidButton::sus: return ChordType::suspended;
    default: return std::nullopt;
    }
}

std::optional<ChordExtension> extension(OrchidButton button) {
    switch (button) {
    case OrchidButton::sixth: return ChordExtension::sixth;
    case OrchidButton::minorSeventh: return ChordExtension::minorSeventh;
    case OrchidButton::majorSeventh: return ChordExtension::majorSeventh;
    case OrchidButton::ninth: return ChordExtension::ninth;
    default: return std::nullopt;
    }
}

JoystickMode mode(FaceStick stick) {
    switch (stick) {
    case FaceStick::perfectoExtended: return JoystickMode::extended;
    case FaceStick::perfectoChromatic: return JoystickMode::chromatic;
    default: return JoystickMode::default_;
    }
}

/// The buttons held at `aim` having first leaned to `anchor`, marked: "Maj + m7".
std::string marks(std::optional<int> anchor, int aim) {
    const std::string held = mark(FaceColors::ring[static_cast<size_t>(aim)]);
    if (!anchor || *anchor == aim) return held;
    return mark(FaceColors::ring[static_cast<size_t>(*anchor)]) + " + " + held;
}

} // namespace

std::string mark(OrchidButton button) {
    switch (button) {
    case OrchidButton::maj: return "Maj";
    case OrchidButton::minorSeventh: return "m7";
    case OrchidButton::ninth: return "9";
    case OrchidButton::majorSeventh: return "M7";
    case OrchidButton::min: return "Min";
    case OrchidButton::sixth: return "6";
    case OrchidButton::dim: return "Dim";
    case OrchidButton::sus: return "Sus";
    }
    return {};
}

const PieGate &FaceColors::gate() {
    static const PieGate gate = PieGate::even(static_cast<int>(ring.size()));
    return gate;
}

JoystickDirection FaceColors::direction(int sector) {
    // The joystick's directions after its middle, clockwise from up as the gate's are.
    return allJoystickDirections[static_cast<size_t>(sector) + 1];
}

ChordBuild FaceColors::build(OrchidButton anchor, OrchidButton aim) {
    std::set<ChordExtension> extensions;
    for (const OrchidButton button : {anchor, aim})
        if (const auto added = extension(button)) extensions.insert(*added);
    return ChordBuild(type(aim) ? type(aim) : type(anchor), extensions);
}

ChordColor FaceColors::live(FaceStick stick, std::optional<int> anchor, std::optional<int> aim) {
    if (!aim) return ChordColor::base();
    if (stick != FaceStick::orchid) return ChordColor::joystick(mode(stick), direction(*aim));
    return ChordColor::built(build(ring[static_cast<size_t>(anchor.value_or(*aim))], ring[static_cast<size_t>(*aim)]));
}

void FaceColors::reset() {
    aim_ = anchor_ = keepsLive_ = std::nullopt;
    isOnPins_ = false;
}

FaceColors::Step FaceColors::step(const PadInput &input, bool reachable, const FaceChords &face,
                                  DeskSettings &settings) {
    if (!reachable) {
        reset();
        return {};
    }
    Step out;
    const bool pins = input.isDown(PadButton::lb);
    aim_ = gate().select(input.frame.left, aim_);
    // The Orchid's first button is held from the first lean until the stick
    // is back in the middle.
    if (!aim_) anchor_ = std::nullopt;
    else if (!anchor_) anchor_ = aim_;
    if (keepsLive_ != aim_) keepsLive_ = std::nullopt;

    if (pins != isOnPins_) {
        if (pins && aim_ && !live(settings.faceStick, anchor_, aim_).isBase()) {
            // LB while coloring pins what sounds, and the color stays until the stick moves on.
            out.effects = pin(face, settings);
            keepsLive_ = aim_;
        } else if (!keepsLive_) {
            // Each layer starts the Orchid's buttons afresh; a color kept keeps them.
            anchor_ = aim_;
        }
        if (!pins) keepsLive_ = std::nullopt;
    }
    isOnPins_ = pins;

    for (const Degree degree : allDegrees) {
        const ChordColor shade = color(degree, settings);
        if (!shade.isBase()) out.colors.emplace(degree, shade);
    }
    return out;
}

ChordColor FaceColors::colorAt(std::optional<int> anchor, std::optional<int> aim, Degree degree,
                               const DeskSettings &settings) const {
    if (!aim) return ChordColor::base();
    if (!isOnPins_ || keepsLive_ == aim) return live(settings.faceStick, anchor, aim);
    const auto pinned = settings.favorites.colors(settings.key, degree);
    return *aim < static_cast<int>(pinned.size()) ? pinned[static_cast<size_t>(*aim)] : ChordColor::base();
}

ChordColor FaceColors::color(Degree degree, const DeskSettings &settings) const {
    return colorAt(anchor_, aim_, degree, settings);
}

std::vector<DeskEffect> FaceColors::pin(const FaceChords &face, DeskSettings &settings) const {
    // Each chord sounding once: both voices on one degree are one pin.
    std::set<DeskChord> chords;
    for (const auto &voice : face.voices())
        if (voice.line.isSounding() && voice.line.chord()) chords.insert(*voice.line.chord());
    std::vector<DeskEffect> out;
    for (const DeskChord &chord : chords) {
        const auto place = Favorites::pinOf(chord, settings.key);
        if (!place) continue;
        const auto pinned = settings.favorites.colors(settings.key, place->degree);
        const auto at = std::find(pinned.begin(), pinned.end(), place->color);
        if (at != pinned.end()) {
            settings.favorites.unpin(settings.key, place->degree, static_cast<int>(at - pinned.begin()));
            out.push_back(DeskEffect::rumble(Rumble::tick));
        } else if (settings.favorites.pin(chord, settings.key)) {
            out.push_back(DeskEffect::rumble(Rumble::bump));
        } else {
            out.push_back(DeskEffect::refuse(numeral(place->degree, settings.key) + " holds " +
                                             std::to_string(Favorites::perChord) + " pins already"));
        }
    }
    return out;
}

std::vector<std::optional<Target>> FaceColors::targets(std::optional<Degree> degree,
                                                       const DeskSettings &settings) const {
    const auto &bearings = gate().bearings;
    std::vector<std::optional<Target>> out;
    if (isOnPins_) {
        const auto pinned = degree ? settings.favorites.colors(settings.key, *degree) : std::vector<ChordColor>();
        for (int index = 0; index < static_cast<int>(ring.size()); ++index) {
            if (!degree || index >= static_cast<int>(pinned.size())) {
                out.push_back(std::nullopt);
                continue;
            }
            const DeskChord chord(settings.key, *degree, pinned[static_cast<size_t>(index)]);
            out.push_back(Target{.bearing = bearings[static_cast<size_t>(index)],
                                 .name = chord.name(),
                                 .detail = std::to_string(index + 1),
                                 .fit = chord.fit(settings.key),
                                 .isAimed = aim_ == index && keepsLive_ != aim_,
                                 .isHidden = !settings.playable(chord)});
        }
        return out;
    }
    for (int index = 0; index < static_cast<int>(ring.size()); ++index) {
        // With a button held, each other direction is what rolling on to it adds.
        const std::string does = settings.faceStick == FaceStick::orchid
                                     ? marks(anchor_, index)
                                     : joystickOutcome(mode(settings.faceStick), direction(index)).action;
        Target target{.bearing = bearings[static_cast<size_t>(index)], .name = does};
        if (degree) {
            const DeskChord chord(settings.key, *degree, live(settings.faceStick, anchor_, index));
            target.name = chord.name();
            target.detail = does;
            target.fit = chord.fit(settings.key);
            target.isHidden = !settings.playable(chord);
        }
        target.isAimed = aim_ == index;
        target.isKept = settings.faceStick == FaceStick::orchid && anchor_ == index && aim_ != index;
        out.push_back(target);
    }
    return out;
}

Legend FaceColors::legend(Legend legend, bool reachable, const DeskSettings &settings) const {
    if (!reachable) return legend;
    legend[PadControl::leftStick()] =
        isOnPins_ ? "The pins of the chord held"
                  : "Color: " + name(settings.faceStick) +
                        (settings.faceStick == FaceStick::orchid ? " · roll on for two" : "");
    const auto lb = legend.find(PadControl::button(PadButton::lb));
    const std::string pins = "press while coloring: pin · hold: the pins";
    legend[PadControl::button(PadButton::lb)] = lb == legend.end() ? "Press while coloring: pin · hold: the pins"
                                                                   : lb->second + " · " + pins;
    return legend;
}

} // namespace perfecto::desk
