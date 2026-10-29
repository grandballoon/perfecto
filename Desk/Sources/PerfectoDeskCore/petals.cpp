#include "perfecto/desk/petals.hpp"

#include "perfecto/desk/gates.hpp"
#include "perfecto/desk/ring_pie.hpp"

#include <perfecto/theory/chord_color.hpp>
#include <perfecto/theory/modes.hpp>

#include <algorithm>
#include <cmath>

namespace perfecto::desk {

using namespace theory;

std::string name(Petals::Mark mark) {
    switch (mark) {
    case Petals::Mark::sus4: return "▲3 sus4";
    case Petals::Mark::sixth: return "+6";
    case Petals::Mark::add9: return "+9";
    case Petals::Mark::raisedFifth: return "▲5";
    }
    return {};
}

ChordTones applied(Petals::Mark mark, const ChordTones &triad) {
    std::vector<int> tones = triad.pitchClasses();
    switch (mark) {
    case Petals::Mark::sus4:
        std::erase_if(tones, [](int tone) { return tone == 3 || tone == 4; });
        tones.push_back(5);
        return ChordTones(tones);
    case Petals::Mark::sixth:
        tones.push_back(9);
        return ChordTones(tones);
    case Petals::Mark::add9:
        tones.push_back(2);
        return ChordTones(tones);
    case Petals::Mark::raisedFifth:
        for (int &tone : tones)
            if (6 <= tone && tone <= 7) tone += 1;
        return ChordTones(tones);
    }
    return triad;
}

const std::map<PadButton, StackHeight> &Petals::heights() {
    static const std::map<PadButton, StackHeight> table = {
        {PadButton::a, StackHeight::triad},
        {PadButton::x, StackHeight::seventh},
        {PadButton::y, StackHeight::ninth},
        {PadButton::b, StackHeight::eleventh},
    };
    return table;
}

const std::map<PadButton, Petals::Mark> &Petals::marks() {
    static const std::map<PadButton, Mark> table = {
        {PadButton::a, Mark::sus4},
        {PadButton::x, Mark::add9},
        {PadButton::y, Mark::raisedFifth},
        {PadButton::b, Mark::sixth},
    };
    return table;
}

Petals::Petals() : degreeSector_(DegreePie::sector(Degree::I)) {}

bool Petals::operator==(const Petals &other) const {
    return degree_ == other.degree_ && darker_ == other.darker_ && brighter_ == other.brighter_ &&
           presses_ == other.presses_ && holds_ == other.holds_ && line_ == other.line_ &&
           arpeggio_ == other.arpeggio_ && bend_ == other.bend_ && bendKept_ == other.bendKept_ &&
           isMarking_ == other.isMarking_ && isOnEffects_ == other.isOnEffects_;
}

namespace {

void append(std::vector<DeskEffect> &out, std::vector<DeskEffect> more) {
    out.insert(out.end(), std::make_move_iterator(more.begin()), std::make_move_iterator(more.end()));
}

} // namespace

std::vector<DeskEffect> Petals::step(const PadInput &input, DeskSettings &settings) {
    std::vector<DeskEffect> out;
    const double time = input.time();
    isMarking_ = input.isDown(PadButton::lb);
    isOnEffects_ = input.isDown(PadButton::rb);

    // The d-pad: the key round the circle of fifths, and its scale.
    if (input.pressed(PadButton::left)) settings.moveKey(-1);
    if (input.pressed(PadButton::right)) settings.moveKey(1);
    if (input.pressed(PadButton::up)) settings.moveScale(1);
    if (input.pressed(PadButton::down)) settings.moveScale(-1);
    if (input.pressed(PadButton::l3)) {
        holds_ = !holds_;
        if (!holds_ && presses_.empty()) append(out, line_.release());
    }

    degreeSector_ = DegreePie::gate().select(input.frame.left, degreeSector_);
    if (degreeSector_ && input.frame.left.radius() >= PieGate::rest) degree_ = DegreePie::degree(*degreeSector_);

    // The triggers: darker and brighter, a detent felt at each sector.
    const int dark = TriggerSteps::three().step(input.frame.leftTrigger, darker_);
    const int bright = TriggerSteps::three().step(input.frame.rightTrigger, brighter_);
    if (dark != darker_ || bright != brighter_) out.push_back(DeskEffect::rumble(Rumble::tick));
    darker_ = dark;
    brighter_ = bright;

    // The right stick: the voicing bent while it leans, R3 keeps it.
    const Stick right = input.frame.right;
    if (right.radius() < PieGate::rest) bendKept_ = false;
    const Bend leaned = bendKept_ ? Bend{0, 0} : bendOf(right);
    if (input.pressed(PadButton::r3) && leaned != Bend{0, 0}) {
        settings.moveOctave(leaned.octaves);
        settings.roll(leaned.roll);
        bendKept_ = true;
        out.push_back(DeskEffect::rumble(Rumble::bump));
    }
    bend_ = bendKept_ ? Bend{0, 0} : leaned;

    // The face buttons: a petal each, or on RB the effects.
    for (PadButton button : diamond) {
        if (input.pressed(button)) {
            if (isOnEffects_) {
                append(out, effect(button, settings, time));
            } else {
                const Petal petal = isMarking_ ? Petal::mark(marks().at(button)) : Petal::height(heights().at(button));
                if (const auto why = settings.consonance.refusal(chord(petal, settings), settings.key)) {
                    out.push_back(DeskEffect::refuse(*why));
                } else {
                    presses_.push_back(Press{button, petal});
                    append(out, line_.strike(chord(petal, settings), 0.8, settings, time));
                }
            }
        }
        if (input.released(button)) {
            const auto at = std::find_if(presses_.begin(), presses_.end(),
                                         [&](const Press &press) { return press.button == button; });
            if (at != presses_.end()) {
                presses_.erase(at);
                if (presses_.empty() && !holds_) append(out, line_.release());
            }
        }
    }

    // What sounds follows the hands, as far as the guard lets it: the
    // press heard is the latest.
    if (!presses_.empty()) {
        const Petal petal = presses_.back().petal;
        if (settings.playable(chord(petal, settings))) append(out, line_.change(chord(petal, settings), settings));
    } else if (line_.chord() && line_.isSounding()) {
        const DeskChord next(settings.key, degree_, line_.chord()->spec.color);
        if (settings.playable(next)) append(out, line_.change(next, settings));
    }
    append(out, line_.bend(bend_.octaves, bend_.roll, settings));
    append(out, line_.arpeggiate(arpeggio_, settings, time));
    append(out, line_.tick(settings, time));
    return out;
}

std::vector<DeskEffect> Petals::effect(PadButton button, DeskSettings &settings, double) {
    switch (button) {
    case PadButton::a:
        arpeggio_ = arpeggio_ ? std::nullopt : std::optional<ArpeggioRate>(ArpeggioRate::eighth);
        break;
    case PadButton::x: {
        const auto &rates = allArpeggioRates;
        const auto found = std::find(rates.begin(), rates.end(), arpeggio_.value_or(ArpeggioRate::quarter));
        const size_t at = found == rates.end() ? 0 : static_cast<size_t>(found - rates.begin());
        arpeggio_ = rates[(at + 1) % rates.size()];
        break;
    }
    case PadButton::y:
        settings.voiceLeading = !settings.voiceLeading;
        break;
    case PadButton::b:
        holds_ = !holds_;
        if (!holds_ && presses_.empty()) {
            std::vector<DeskEffect> out = line_.release();
            out.push_back(DeskEffect::rumble(Rumble::tick));
            return out;
        }
        break;
    default:
        break;
    }
    return {DeskEffect::rumble(Rumble::tick)};
}

std::vector<DeskEffect> Petals::releaseAll() {
    presses_.clear();
    holds_ = false;
    return line_.release();
}

Petals::Bend Petals::bendOf(const Stick &stick) {
    const auto steps = [](double value, const std::vector<double> &edges) {
        const int count = static_cast<int>(
            std::count_if(edges.begin(), edges.end(), [&](double edge) { return std::abs(value) >= edge; }));
        return value < 0 ? -count : count;
    };
    return Bend{steps(stick.y, {0.6}), steps(stick.x, {0.45, 0.9})};
}

DeskChord Petals::chord(const Petal &petal, const DeskSettings &settings) const {
    const RingPie pie = settings.brightnessRing(degree_);
    const HeptatonicMode mode = pie.mode(shift());
    if (const auto *height = std::get_if<Petal::Height>(&petal.value()))
        return DeskChord(settings.key, degree_, pie.color(RingCell{mode, height->height}));
    const auto &mark = std::get<Petal::Mark>(petal.value());
    const DeskChord triad(settings.key, degree_, pie.color(RingCell{mode, StackHeight::triad}));
    return DeskChord(settings.key, degree_, ChordColor::tones(applied(mark.mark, triad.tones())));
}

// What the screen shows

std::vector<Target> Petals::degreeTargets(const DeskSettings &settings) const {
    return desk::degreeTargets(degree_, line_.isSounding() ? line_.chord() : std::nullopt, settings);
}

std::vector<Target> Petals::petalTargets(const DeskSettings &settings) const {
    const std::optional<PadButton> heard =
        presses_.empty() ? std::nullopt : std::optional<PadButton>(presses_.back().button);
    std::vector<Target> targets;
    for (size_t index = 0; index < diamond.size(); ++index) {
        const PadButton button = diamond[index];
        const Petal petal = isMarking_ ? Petal::mark(marks().at(button)) : Petal::height(heights().at(button));
        const DeskChord chord = this->chord(petal, settings);
        std::string detail;
        if (const auto *height = std::get_if<Petal::Height>(&petal.value()))
            detail = name(button) + " · " + displayName(height->height);
        else
            detail = name(button) + " · " + name(std::get<Petal::Mark>(petal.value()).mark);
        targets.push_back(Target{.bearing = 180 + static_cast<double>(index) * 90,
                                 .name = chord.name(),
                                 .detail = detail,
                                 .fit = chord.fit(settings.key),
                                 .isAimed = heard == button,
                                 .isHidden = !settings.playable(chord)});
    }
    return targets;
}

std::vector<Target> Petals::depthTargets(const DeskSettings &settings) const {
    StackHeight height = StackHeight::seventh;
    if (!presses_.empty())
        if (const auto *held = std::get_if<Petal::Height>(&presses_.back().petal.value())) height = held->height;
    const RingPie pie = settings.brightnessRing(degree_);
    std::vector<Target> targets;
    for (int steps = -3; steps <= 3; ++steps) {
        if (!pie.reaches(steps)) {
            targets.push_back(Target{.bearing = static_cast<double>(steps), .name = "—", .detail = "past the ring"});
            continue;
        }
        const HeptatonicMode mode = pie.mode(steps);
        const DeskChord chord(settings.key, degree_, pie.color(RingCell{mode, height}));
        targets.push_back(Target{.bearing = static_cast<double>(steps),
                                 .name = chord.name(),
                                 .detail = displayName(mode),
                                 .fit = chord.fit(settings.key),
                                 .isAimed = steps == pie.clamped(shift())});
    }
    return targets;
}

Legend Petals::legend(const DeskSettings &settings) const {
    Legend legend = commonLegend(settings, false);
    legend[PadControl::button(PadButton::left)] = "Key a 5th down";
    legend[PadControl::button(PadButton::right)] = "Key a 5th up";
    legend[PadControl::button(PadButton::up)] = "Next scale";
    legend[PadControl::button(PadButton::down)] = "Scale before";
    legend[PadControl::leftStick()] = "Degree · " + numeral(degree_, settings.key);
    legend[PadControl::rightStick()] = "Bend voicing: ↔ inversion, ↕ octave";
    legend[PadControl::button(PadButton::r3)] = "Keep the bend";
    legend[PadControl::leftTrigger()] = "Darker by " + std::to_string(darker_);
    legend[PadControl::rightTrigger()] = "Brighter by " + std::to_string(brighter_);
    legend[PadControl::button(PadButton::l3)] = std::string("Hold ") + (holds_ ? "on" : "off");
    legend[PadControl::button(PadButton::lb)] = "Hold: marks on the buttons";
    legend[PadControl::button(PadButton::rb)] = "Hold: effects on the buttons";
    if (isOnEffects_) {
        legend[PadControl::button(PadButton::a)] = std::string("Arpeggio ") + (arpeggio_ ? "off" : "on");
        legend[PadControl::button(PadButton::x)] = "Arpeggio rate " + (arpeggio_ ? name(*arpeggio_) : std::string());
        legend[PadControl::button(PadButton::y)] =
            std::string("Voice leading ") + (settings.voiceLeading ? "off" : "on");
        legend[PadControl::button(PadButton::b)] = std::string("Hold ") + (holds_ ? "off" : "on");
    } else {
        for (const Target &target : petalTargets(settings)) {
            const PadButton button = diamond[static_cast<size_t>(static_cast<int>((target.bearing - 180) / 90))];
            legend[PadControl::button(button)] = target.name;
        }
    }
    return legend;
}

} // namespace perfecto::desk
