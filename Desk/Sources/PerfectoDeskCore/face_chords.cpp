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

std::optional<std::pair<PadButton, Degree>> FaceChords::heard() const {
    if (!line_.isSounding() || !struck_) return std::nullopt;
    return std::pair(struck_->button, struck_->degree);
}

std::optional<FaceChords::Wanted> FaceChords::wanted() const {
    for (auto press = held_.rbegin(); press != held_.rend(); ++press)
        if (const auto degree = map_.degree(*press, isLayered_)) return Wanted{*press, *degree};
    return std::nullopt;
}

std::vector<DeskEffect> FaceChords::step(const PadInput &input, DeskSettings &settings) {
    std::vector<DeskEffect> out;
    if (voicingPad(input, settings)) append(out, line_.revoice(settings));

    const bool layered = layerTrigger().step(input.frame.leftTrigger, isLayered_ ? 1 : 0) == 1;
    if (layered != isLayered_) out.push_back(DeskEffect::rumble(Rumble::tick));
    isLayered_ = layered;

    for (const PadButton button : faces) {
        if (input.pressed(button)) held_.push_back(button);
        if (input.released(button)) std::erase(held_, button);
    }

    // What sounds is what the hands ask for now: a new press, a press let go
    // and LT pulled or let go are each a change of chord, and nothing held
    // is silence.
    const auto next = wanted();
    if (next != struck_) {
        struck_ = next;
        if (next) {
            const DeskChord chord(settings.key, next->degree);
            if (const auto why = settings.consonance.refusal(chord, settings.key)) {
                out.push_back(DeskEffect::refuse(*why));
                append(out, line_.release());
            } else {
                append(out, line_.strike(chord, 0.8, settings, input.time()));
            }
        } else {
            append(out, line_.release());
        }
    }
    return out;
}

std::vector<DeskEffect> FaceChords::releaseAll() {
    held_.clear();
    struck_.reset();
    return line_.release();
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
    legend[PadControl::leftTrigger()] = isLayered_ ? "Let go: " + other : "Hold: " + other;
    return legend;
}

} // namespace perfecto::desk
