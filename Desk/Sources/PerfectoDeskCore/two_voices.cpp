#include "perfecto/desk/two_voices.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <variant>

namespace perfecto::desk {

using namespace theory;

namespace {

void append(std::vector<DeskEffect> &out, const std::vector<DeskEffect> &more) {
    out.insert(out.end(), more.begin(), more.end());
}

} // namespace

// TwoVoices

std::vector<DeskEffect> TwoVoices::step(const PadInput &input, DeskSettings &settings) {
    std::vector<DeskEffect> out;
    const double time = input.time();

    if (input.pressed(PadButton::b)) {
        drones_ = false;
        append(out, chords_.release());
        append(out, melody_.release());
    }
    if (input.pressed(PadButton::a)) {
        drones_ = !drones_;
        const auto why = settings.consonance.refusal(chord(settings), settings.key);
        if (drones_ && !chords_.isSounding() && why) {
            drones_ = false;
            out.push_back(DeskEffect::refuse(*why));
        } else if (drones_ && !chords_.isSounding()) {
            append(out, chords_.strike(chord(settings), 0.7, settings, time));
        } else if (!drones_ && !swell_.isHeld()) {
            append(out, chords_.release());
        }
    }
    if (input.pressed(PadButton::x)) {
        append(out, chords_.arpeggiate(chords_.arpeggio() ? std::nullopt : std::optional(ArpeggioRate::eighth),
                                       settings, time));
    }
    if (input.pressed(PadButton::y)) chordTonesOnly_ = !chordTonesOnly_;
    if (input.pressed(PadButton::lb)) {
        constexpr std::array<StackHeight, 3> heights = {StackHeight::triad, StackHeight::seventh, StackHeight::ninth};
        const auto found = std::find(heights.begin(), heights.end(), height_);
        const size_t at = found == heights.end() ? 0 : static_cast<size_t>(found - heights.begin());
        height_ = heights[(at + 1) % heights.size()];
        out.push_back(DeskEffect::rumble(Rumble::tick));
    }
    if (input.pressed(PadButton::l3)) height_ = StackHeight::triad;
    if (input.pressed(PadButton::up)) lineOctave_ = std::min(lineOctaves.upperBound, lineOctave_ + 1);
    if (input.pressed(PadButton::down)) lineOctave_ = std::max(lineOctaves.lowerBound, lineOctave_ - 1);
    if (input.pressed(PadButton::left) || input.pressed(PadButton::right)) {
        settings.roll(input.pressed(PadButton::left) ? -1 : 1);
        append(out, chords_.revoice(settings));
    }

    // The left hand: the degree, and LT's swell.
    degreeSector_ = DegreePie::gate().select(input.frame.left, degreeSector_);
    if (degreeSector_ && input.frame.left.radius() >= PieGate::rest) {
        // A degree whose chord the guard will not play is not chosen.
        const Degree chosen = DegreePie::degree(*degreeSector_);
        if (settings.playable(chord(chosen, settings))) degree_ = chosen;
    }
    for (const auto &event : swell_.step(input.frame.leftTrigger, time)) {
        if (std::holds_alternative<TriggerStrike::Strike>(event)) {
            const auto why = settings.consonance.refusal(chord(settings), settings.key);
            if (why && !chords_.isSounding()) {
                out.push_back(DeskEffect::refuse(*why));
            } else if (!chords_.isSounding()) {
                append(out, chords_.strike(chord(settings), 0.15, 0.5, settings, time));
            }
        } else if (const auto *depth = std::get_if<TriggerStrike::Depth>(&event)) {
            append(out, chords_.shape(0.15 + 0.85 * depth->value, 0.5 + 0.5 * depth->value));
        } else {
            if (!drones_) append(out, chords_.release());
        }
    }
    if (settings.playable(chord(settings))) append(out, chords_.change(chord(settings), settings));

    // The right hand: a petal or the bar, and RT's pressure.
    isOnBar_ = input.isDown(PadButton::rb);
    const std::optional<double> pitch =
        isOnBar_ ? std::optional(barPitchOf(input, settings)) : petalPitch(input.frame.right, settings);
    for (const auto &event : pressure_.step(input.frame.rightTrigger, time)) {
        if (const auto *strike = std::get_if<TriggerStrike::Strike>(&event)) {
            if (pitch) {
                const int note = settings.key.noteNearest(*pitch);
                if (const auto why = settings.consonance.refusalOfNote(note, settings.key)) {
                    out.push_back(DeskEffect::refuse(*why));
                    continue;
                }
                append(out, melody_.strike(note, strike->level, settings.lineSound));
                append(out, melody_.glide(*pitch));
            }
        } else if (const auto *depth = std::get_if<TriggerStrike::Depth>(&event)) {
            append(out, melody_.shape(0.25 + 0.75 * depth->value, 0.4 + 0.6 * depth->value));
        } else {
            append(out, melody_.release());
        }
    }
    if (pressure_.isHeld() && pitch) append(out, melody_.glide(*pitch));
    append(out, chords_.tick(settings, time));
    return out;
}

DeskChord TwoVoices::chord(const DeskSettings &settings) const { return chord(degree_, settings); }

DeskChord TwoVoices::chord(Degree degree, const DeskSettings &settings) const {
    return DeskChord(settings.key, degree,
                     height_ == StackHeight::triad ? ChordColor::base() : ChordColor::grid(height_, std::nullopt));
}

std::vector<Target> TwoVoices::degreeTargets(const DeskSettings &settings) const {
    return desk::degreeTargets(degree_, chords_.isSounding() ? chords_.chord() : std::nullopt, settings);
}

int TwoVoices::lineTonic(const DeskSettings &settings) const {
    return (settings.octave + 1 + lineOctave_) * 12 + raw(settings.key.root);
}

std::vector<TwoVoices::Petal> TwoVoices::petals(const DeskSettings &settings) const {
    const std::set<int> chordPitches = chord(settings).pitchClasses();
    std::vector<Petal> petals;
    for (int interval : intervals(settings.key.scale)) {
        const int note = lineTonic(settings) + interval;
        const bool isChordTone = chordPitches.contains(note % 12);
        const bool isAllowed = settings.consonance.allowsNote(note, settings.key);
        petals.push_back(Petal{note, isChordTone, (isChordTone || !chordTonesOnly_) && isAllowed});
    }
    return petals;
}

std::optional<double> TwoVoices::petalPitch(const Stick &stick, const DeskSettings &settings) {
    barPitch_ = std::nullopt;
    const std::vector<Petal> petals = this->petals(settings);
    std::vector<int> reachable;
    for (size_t i = 0; i < petals.size(); ++i)
        if (petals[i].isReachable) reachable.push_back(static_cast<int>(i));
    const double step = 360 / static_cast<double>(petals.size());
    std::vector<double> bearings;
    for (int index : reachable) bearings.push_back(static_cast<double>(index) * step);
    const PieGate gate(std::move(bearings), 180);
    std::optional<int> last;
    if (petal_) {
        const auto found = std::find(reachable.begin(), reachable.end(), *petal_);
        if (found != reachable.end()) last = static_cast<int>(found - reachable.begin());
    }
    const auto chosen = gate.select(stick, last);
    if (!chosen) {
        petal_ = std::nullopt;
        band_ = std::nullopt;
        // A note held stays where it was while the stick comes back.
        return pressure_.isHeld() ? melody_.pitch() : std::nullopt;
    }
    petal_ = reachable[static_cast<size_t>(*chosen)];
    band_ = RadialBands::two().band(stick.radius(), band_);
    return static_cast<double>(petals[static_cast<size_t>(*petal_)].note + 12 * *band_);
}

double TwoVoices::barPitchOf(const PadInput &input, const DeskSettings &settings) {
    petal_ = std::nullopt;
    const double raw = static_cast<double>(lineTonic(settings)) + (input.frame.right.y + 1) / 2 * barSpan;
    if (barPitch_ && std::fabs(raw - *barPitch_) > 0.08) barMoved_ = input.time();
    if (!barPitch_) barMoved_ = input.time();
    barPitch_ = raw;
    // At rest, the bar is in tune: on the key's nearest note.
    return input.time() - barMoved_ >= restTime ? static_cast<double>(settings.key.noteNearest(raw)) : raw;
}

std::vector<DeskEffect> TwoVoices::releaseAll() {
    drones_ = false;
    swell_ = TriggerStrike();
    pressure_ = TriggerStrike();
    std::vector<DeskEffect> out = chords_.release();
    append(out, melody_.release());
    return out;
}

Legend TwoVoices::legend(const DeskSettings &settings) const {
    Legend legend = commonLegend(settings, false);
    legend[PadControl::leftStick()] = "Degree · " + numeral(degree_, settings.key);
    legend[PadControl::leftTrigger()] = "Chord swell";
    legend[PadControl::rightStick()] =
        isOnBar_ ? "The bar: pitch follows, rests in tune" : "Line: the key's notes, outer ring an octave up";
    legend[PadControl::rightTrigger()] = "Line pressure";
    legend[PadControl::button(PadButton::lb)] = "Color: " + displayName(height_);
    legend[PadControl::button(PadButton::rb)] = "Hold: the bar";
    legend[PadControl::button(PadButton::a)] = std::string("Drone ") + (drones_ ? "on" : "off");
    legend[PadControl::button(PadButton::b)] = "Let go";
    legend[PadControl::button(PadButton::x)] = std::string("Arpeggio ") + (chords_.arpeggio() ? "on" : "off");
    legend[PadControl::button(PadButton::y)] = chordTonesOnly_ ? "Chord tones only" : "Every note of the key";
    legend[PadControl::button(PadButton::up)] = "Line octave up";
    legend[PadControl::button(PadButton::down)] = "Line octave down";
    legend[PadControl::button(PadButton::left)] = "Inversion down";
    legend[PadControl::button(PadButton::right)] = "Inversion up";
    legend[PadControl::button(PadButton::l3)] = "Plain triad";
    return legend;
}

// MelodyVoice

std::optional<double> MelodyVoice::pitch() const {
    if (!note_) return std::nullopt;
    return static_cast<double>(*note_) + bend_;
}

std::vector<DeskEffect> MelodyVoice::strike(int note, double level, const std::string &sound) {
    note_ = note;
    level_ = level;
    bend_ = 0;
    return {DeskEffect::sound(Line::melody, {note}, sound, level, brightness_, false)};
}

std::vector<DeskEffect> MelodyVoice::glide(double pitch) {
    if (!note_ || !(std::fabs(pitch - static_cast<double>(*note_) - bend_) > 0.01)) return {};
    bend_ = pitch - static_cast<double>(*note_);
    return {DeskEffect::shape(Line::melody, level_, brightness_, bend_)};
}

std::vector<DeskEffect> MelodyVoice::shape(double level, double brightness) {
    if (!(std::fabs(level - level_) > 0.01 || std::fabs(brightness - brightness_) > 0.01)) return {};
    level_ = level;
    brightness_ = brightness;
    if (!note_) return {};
    return {DeskEffect::shape(Line::melody, level, brightness, bend_)};
}

std::vector<DeskEffect> MelodyVoice::release() {
    if (!note_) return {};
    note_ = std::nullopt;
    bend_ = 0;
    return {DeskEffect::silence(Line::melody)};
}

} // namespace perfecto::desk
