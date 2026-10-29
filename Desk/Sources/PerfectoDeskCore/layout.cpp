#include "perfecto/desk/layout.hpp"

#include <perfecto/theory/color_steps.hpp>
#include <perfecto/theory/naming.hpp>

#include <algorithm>
#include <utility>

namespace perfecto::desk {

using namespace theory;

std::string name(LayoutKind kind) {
    switch (kind) {
    case LayoutKind::twinRings: return "Twin Rings";
    case LayoutKind::petals: return "Petals & Depth";
    case LayoutKind::neighbourhood: return "Neighbourhood";
    case LayoutKind::twoVoices: return "Two Voices";
    case LayoutKind::arranger: return "Arranger";
    }
    return {};
}

std::string summary(LayoutKind kind) {
    switch (kind) {
    case LayoutKind::twinRings:
        return "Left stick the degree, right stick the color ring, RT strikes: 154 chords in one gesture.";
    case LayoutKind::petals:
        return "Left stick the degree, the face buttons strike at four heights, the triggers bend darker and brighter.";
    case LayoutKind::neighbourhood:
        return "Only the chords one step from where you are: flick to move there, hold to listen.";
    case LayoutKind::twoVoices:
        return "The left hand swells the chords, the right plays a line over them with RT as pressure.";
    case LayoutKind::arranger:
        return "Aim a chord with both sticks and write it into four bars; play them back in a loop.";
    }
    return {};
}

bool voicingPad(const PadInput &input, DeskSettings &settings) {
    const auto before = std::pair(settings.octave, settings.inversion);
    if (input.pressed(PadButton::left)) settings.roll(-1);
    if (input.pressed(PadButton::right)) settings.roll(1);
    if (input.pressed(PadButton::up)) settings.moveOctave(1);
    if (input.pressed(PadButton::down)) settings.moveOctave(-1);
    return before != std::pair(settings.octave, settings.inversion);
}

Legend commonLegend(const DeskSettings &, bool voicing) {
    Legend legend = {{PadControl::button(PadButton::back), "Next layout"},
                     {PadControl::button(PadButton::start), "Menu"}};
    if (voicing) {
        legend[PadControl::button(PadButton::left)] = "Inversion down";
        legend[PadControl::button(PadButton::right)] = "Inversion up";
        legend[PadControl::button(PadButton::up)] = "Octave up";
        legend[PadControl::button(PadButton::down)] = "Octave down";
    }
    return legend;
}

// DeskChord, from Layout.swift.

bool DeskChord::isOneStep(const std::optional<DeskChord> &other) const {
    if (!other || other->root() != root()) return false;
    return colorSteps(tones().pitchClasses(), other->tones().pitchClasses()) == 1;
}

std::set<int> DeskChord::pitchClasses() const {
    const int rootClass = raw(root());
    std::set<int> pitches;
    const ChordTones tones = this->tones();
    for (int tone : tones.pitchClasses()) pitches.insert((tone + rootClass) % 12);
    return pitches;
}

bool DeskChord::sharesTwo(const std::optional<DeskChord> &other) const {
    if (!other || *other == *this) return false;
    const std::set<int> mine = pitchClasses(), theirs = other->pitchClasses();
    const auto shared = std::count_if(mine.begin(), mine.end(), [&](int pitch) { return theirs.contains(pitch); });
    return shared >= 2;
}

std::string numeral(Degree degree, const Key &key) { return degreeNumeral(key, degree); }

std::vector<Target> degreeTargets(Degree chosen, const std::optional<DeskChord> &sounding,
                                  const DeskSettings &settings) {
    std::optional<DeskChord> plain;
    if (sounding) plain = DeskChord(sounding->key, sounding->spec.degree);
    std::vector<Target> targets;
    for (size_t sector = 0; sector < DegreePie::order.size(); ++sector) {
        const Degree degree = DegreePie::order[sector];
        const DeskChord chord(settings.key, degree);
        targets.push_back(Target{DegreePie::gate().bearings[sector], chord.name(), numeral(degree, settings.key),
                                 ChordFit::inKey, chord.sharesTwo(plain), degree == chosen, false,
                                 !settings.playable(chord)});
    }
    return targets;
}

} // namespace perfecto::desk
