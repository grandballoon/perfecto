#include "perfecto/desk/drums.hpp"

#include <algorithm>
#include <cmath>

namespace perfecto::desk {

namespace {

/// LT in the drum layer: on past halfway, held a little either side of it,
/// as Face Chords reads it.
const TriggerSteps &shiftTrigger() {
    static const TriggerSteps steps{{0.5}};
    return steps;
}

/// How many of the steps given are kept, to say which is sounding: more
/// than the lookahead ever holds.
constexpr size_t givenKept = 4;

/// How hard a pad is struck: a button has no depth.
constexpr double padLevel = 0.9;

void append(std::vector<DrumEffect> &out, const std::vector<DrumEffect> &more) {
    out.insert(out.end(), more.begin(), more.end());
}

/// `effects` with every hit struck in the kit numbered `kit`.
std::vector<DrumEffect> inKit(std::vector<DrumEffect> effects, int kit) {
    for (DrumEffect &effect : effects)
        if (const auto *hit = std::get_if<DrumEffect::Hit>(&effect.value()))
            effect = DrumEffect::hit(hit->drum, hit->level, hit->time, kit);
    return effects;
}

bool isMiddle(PadButton button) { return button == PadButton::back || button == PadButton::start; }

bool isFace(PadButton button) {
    return button == PadButton::a || button == PadButton::b || button == PadButton::x || button == PadButton::y;
}

bool isDpad(PadButton button) {
    return button == PadButton::up || button == PadButton::down || button == PadButton::left ||
           button == PadButton::right;
}

} // namespace

std::string name(Drum drum) {
    switch (drum) {
    case Drum::kick: return "Kick";
    case Drum::snare: return "Snare";
    case Drum::closedHat: return "Closed hat";
    case Drum::openHat: return "Open hat";
    case Drum::clap: return "Clap";
    case Drum::lowTom: return "Low tom";
    case Drum::midTom: return "Mid tom";
    case Drum::highTom: return "High tom";
    }
    return {};
}

int generalMidi(Drum drum) {
    switch (drum) {
    case Drum::kick: return 36;
    case Drum::snare: return 38;
    case Drum::closedHat: return 42;
    case Drum::openHat: return 46;
    case Drum::clap: return 39;
    case Drum::lowTom: return 45;
    case Drum::midTom: return 47;
    case Drum::highTom: return 50;
    }
    return 0;
}

std::vector<Drum> chokes(Drum drum) {
    if (drum == Drum::closedHat) return {Drum::openHat};
    return {};
}

std::vector<DrumEffect> strike(Drum drum, double level, double time, int kit) {
    std::vector<DrumEffect> out;
    for (const Drum choked : chokes(drum)) out.push_back(DrumEffect::choke(choked, time));
    out.push_back(DrumEffect::hit(drum, level, time, kit));
    return out;
}

// MARK: – Patterns

double level(char step) {
    switch (step) {
    case 'o': return 0.4;
    case 'x': return 0.75;
    case 'X': return 1.0;
    default: return 0;
    }
}

std::vector<std::pair<Drum, double>> DrumPattern::at(int step) const {
    const size_t place = static_cast<size_t>((step % steps + steps) % steps);
    std::vector<std::pair<Drum, double>> out;
    for (const auto &[drum, line] : lines)
        if (place < line.size() && level(line[place]) > 0) out.emplace_back(drum, level(line[place]));
    return out;
}

double DrumPattern::lateness(int step) const { return step % 2 != 0 ? (swing - 0.5) * 2 : 0; }

const std::vector<DrumPattern> &drumPatterns() {
    // Each line a bar: the beats fall on the 1st, 5th, 9th and 13th steps.
    static const std::vector<DrumPattern> patterns = {
        {"Backbeat",
         {{Drum::kick,      "X.....x.X.x....."},
          {Drum::snare,     "....X.......X..."},
          {Drum::closedHat, "X.x.X.x.X.x.X.x."}}},
        {"Floor",
         {{Drum::kick,      "X...X...X...X..."},
          {Drum::clap,      "....X.......X..."},
          {Drum::closedHat, "x...x...x...x..."},
          {Drum::openHat,   "..x...x...x...x."}}},
        {"Half time",
         {{Drum::kick,      "X......x..x....."},
          {Drum::snare,     "........X..o...o"},
          {Drum::closedHat, "x.x.x.x.x.x.x.x."}}},
        {"Shuffle",
         {{Drum::kick,      "X.....x.X.....x."},
          {Drum::snare,     "....X.......X..o"},
          {Drum::closedHat, "X.xoX.xoX.xoX.xo"}},
         0.64},
        {"Broken",
         {{Drum::kick,      "X..x..x...X..x.."},
          {Drum::snare,     "....X..o.o..X..."},
          {Drum::closedHat, "x.x.x.x.x.x.x..."},
          {Drum::openHat,   "..............x."}},
         0.55},
        {"Toms",
         {{Drum::kick,      "X.......X......."},
          {Drum::clap,      "....x.......x..."},
          {Drum::lowTom,    "....x..x....x..."},
          {Drum::highTom,   "..x.......x...x."},
          {Drum::closedHat, "o.o.o.o.o.o.o.o."}}},
    };
    return patterns;
}

double sixteenth(double tempo) { return 60.0 / tempo / 4; }

// MARK: – The machine

const DrumPattern &DrumMachine::played() const { return drumPatterns()[static_cast<size_t>(pattern_)]; }

void DrumMachine::choose(int steps) {
    const int count = static_cast<int>(drumPatterns().size());
    pattern_ = ((pattern_ + steps) % count + count) % count;
}

std::vector<DrumEffect> DrumMachine::start(double time, double tempo) {
    isPlaying_ = true;
    next_ = 0;
    nextTime_ = time;
    given_.clear();
    return advance(time, tempo);
}

void DrumMachine::stop() {
    isPlaying_ = false;
    given_.clear();
}

std::vector<DrumEffect> DrumMachine::advance(double time, double tempo) {
    std::vector<DrumEffect> out;
    if (!isPlaying_) return out;
    const DrumPattern &pattern = played();
    const double length = sixteenth(tempo);
    for (;;) {
        const double when = nextTime_ + pattern.lateness(next_) * length;
        if (when >= time + lookahead) break;
        // A step long past (the desk was held up) is skipped, not sounded
        // late in a heap with the rest.
        if (when >= time - lookahead) {
            for (const auto &[drum, level] : pattern.at(next_)) append(out, strike(drum, level, when));
            given_.emplace_back(next_, when);
            if (given_.size() > givenKept) given_.erase(given_.begin());
        }
        next_ = (next_ + 1) % DrumPattern::steps;
        nextTime_ += length;
    }
    return out;
}

std::optional<int> DrumMachine::step(double time) const {
    if (!isPlaying_) return std::nullopt;
    for (auto given = given_.rbegin(); given != given_.rend(); ++given)
        if (given->second <= time) return given->first;
    return std::nullopt;
}

// MARK: – The hands

Drums::Drums(std::vector<std::string> kits) : kits_(kits.empty() ? std::vector<std::string>{"Kit"} : std::move(kits)) {}

std::vector<DrumEffect> Drums::chooseKit(int steps, double time) {
    const int count = static_cast<int>(kits_.size());
    return setKit(((kit_ + steps) % count + count) % count, time);
}

std::vector<DrumEffect> Drums::setKit(int kit, double time) {
    if (kit < 0 || kit >= static_cast<int>(kits_.size()) || kit == kit_) return {};
    kit_ = kit;
    if (machine_.isPlaying()) return {};
    return strike(Drum::kick, padLevel, time, kit_);
}

std::optional<Drum> Drums::pad(PadButton button, bool shifted) {
    switch (button) {
    case PadButton::a: return shifted ? Drum::lowTom : Drum::kick;
    case PadButton::b: return shifted ? Drum::clap : Drum::snare;
    case PadButton::x: return shifted ? Drum::midTom : Drum::closedHat;
    case PadButton::y: return shifted ? Drum::highTom : Drum::openHat;
    default: return std::nullopt;
    }
}

Drums::Step Drums::step(const PadInput &input, bool reachable, DeskSettings &settings) {
    Step out{{}, {}, input.frame};
    const double time = input.time();
    isShifted_ = shiftTrigger().step(input.frame.leftTrigger, isShifted_ ? 1 : 0) == 1;

    // RB and L3 are the drums' wherever they can be played; with RB held,
    // so are the face buttons and the d-pad pressed under it.
    if (reachable) {
        for (const PadButton button : {PadButton::rb, PadButton::l3})
            if (input.pressed(button)) claimed_.insert(button);
        if (isLayered())
            for (const PadButton button : input.edges.pressed)
                if (isFace(button) || isDpad(button) || isMiddle(button)) claimed_.insert(button);
    }
    const auto taken = [&](PadButton button) { return reachable && input.pressed(button) && claimed_.contains(button); };

    if (taken(PadButton::l3)) {
        if (machine_.isPlaying()) machine_.stop();
        else append(out.drums, inKit(machine_.start(time, settings.tempo), kit_));
        out.effects.push_back(DeskEffect::rumble(Rumble::bump));
    }
    if (isLayered() && reachable) {
        for (const PadButton button : input.edges.pressed)
            if (const auto drum = pad(button, isShifted_); drum && taken(button))
                append(out.drums, strike(*drum, padLevel, time, kit_));
        if (taken(PadButton::left) || taken(PadButton::right)) {
            machine_.choose(taken(PadButton::left) ? -1 : 1);
            out.effects.push_back(DeskEffect::rumble(Rumble::tick));
        }
        if (taken(PadButton::back) || taken(PadButton::start)) {
            append(out.drums, chooseKit(taken(PadButton::back) ? -1 : 1, time));
            out.effects.push_back(DeskEffect::rumble(Rumble::tick));
        }
        if (taken(PadButton::up) || taken(PadButton::down)) {
            const double tempo = std::clamp(settings.tempo + (taken(PadButton::up) ? tempoStep : -tempoStep),
                                            DeskSettings::tempos.lowerBound, DeskSettings::tempos.upperBound);
            if (tempo != settings.tempo) {
                settings.tempo = tempo;
                out.effects.push_back(DeskEffect::rumble(Rumble::tick));
            }
        }
    }
    append(out.drums, inKit(machine_.advance(time, settings.tempo), kit_));

    for (const PadButton button : claimed_) out.frame.buttons.erase(button);
    for (const PadButton button : input.edges.released) claimed_.erase(button);
    if (isLayered()) out.frame.leftTrigger = deskTrigger_;
    deskTrigger_ = out.frame.leftTrigger;
    return out;
}

void Drums::stop() { machine_.stop(); }

Legend Drums::legend(Legend legend, bool reachable) const {
    if (!reachable) return legend;
    legend[PadControl::button(PadButton::l3)] =
        machine_.isPlaying() ? "Stop the beat" : "Start the beat · " + machine_.played().name;
    legend[PadControl::button(PadButton::rb)] = "Hold: drum pads";
    if (!isLayered()) return legend;
    for (const PadButton button : {PadButton::a, PadButton::b, PadButton::x, PadButton::y})
        legend[PadControl::button(button)] = name(*pad(button, isShifted_));
    legend[PadControl::leftTrigger()] = isShifted_ ? "Let go: kick, snare, hats" : "Hold: toms, clap";
    legend[PadControl::button(PadButton::left)] = "Pattern before";
    legend[PadControl::button(PadButton::right)] = "Next pattern";
    legend[PadControl::button(PadButton::up)] = "Faster";
    legend[PadControl::button(PadButton::down)] = "Slower";
    legend[PadControl::button(PadButton::back)] = "Kit before";
    legend[PadControl::button(PadButton::start)] = "Next kit";
    return legend;
}

} // namespace perfecto::desk
