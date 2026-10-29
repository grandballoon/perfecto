#include "perfecto/desk/neighbourhood.hpp"

#include "perfecto/desk/ring_pie.hpp"

#include <algorithm>
#include <cmath>
#include <map>
#include <variant>

namespace perfecto::desk {

using namespace theory;

std::string name(Neighbourhood::Lens lens) {
    switch (lens) {
    case Neighbourhood::Lens::color: return "Color";
    case Neighbourhood::Lens::tonnetz: return "Tonnetz";
    case Neighbourhood::Lens::degrees: return "Degrees";
    }
    return {};
}

const PieGate &Neighbourhood::gate() {
    static const PieGate pie = PieGate::even(8);
    return pie;
}

Neighbourhood::Neighbourhood()
    : centre_(Key{PitchClass::C, ScaleType::major}, Degree::I), palette_(8, std::nullopt) {}

namespace {

void append(std::vector<DeskEffect> &out, std::vector<DeskEffect> more) {
    out.insert(out.end(), std::make_move_iterator(more.begin()), std::make_move_iterator(more.end()));
}

} // namespace

std::vector<DeskEffect> Neighbourhood::step(const PadInput &input, DeskSettings &settings) {
    std::vector<DeskEffect> out;
    const double time = input.time();
    if (path_.empty() || (centre_.key != settings.key && path_.size() == 1 && !line_.isSounding())) {
        centre_ = DeskChord(settings.key, Degree::I);
        path_ = {centre_};
        pathIndex_ = 0;
    }

    if (input.pressed(PadButton::b)) append(out, line_.release());
    if (input.pressed(PadButton::a)) {
        if (const auto why = settings.consonance.refusal(centre_, settings.key)) {
            out.push_back(DeskEffect::refuse(*why));
        } else {
            append(out, line_.strike(centre_, swell_, brightness_, settings, time));
        }
    }
    if (input.pressed(PadButton::x)) append(out, move(DeskChord(settings.key, Degree::I), settings, time));
    if (input.pressed(PadButton::lb) || input.pressed(PadButton::rb)) {
        const int count = static_cast<int>(allLenses.size());
        const int at = static_cast<int>(std::find(allLenses.begin(), allLenses.end(), lens_) - allLenses.begin()) +
                       (input.pressed(PadButton::rb) ? 1 : -1);
        lens_ = allLenses[static_cast<size_t>((at % count + count) % count)];
        append(out, endAudition(settings));
        out.push_back(DeskEffect::rumble(Rumble::tick));
    }
    if (input.pressed(PadButton::l3)) {
        const auto free = std::find(palette_.begin(), palette_.end(), std::nullopt);
        if (free != palette_.end()) {
            *free = centre_;
        } else {
            palette_.erase(palette_.begin());
            palette_.push_back(centre_);
        }
        out.push_back(DeskEffect::rumble(Rumble::tick));
    }
    if (voicingPad(input, settings)) append(out, line_.revoice(settings));

    // The left stick walks back and forward along the path.
    const Stick left = input.frame.left;
    if (left.radius() < 0.3) pathArmed_ = true;
    if (pathArmed_ && std::abs(left.x) > 0.7 && std::abs(left.x) > std::abs(left.y)) {
        pathArmed_ = false;
        const int next = pathIndex_ + (left.x > 0 ? 1 : -1);
        const bool onPath = 0 <= next && next < static_cast<int>(path_.size());
        if (onPath) {
            if (const auto why = settings.consonance.refusal(path_[static_cast<size_t>(next)], settings.key)) {
                out.push_back(DeskEffect::refuse(*why));
            } else {
                pathIndex_ = next;
                centre_ = path_[static_cast<size_t>(next)];
                append(out, line_.strike(centre_, swell_, brightness_, settings, time));
                out.push_back(DeskEffect::rumble(Rumble::bump));
            }
        }
    }

    // The right stick: a neighbour, or with Y held a bookmark.
    if (input.pressed(PadButton::y) || input.released(PadButton::y)) append(out, endAudition(settings));
    isOnPalette_ = input.isDown(PadButton::y);
    // What the guard will not play cannot be reached.
    std::vector<std::optional<DeskChord>> targets;
    if (isOnPalette_) {
        targets = palette_;
    } else {
        for (const auto &neighbour : neighbours(settings))
            targets.push_back(neighbour ? std::optional<DeskChord>(neighbour->chord) : std::nullopt);
    }
    for (auto &target : targets)
        if (target && !settings.playable(*target)) target = std::nullopt;
    for (const StickGesture::Event &event : gesture_.step(input.frame.right, gate(), time)) {
        if (const auto *aim = std::get_if<StickGesture::Aim>(&event)) {
            append(out, endAudition(settings));
            const auto &chord = targets[static_cast<size_t>(aim->target)];
            if (!chord) continue;
            wasSounding_ = line_.isSounding();
            audition_ = aim->target;
            append(out, line_.isSounding() ? line_.change(*chord, settings)
                                           : line_.strike(*chord, swell_, brightness_, settings, time));
        } else if (const auto *flick = std::get_if<StickGesture::Flick>(&event)) {
            audition_ = std::nullopt;
            const auto &chord = targets[static_cast<size_t>(flick->target)];
            if (!chord) continue;
            append(out, move(*chord, settings, time));
        } else {
            append(out, endAudition(settings));
        }
    }
    if (input.pressed(PadButton::r3) && audition_) {
        if (const auto &chord = targets[static_cast<size_t>(*audition_)]) {
            audition_ = std::nullopt;
            append(out, move(*chord, settings, time));
        }
    }

    // The triggers: RT swells, LT darkens.
    const double level = input.frame.rightTrigger > 0.04 ? 0.2 + 0.8 * input.frame.rightTrigger : 0.8;
    const double dark = 1 - 0.75 * input.frame.leftTrigger;
    swell_ = level;
    brightness_ = dark;
    append(out, line_.shape(level, dark));
    append(out, line_.tick(settings, time));
    return out;
}

std::vector<DeskEffect> Neighbourhood::move(const DeskChord &chord, const DeskSettings &settings, double time) {
    if (const auto why = settings.consonance.refusal(chord, settings.key)) return {DeskEffect::refuse(*why)};
    centre_ = chord;
    path_.erase(path_.begin() + static_cast<std::ptrdiff_t>(std::min(path_.size(), static_cast<size_t>(pathIndex_ + 1))),
                path_.end());
    path_.push_back(chord);
    pathIndex_ = static_cast<int>(path_.size()) - 1;
    std::vector<DeskEffect> out = line_.strike(chord, swell_, brightness_, settings, time);
    out.push_back(DeskEffect::rumble(Rumble::bump));
    return out;
}

std::vector<DeskEffect> Neighbourhood::endAudition(const DeskSettings &settings) {
    if (!audition_) return {};
    audition_ = std::nullopt;
    return wasSounding_ ? line_.change(centre_, settings) : line_.release();
}

std::vector<DeskEffect> Neighbourhood::releaseAll() {
    gesture_.reset();
    audition_ = std::nullopt;
    return line_.release();
}

// The lenses

std::vector<std::optional<Neighbourhood::Neighbour>> Neighbourhood::neighbours(const DeskSettings &settings) const {
    std::vector<std::optional<Neighbour>> out;
    switch (lens_) {
    case Lens::color:
        for (size_t index = 0; index < CompassPie::places().size(); ++index) {
            const int at = static_cast<int>(index);
            if (const auto chord = CompassPie::chord(at, centre_, settings.ranking))
                out.push_back(Neighbour{*chord, CompassPie::edit(at, centre_, settings.ranking).value_or("")});
            else
                out.push_back(std::nullopt);
        }
        break;
    case Lens::tonnetz: {
        const Triad triad(centre_);
        for (Triad::Move move : Triad::allMoves) {
            const Triad next = triad.applying(move);
            out.push_back(Neighbour{DeskChord::onRoot(next.root, next.tones(), settings.key), name(move)});
        }
        break;
    }
    case Lens::degrees: {
        const Key home = settings.key;
        const Degree degree =
            centre_.key == home ? centre_.spec.degree : home.degreeOf(centre_.root()).value_or(Degree::I);
        const std::array<std::optional<int>, 8> around = {std::nullopt, 2, 1, 3, std::nullopt, -3, -1, -2};
        static const std::map<int, std::string> names = {{2, "5th up"},    {1, "3rd up"},    {3, "6th up"},
                                                         {-3, "6th down"}, {-1, "3rd down"}, {-2, "5th down"}};
        for (const auto &steps : around) {
            if (steps)
                out.push_back(Neighbour{DeskChord(home, DiatonicCycle::degree(*steps, degree)), names.at(*steps)});
            else
                out.push_back(std::nullopt);
        }
        break;
    }
    }
    return out;
}

// What the screen shows

std::vector<std::optional<Target>> Neighbourhood::neighbourTargets(const DeskSettings &settings) const {
    std::vector<std::optional<Target>> out;
    if (isOnPalette_) {
        for (size_t index = 0; index < palette_.size(); ++index) {
            const auto &chord = palette_[index];
            if (!chord) {
                out.push_back(std::nullopt);
                continue;
            }
            out.push_back(Target{.bearing = gate().bearings[index],
                                 .name = chord->name(),
                                 .detail = "bookmark " + std::to_string(index + 1),
                                 .fit = chord->fit(settings.key),
                                 .isAimed = audition_ == static_cast<int>(index),
                                 .isHidden = !settings.playable(*chord)});
        }
        return out;
    }
    const auto neighbours = this->neighbours(settings);
    for (size_t index = 0; index < neighbours.size(); ++index) {
        const auto &neighbour = neighbours[index];
        if (!neighbour) {
            out.push_back(std::nullopt);
            continue;
        }
        out.push_back(Target{.bearing = gate().bearings[index],
                             .name = neighbour->chord.name(),
                             .detail = neighbour->move,
                             .fit = neighbour->chord.fit(settings.key),
                             .isAimed = audition_ == static_cast<int>(index),
                             .isHidden = !settings.playable(neighbour->chord)});
    }
    return out;
}

std::string Neighbourhood::centreDetail(const DeskSettings &settings) const {
    if (centre_.key == settings.key) return numeral(centre_.spec.degree, settings.key);
    if (const auto degree = settings.key.degreeOf(centre_.root());
        degree && centre_.fit(settings.key) != ChordFit::borrowed)
        return numeral(*degree, settings.key);
    return "borrowed";
}

Legend Neighbourhood::legend(const DeskSettings &settings) const {
    Legend legend = commonLegend(settings);
    legend[PadControl::rightStick()] = isOnPalette_ ? "Bookmarks: flick jumps, hold listens"
                                                    : name(lens_) + " lens: flick moves, hold listens";
    legend[PadControl::leftStick()] = "← → back and forward along the path";
    legend[PadControl::rightTrigger()] = "Swell";
    legend[PadControl::leftTrigger()] = "Darker";
    legend[PadControl::button(PadButton::a)] = "Strike the centre";
    legend[PadControl::button(PadButton::b)] = "Let go";
    legend[PadControl::button(PadButton::x)] = "Home: I";
    legend[PadControl::button(PadButton::y)] = "Hold: bookmarks";
    legend[PadControl::button(PadButton::lb)] = "Lens before";
    legend[PadControl::button(PadButton::rb)] = "Next lens";
    legend[PadControl::button(PadButton::l3)] = "Bookmark the centre";
    legend[PadControl::button(PadButton::r3)] = "Move to the chord listened to";
    return legend;
}

// Triad

Triad::Triad(const DeskChord &chord) : Triad(chord.root(), chord.tones().has(4) || !chord.tones().has(3)) {}

ChordTones Triad::tones() const { return ChordTones(isMajor ? std::vector<int>{0, 4, 7} : std::vector<int>{0, 3, 7}); }

std::string name(Triad::Move move) {
    switch (move) {
    case Triad::Move::parallel: return "P · parallel";
    case Triad::Move::relative: return "R · relative";
    case Triad::Move::dominant: return "a 5th up";
    case Triad::Move::hexatonicUp: return "PR";
    case Triad::Move::nebenverwandt: return "N";
    case Triad::Move::hexatonicDown: return "PL";
    case Triad::Move::subdominant: return "a 5th down";
    case Triad::Move::leadingTone: return "L · leading tone";
    }
    return {};
}

Triad Triad::moved(int semitones, bool major) const {
    return Triad(pitchClass((raw(root) + semitones + 12) % 12), major);
}

Triad Triad::applying(Move move) const {
    switch (move) {
    case Move::parallel: return p();
    case Move::relative: return r();
    case Move::leadingTone: return l();
    case Move::dominant: return moved(7, isMajor);
    case Move::subdominant: return moved(5, isMajor);
    case Move::hexatonicUp: return p().r();
    case Move::hexatonicDown: return p().l();
    case Move::nebenverwandt: return r().l().p();
    }
    return *this;
}

} // namespace perfecto::desk
