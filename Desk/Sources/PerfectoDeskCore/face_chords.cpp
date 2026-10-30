#include "perfecto/desk/face_chords.hpp"

#include "perfecto/desk/gates.hpp"

#include <algorithm>

namespace perfecto::desk {

using namespace theory;

namespace {

/// LT as a switch: on past halfway, held a little either side of it.
const TriggerSteps &layerTrigger() {
    static const TriggerSteps steps{{0.5}};
    return steps;
}

void append(std::vector<DeskEffect> &out, std::vector<DeskEffect> more) {
    out.insert(out.end(), std::make_move_iterator(more.begin()), std::make_move_iterator(more.end()));
}

} // namespace

const FaceChords::Map &FaceChords::Map::standard() {
    static const Map map = {
        {{PadButton::a, Degree::I}, {PadButton::b, Degree::IV}, {PadButton::x, Degree::V}, {PadButton::y, Degree::viiDim}},
        {{PadButton::a, Degree::I}, {PadButton::b, Degree::ii}, {PadButton::x, Degree::iii}, {PadButton::y, Degree::vi}},
    };
    return map;
}

std::optional<Degree> FaceChords::Map::degree(PadButton button, bool isLayered) const {
    const auto &layer = isLayered ? layered : plain;
    const auto found = layer.find(button);
    return found == layer.end() ? std::nullopt : std::optional<Degree>(found->second);
}

double FaceChords::bearing(PadButton button) {
    switch (button) {
    case PadButton::a: return 180;
    case PadButton::x: return 270;
    case PadButton::y: return 0;
    case PadButton::b: return 90;
    default: return 0;
    }
}

FaceChords::FaceChords(Map map)
    : map_(std::move(map)), voices_{Voice{{}, std::nullopt, ChordLine(Line::chord)},
                                    Voice{{}, std::nullopt, ChordLine(Line::melody)}} {}

std::optional<std::pair<PadButton, Degree>> FaceChords::Voice::heard() const {
    if (!line.isSounding()) return std::nullopt;
    return struck;
}

std::optional<std::pair<PadButton, Degree>> FaceChords::wanted(size_t voice) const {
    const auto &held = voices_[voice].held;
    for (auto press = held.rbegin(); press != held.rend(); ++press)
        if (const auto degree = map_.degree(*press, isLayered(voice))) return std::pair(*press, *degree);
    return std::nullopt;
}

std::vector<size_t> FaceChords::route(const PadInput &input) const {
    if (!hasSecond_) return {0};
    if (input.isDown(PadButton::lb)) return {1};
    if (!isTogether_) return {0};
    if (strikesWithLT(input)) return {1};
    return {0, 1};
}

bool FaceChords::strikesWithLT(const PadInput &input) const {
    return isTogether_ && isLayered_ && input.time() - layeredAt_ <= together;
}

std::vector<DeskEffect> FaceChords::settle(size_t voice, const DeskSettings &settings, double time) {
    // What sounds is what the hands ask for now: a new press, a press let go
    // and LT pulled or let go are each a change of chord, and nothing held
    // is silence.
    // A new color on the chord sounding is heard tied, as a change.
    Voice &v = voices_[voice];
    const auto next = wanted(voice);
    const auto found = next ? colors_.find(next->second) : colors_.end();
    const ChordColor color = found == colors_.end() ? ChordColor::base() : found->second;
    if (next == v.struck && (!next || color == v.color)) return {};
    const bool recolors = next && next == v.struck && v.line.isSounding();
    v.struck = next;
    v.color = color;
    if (!next) return v.line.release();
    const DeskChord chord(settings.key, next->second, color);
    if (const auto why = settings.consonance.refusal(chord, settings.key)) {
        std::vector<DeskEffect> out = {DeskEffect::refuse(*why)};
        append(out, v.line.release());
        return out;
    }
    if (recolors) return v.line.change(chord, settings);
    return v.line.strike(chord, 0.8, settings, time);
}

std::vector<DeskEffect> FaceChords::takeAwaySecond() {
    hasSecond_ = false;
    isTogether_ = false;
    isOverPull_ = false;
    lbPressedAt_.reset();
    latePresses_.clear();
    Voice &second = voices_[1];
    second.held.clear();
    second.struck.reset();
    return second.line.release();
}

std::vector<DeskEffect> FaceChords::step(const PadInput &input, DeskSettings &settings) {
    std::vector<DeskEffect> out;
    const double time = input.time();
    if (voicingPad(input, settings))
        for (Voice &voice : voices_) append(out, voice.line.revoice(settings));

    if (input.pressed(PadButton::r3)) {
        if (hasSecond_) {
            append(out, takeAwaySecond());
        } else {
            hasSecond_ = true;
            append(out, voices_[1].line.bend(overOctaves, 0, settings));
        }
        out.push_back(DeskEffect::rumble(Rumble::bump));
    }
    if (hasSecond_ && input.pressed(PadButton::lb)) {
        if (lbPressedAt_ && time - *lbPressedAt_ <= doubleClick) {
            isTogether_ = !isTogether_;
            lbPressedAt_.reset();
            out.push_back(DeskEffect::rumble(Rumble::bump));
        } else {
            lbPressedAt_ = time;
        }
    }

    const bool layered = layerTrigger().step(input.frame.leftTrigger, isLayered_ ? 1 : 0) == 1;
    if (layered != isLayered_) out.push_back(DeskEffect::rumble(Rumble::tick));
    if (layered && !isLayered_) {
        layeredAt_ = time;
        // LT just after a face button, with both voices on: they were struck
        // together, so the pull and the press are the second voice's alone.
        for (const Press &press : latePresses_) {
            if (!isTogether_ || time - press.time > together) continue;
            std::erase(voices_[0].held, press.button);
            isOverPull_ = true;
        }
    }
    if (!layered) isOverPull_ = false;
    isLayered_ = layered;
    std::erase_if(latePresses_, [&](const Press &press) { return time - press.time > together; });

    for (const PadButton button : faces) {
        if (input.pressed(button)) {
            for (const size_t voice : route(input)) voices_[voice].held.push_back(button);
            if (strikesWithLT(input)) isOverPull_ = true;
            else latePresses_.push_back({button, time});
        }
        if (input.released(button)) {
            for (Voice &voice : voices_) std::erase(voice.held, button);
            std::erase_if(latePresses_, [&](const Press &press) { return press.button == button; });
        }
    }

    for (size_t voice = 0; voice < voices_.size(); ++voice) append(out, settle(voice, settings, time));
    return out;
}

std::vector<DeskEffect> FaceChords::releaseAll() {
    std::vector<DeskEffect> out;
    for (Voice &voice : voices_) {
        voice.held.clear();
        voice.struck.reset();
        append(out, voice.line.release());
    }
    isOverPull_ = false;
    lbPressedAt_.reset();
    latePresses_.clear();
    return out;
}

Legend FaceChords::legend(const DeskSettings &settings) const {
    Legend legend = commonLegend(settings);
    for (const PadButton button : faces)
        if (const auto degree = map_.degree(button, isLayered_))
            legend[PadControl::button(button)] = numeral(*degree, settings.key) + " · " + DeskChord(settings.key, *degree).name();
    // The chords the other layer brings, in the key's order.
    std::vector<Degree> others;
    for (const PadButton button : faces) {
        const auto mine = map_.degree(button, isLayered_), theirs = map_.degree(button, !isLayered_);
        if (theirs && mine != theirs) others.push_back(*theirs);
    }
    std::sort(others.begin(), others.end());
    others.erase(std::unique(others.begin(), others.end()), others.end());
    std::string other;
    for (const Degree degree : others) other += (other.empty() ? "" : " ") + numeral(degree, settings.key);
    legend[PadControl::leftTrigger()] =
        (isLayered_ ? "Let go: " + other : "Hold: " + other) + (isTogether_ ? " · with a face: voice 2" : "");
    legend[PadControl::button(PadButton::r3)] = hasSecond_ ? "Take away voice 2" : "Add a second voice";
    if (hasSecond_)
        legend[PadControl::button(PadButton::lb)] =
            isTogether_ ? "Hold: voice 2 over · double-click: voice 1" : "Hold: voice 2 · double-click: both";
    return legend;
}

} // namespace perfecto::desk
