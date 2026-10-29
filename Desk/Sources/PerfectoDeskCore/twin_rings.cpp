#include "perfecto/desk/twin_rings.hpp"

#include <perfecto/theory/modes.hpp>

#include <array>
#include <string>
#include <utility>
#include <variant>

namespace perfecto::desk {

using namespace theory;

namespace {

void append(std::vector<DeskEffect> &out, const std::vector<DeskEffect> &effects) {
    out.insert(out.end(), effects.begin(), effects.end());
}

/// Swift's `ArpeggioRate(rawValue:)`: 1 to 3 a rate, anything else none.
std::optional<ArpeggioRate> arpeggioRate(int raw) {
    for (ArpeggioRate rate : allArpeggioRates)
        if (static_cast<int>(rate) == raw) return rate;
    return std::nullopt;
}

/// The consonant chord `move` makes from `chord`'s notes, if there is one.
/// (Swift's internal `VoiceMove.chord(from:_:bass:)`, which only this file uses.)
std::optional<DeskChord> chordFrom(const VoiceMove &move, const DeskChord &chord, const DeskSettings &settings,
                                   bool bass) {
    const std::vector<int> notes = chord.notes(settings);
    const auto next = bass ? VoiceLeading::bassNeighbour(notes, move, settings.key)
                           : VoiceLeading::neighbour(notes, move, settings.key);
    if (!next || !settings.playable(*next)) return std::nullopt;
    return next;
}

} // namespace

const PieGate &TwinRings::favoritesGate() {
    static const PieGate gate = PieGate::even(Favorites::perChord);
    return gate;
}

std::vector<DeskEffect> TwinRings::step(const PadInput &input, DeskSettings &settings) {
    std::vector<DeskEffect> out;
    const double time = input.time();

    if (input.pressed(PadButton::b)) {
        holds_ = false;
        append(out, line_.release());
    }
    // Y: a tap holds; held, it is the favorites' layer.
    if (input.pressed(PadButton::y)) {
        y_.press(time);
        ring_.reset();
        aim_ = std::nullopt;
    }
    if (input.released(PadButton::y)) {
        favorites_.reset();
        favoriteAim_ = std::nullopt;
        if (y_.release(time)) {
            holds_ = !holds_;
            if (!holds_ && !strike_.isHeld() && !input.isDown(PadButton::a)) append(out, line_.release());
        }
    }
    isOnFavorites_ = input.isDown(PadButton::y);
    if (input.pressed(PadButton::x)) {
        if (isOnFavorites_) {
            y_.use();
            if (favoriteAim_) {
                settings.favorites.unpin(settings.key, degree_, *favoriteAim_);
                if (keptFavorite_ == favoriteAim_) keptFavorite_ = std::nullopt;
                favoriteAim_ = std::nullopt;
                out.push_back(DeskEffect::rumble(Rumble::bump));
            }
        } else {
            settings.voiceLeading = !settings.voiceLeading;
        }
    }
    // R3 with the stick at rest, the middle: the voices' walk taken back
    // first, then a step of the compass, then the color, to the plain chord.
    if (input.pressed(PadButton::r3) && !aim_ && !compassAim_ && !favoriteAim_ && !voiceAim_ && !bassAim_ &&
        resetsTo(settings)) {
        if (walked_) {
            walked_ = std::nullopt;
        } else if (keptStep_) {
            keptStep_ = std::nullopt;
        } else {
            kept_ = std::nullopt;
            keptFavorite_ = std::nullopt;
        }
        out.push_back(DeskEffect::rumble(Rumble::tick));
    }
    // L3: with the LB layer on, compass or voices; otherwise the ring's arrangement.
    if (input.pressed(PadButton::l3)) {
        if (isOnCompass_) {
            settings.lbLayer = settings.lbLayer == LBLayer::compass ? LBLayer::voices : LBLayer::compass;
            compass_.reset();
            compassAim_ = std::nullopt;
            letGoOfVoices();
        } else {
            settings.moveRingArrangement(1);
        }
        out.push_back(DeskEffect::rumble(Rumble::tick));
    }
    const bool revoiced = voicingPad(input, settings);

    // The bumpers: a tap moves the key a fifth, a hold is a layer. LB
    // held long turns the compass on to stay, or off again.
    if (input.pressed(PadButton::lb)) {
        lb_.press(time);
        lbHeldSince_ = time;
        ring_.reset();
        aim_ = std::nullopt;
    }
    if (lbHeldSince_ && input.isDown(PadButton::lb) && time - *lbHeldSince_ >= TapOrHold::tapTime) {
        lbHeldSince_ = std::nullopt;
        lb_.use();
        compassLatched_ = !compassLatched_;
        out.push_back(DeskEffect::rumble(Rumble::bump));
    }
    if (input.released(PadButton::lb)) {
        lbHeldSince_ = std::nullopt;
        if (!compassLatched_) {
            compass_.reset();
            compassAim_ = std::nullopt;
            letGoOfVoices();
        }
        if (lb_.release(time)) {
            settings.moveKey(-1);
            out.push_back(DeskEffect::rumble(Rumble::bump));
        }
    }
    if (input.pressed(PadButton::rb)) rb_.press(time);
    if (input.released(PadButton::rb) && rb_.release(time)) {
        settings.moveKey(1);
        out.push_back(DeskEffect::rumble(Rumble::bump));
    }
    isOnCompass_ = input.isDown(PadButton::lb) || compassLatched_;
    isOnVoices_ = isOnCompass_ && settings.lbLayer == LBLayer::voices;
    isExtended_ = input.isDown(PadButton::rb);

    // The left stick: the degree, kept when the stick comes back; with
    // the voices on, the bass.
    if (isOnVoices_) {
        append(out, stepBass(input, settings));
    } else {
        degreeSector_ = DegreePie::gate().select(input.frame.left, degreeSector_);
        if (degreeSector_ && input.frame.left.radius() >= PieGate::rest) {
            const Degree chosen = DegreePie::degree(*degreeSector_);
            // A degree whose chord the guard will not play is not chosen.
            if (chosen != degree_ && allows(
                                         [&](TwinRings &changed) {
                                             changed.degree_ = chosen;
                                             changed.walked_ = std::nullopt;
                                         },
                                         settings)) {
                walked_ = std::nullopt;
                degree_ = chosen;
            }
        }
    }

    // The right stick: the ring, with LB the compass, with Y the favorites.
    if (isOnFavorites_) {
        const int count = static_cast<int>(settings.favorites.colors(settings.key, degree_).size());
        for (const auto &event : favorites_.step(input.frame.right, favoritesGate(), time)) {
            y_.use();
            if (const auto *aim = std::get_if<StickGesture::Aim>(&event)) {
                const int index = aim->target;
                favoriteAim_ =
                    index < count && allows([&](TwinRings &changed) { changed.favoriteAim_ = index; }, settings)
                        ? std::optional<int>(index)
                        : std::nullopt;
            } else if (const auto *flick = std::get_if<StickGesture::Flick>(&event)) {
                const int index = flick->target;
                if (!(index < count && allows([&](TwinRings &changed) { changed.favoriteAim_ = index; }, settings)))
                    continue;
                keptFavorite_ = keptFavorite_ == index ? std::nullopt : std::optional<int>(index);
                favoriteAim_ = std::nullopt;
                out.push_back(DeskEffect::rumble(Rumble::bump));
            } else {
                favoriteAim_ = std::nullopt;
            }
        }
        if (input.pressed(PadButton::r3) && favoriteAim_) keptFavorite_ = favoriteAim_;
    } else if (isOnVoices_) {
        append(out, stepVoices(input, settings));
    } else if (isOnCompass_) {
        for (const auto &event : compass_.step(input.frame.right, CompassPie::gate(), time)) {
            lb_.use();
            if (const auto *aim = std::get_if<StickGesture::Aim>(&event)) {
                const int place = aim->target;
                compassAim_ = allows([&](TwinRings &changed) { changed.compassAim_ = place; }, settings)
                                  ? std::optional<int>(place)
                                  : std::nullopt;
            } else if (const auto *flick = std::get_if<StickGesture::Flick>(&event)) {
                const int place = flick->target;
                if (!allows([&](TwinRings &changed) { changed.compassAim_ = place; }, settings)) continue;
                keptStep_ = keptStep_ == place ? std::nullopt : std::optional<int>(place);
                compassAim_ = std::nullopt;
                out.push_back(DeskEffect::rumble(Rumble::bump));
            } else {
                compassAim_ = std::nullopt;
            }
        }
        if (input.pressed(PadButton::r3) && compassAim_) keptStep_ = compassAim_;
    } else {
        const RingPie pie = settings.ring(degree_, struck_);
        const RingPie::Gate gate = pie.gate(isExtended_);
        const std::vector<int> &reachable = gate.sectors;
        for (const auto &event : ring_.step(input.frame.right, gate.gate, time)) {
            if (std::holds_alternative<StickGesture::Flick>(event)) {
                kept_ = aim_;
                out.push_back(DeskEffect::rumble(Rumble::bump));
            }
        }
        const auto target = ring_.target();
        if (target && *target >= 0 && *target < static_cast<int>(reachable.size())) {
            if (isExtended_) rb_.use();
            const int next = RadialBands::three().band(input.frame.right.radius(), band_);
            if (band_ && next != *band_) out.push_back(DeskEffect::rumble(Rumble::tick));
            band_ = next;
            aim_ = pie.cell(reachable[static_cast<size_t>(*target)], next, isExtended_);
            if (input.pressed(PadButton::r3)) kept_ = aim_;
        } else {
            band_ = std::nullopt;
            aim_ = std::nullopt;
        }
    }

    // Striking: RT with a level, A at a fixed one.
    for (const auto &event : strike_.step(input.frame.rightTrigger, time)) {
        if (const auto *strike = std::get_if<TriggerStrike::Strike>(&event)) {
            if (const auto why = settings.consonance.refusal(chord(settings), settings.key)) {
                out.push_back(DeskEffect::refuse(*why));
                continue;
            }
            struckLevel_ = strike->level;
            struck_ = chord(settings);
            append(out, line_.strike(*struck_, strike->level, 1, settings, time));
        } else if (const auto *depth = std::get_if<TriggerStrike::Depth>(&event)) {
            append(out, line_.shape(struckLevel_ * (0.6 + 0.4 * depth->value), 0.55 + 0.45 * depth->value));
        } else {
            if (!holds_ && !input.isDown(PadButton::a)) append(out, line_.release());
        }
    }
    if (input.pressed(PadButton::a)) {
        if (isOnFavorites_) {
            // Y + A pins the chord the hands are on.
            y_.use();
            out.push_back(
                DeskEffect::rumble(settings.favorites.pin(chord(settings), settings.key) ? Rumble::bump : Rumble::tick));
        } else if (const auto why = settings.consonance.refusal(chord(settings), settings.key)) {
            out.push_back(DeskEffect::refuse(*why));
        } else {
            struck_ = chord(settings);
            append(out, line_.strike(*struck_, 0.8, settings, time));
        }
    }
    if (input.released(PadButton::a) && !holds_ && !strike_.isHeld()) append(out, line_.release());

    // What sounds follows the hands, as far as the guard lets it.
    if (settings.playable(chord(settings))) append(out, line_.change(chord(settings), settings));
    if (revoiced) append(out, line_.revoice(settings));

    // LT: the arpeggio, off and then faster as it is pulled.
    const int next = TriggerSteps::three().step(input.frame.leftTrigger, arpeggioStep_);
    if (next != arpeggioStep_) {
        arpeggioStep_ = next;
        out.push_back(DeskEffect::rumble(Rumble::tick));
        append(out, line_.arpeggiate(arpeggioRate(next), settings, time));
    }
    append(out, line_.tick(settings, time));
    return out;
}

std::vector<DeskEffect> TwinRings::releaseAll() {
    letGoOfVoices();
    holds_ = false;
    lbHeldSince_ = std::nullopt;
    ring_.reset();
    compass_.reset();
    aim_ = std::nullopt;
    compassAim_ = std::nullopt;
    strike_ = TriggerStrike();
    return line_.release();
}

DeskChord TwinRings::chord(const DeskSettings &settings) const {
    const DeskChord from = voiced(settings);
    if (voiceAim_)
        if (auto moved = VoiceLeading::neighbour(from.notes(settings), *voiceAim_, settings.key)) return *moved;
    if (bassAim_)
        if (auto moved = VoiceLeading::bassNeighbour(from.notes(settings), *bassAim_, settings.key)) return *moved;
    return from;
}

DeskChord TwinRings::voiced(const DeskSettings &settings) const {
    if (walked_) return *walked_;
    return colored(settings);
}

DeskChord TwinRings::colored(const DeskSettings &settings) const {
    // A favorite, or else the ring's cell, and the compass's step from it.
    const std::vector<ChordColor> pinned = settings.favorites.colors(settings.key, degree_);
    const std::optional<int> favorite = favoriteAim_ ? favoriteAim_ : keptFavorite_;
    const std::optional<RingCell> cell = aim_ ? aim_ : kept_;
    ChordColor color = ChordColor::base();
    if (favorite && *favorite >= 0 && *favorite < static_cast<int>(pinned.size())) {
        color = pinned[static_cast<size_t>(*favorite)];
    } else if (cell) {
        color = settings.ring(degree_).color(*cell);
    }
    const DeskChord base(settings.key, degree_, color);
    const std::optional<int> place = compassAim_ ? compassAim_ : keptStep_;
    if (!place) return base;
    return CompassPie::chord(*place, base, settings.ranking).value_or(base);
}

// What the screen shows

std::optional<DeskChord> TwinRings::resetsTo(const DeskSettings &settings) const {
    TwinRings back = *this;
    back.compassAim_ = std::nullopt;
    back.favoriteAim_ = std::nullopt;
    back.aim_ = std::nullopt;
    back.voiceAim_ = std::nullopt;
    back.bassAim_ = std::nullopt;
    if (back.walked_) {
        back.walked_ = std::nullopt;
    } else if (back.keptStep_) {
        back.keptStep_ = std::nullopt;
    } else if (back.kept_ || back.keptFavorite_) {
        back.kept_ = std::nullopt;
        back.keptFavorite_ = std::nullopt;
    } else {
        return std::nullopt;
    }
    return back.chord(settings);
}

// The voices

std::vector<DeskEffect> TwinRings::stepVoices(const PadInput &input, const DeskSettings &settings) {
    std::vector<DeskEffect> out;
    for (const auto &event : voices_.step(input.frame.right, VoiceLeading::gate(), input.time())) {
        lb_.use();
        if (std::holds_alternative<StickGesture::Flick>(event) && voiceAim_) {
            if (auto next = chordFrom(*voiceAim_, voiced(settings), settings, false)) {
                walked_ = std::move(next);
                out.push_back(DeskEffect::rumble(Rumble::bump));
            }
        }
    }
    if (const auto direction = voices_.target()) {
        const int band = RadialBands::two().band(input.frame.right.radius(), voiceBand_);
        if (voiceBand_ && band != *voiceBand_) out.push_back(DeskEffect::rumble(Rumble::tick));
        voiceBand_ = band;
        const VoiceMove move{*direction, band + 1};
        const auto next = chordFrom(move, voiced(settings), settings, false);
        voiceAim_ = next ? std::optional<VoiceMove>(move) : std::nullopt;
        if (input.pressed(PadButton::r3) && next) {
            walked_ = next;
            voiceAim_ = std::nullopt;
        }
    } else {
        voiceBand_ = std::nullopt;
        voiceAim_ = std::nullopt;
    }
    return out;
}

std::vector<DeskEffect> TwinRings::stepBass(const PadInput &input, const DeskSettings &settings) {
    std::vector<DeskEffect> out;
    for (const auto &event : bass_.step(input.frame.left, VoiceLeading::bassGate(), input.time())) {
        lb_.use();
        if (std::holds_alternative<StickGesture::Flick>(event) && bassAim_) {
            if (auto next = chordFrom(*bassAim_, voiced(settings), settings, true)) {
                walked_ = std::move(next);
                out.push_back(DeskEffect::rumble(Rumble::bump));
            }
        }
    }
    if (const auto direction = bass_.target()) {
        const int band = RadialBands::two().band(input.frame.left.radius(), bassBand_);
        if (bassBand_ && band != *bassBand_) out.push_back(DeskEffect::rumble(Rumble::tick));
        bassBand_ = band;
        const VoiceMove move{*direction, band + 1};
        bassAim_ = chordFrom(move, voiced(settings), settings, true) ? std::optional<VoiceMove>(move) : std::nullopt;
    } else {
        bassBand_ = std::nullopt;
        bassAim_ = std::nullopt;
    }
    return out;
}

bool TwinRings::allows(const std::function<void(TwinRings &)> &change, const DeskSettings &settings) const {
    TwinRings changed = *this;
    change(changed);
    return settings.playable(changed.chord(settings));
}

void TwinRings::letGoOfVoices() {
    voices_.reset();
    bass_.reset();
    voiceAim_ = std::nullopt;
    bassAim_ = std::nullopt;
    voiceBand_ = std::nullopt;
    bassBand_ = std::nullopt;
}

TwinRings::VoiceTargets TwinRings::voiceTargets(const DeskSettings &settings) const {
    const DeskChord from = voiced(settings);
    const std::vector<int> notes = from.notes(settings);
    const auto targets = [&](int shell) {
        std::vector<std::optional<Target>> out;
        for (size_t direction = 0; direction < VoiceLeading::moves.size(); ++direction) {
            const VoiceMove move{static_cast<int>(direction), shell};
            if (!VoiceLeading::moved(notes, move)) {
                out.push_back(std::nullopt);
                continue;
            }
            const double bearing = VoiceLeading::gate().bearings[direction];
            const auto chord = VoiceLeading::neighbour(notes, move, settings.key);
            if (!chord) {
                out.push_back(Target{.bearing = bearing,
                                     .name = "·",
                                     .detail = VoiceLeading::names[direction],
                                     .isHidden = true});
                continue;
            }
            out.push_back(Target{.bearing = bearing,
                                 .name = chord->name(),
                                 .detail = shell == 1 ? VoiceLeading::names[direction] : "",
                                 .fit = chord->fit(settings.key),
                                 .isAimed = move == voiceAim_,
                                 .isHidden = !settings.playable(*chord)});
        }
        return out;
    };
    return VoiceTargets{targets(1), targets(2)};
}

std::vector<std::optional<Target>> TwinRings::bassTargets(const DeskSettings &settings) const {
    const std::vector<int> notes = voiced(settings).notes(settings);
    static constexpr std::array<std::pair<int, int>, 4> moves = {{{0, 1}, {0, 2}, {1, 1}, {1, 2}}};
    std::vector<std::optional<Target>> out;
    for (const auto &[direction, shell] : moves) {
        const VoiceMove move{direction, shell};
        if (!VoiceLeading::bassMoved(notes, move)) {
            out.push_back(std::nullopt);
            continue;
        }
        const std::string arrow = direction == 0 ? "↑" : "↓";
        std::string detail = "bass ";
        for (int i = 0; i < shell; ++i) detail += arrow;
        const double bearing = direction == 0 ? 0 : 180;
        const auto chord = VoiceLeading::bassNeighbour(notes, move, settings.key);
        if (!chord) {
            out.push_back(Target{.bearing = bearing, .name = "·", .detail = detail, .isHidden = true});
            continue;
        }
        out.push_back(Target{.bearing = bearing,
                             .name = chord->name(),
                             .detail = detail,
                             .fit = chord->fit(settings.key),
                             .isAimed = move == bassAim_,
                             .isHidden = !settings.playable(*chord)});
    }
    return out;
}

std::vector<Target> TwinRings::degreeTargets(const DeskSettings &settings) const {
    return desk::degreeTargets(degree_, line_.isSounding() ? line_.chord() : std::nullopt, settings);
}

std::vector<std::vector<Target>> TwinRings::ringTargets(const DeskSettings &settings) const {
    const RingPie pie = settings.ring(degree_, struck_);
    const std::optional<DeskChord> sounding = line_.isSounding() ? line_.chord() : std::nullopt;
    std::vector<std::vector<Target>> rings;
    for (StackHeight height : RingPie::heights(isExtended_)) {
        std::vector<Target> ring;
        for (const auto &sector : pie.sectors) {
            const RingCell cell{sector.mode, height};
            const DeskChord chord(settings.key, degree_, pie.color(cell));
            ring.push_back(Target{.bearing = sector.bearing,
                                  .name = chord.name(),
                                  .detail = displayName(sector.mode),
                                  .fit = chord.fit(settings.key),
                                  .isNear = chord.isOneStep(sounding),
                                  .isAimed = cell == aim_,
                                  .isKept = cell == kept_,
                                  .isHidden = !pie.allows(cell)});
        }
        rings.push_back(std::move(ring));
    }
    return rings;
}

std::vector<std::optional<Target>> TwinRings::favoriteTargets(const DeskSettings &settings) const {
    const std::vector<ChordColor> pinned = settings.favorites.colors(settings.key, degree_);
    std::vector<std::optional<Target>> out;
    for (int index = 0; index < Favorites::perChord; ++index) {
        if (index >= static_cast<int>(pinned.size())) {
            out.push_back(std::nullopt);
            continue;
        }
        const DeskChord chord(settings.key, degree_, pinned[static_cast<size_t>(index)]);
        out.push_back(Target{.bearing = favoritesGate().bearings[static_cast<size_t>(index)],
                             .name = chord.name(),
                             .detail = std::to_string(index + 1),
                             .fit = chord.fit(settings.key),
                             .isAimed = index == favoriteAim_,
                             .isKept = index == keptFavorite_,
                             .isHidden = !settings.playable(chord)});
    }
    return out;
}

std::vector<Target> TwinRings::compassTargets(const DeskSettings &settings) const {
    TwinRings base = *this;
    base.compassAim_ = std::nullopt;
    base.keptStep_ = std::nullopt;
    const DeskChord from = base.colored(settings);
    std::vector<Target> out;
    for (size_t index = 0; index < CompassPie::places().size(); ++index) {
        const int place = static_cast<int>(index);
        const auto chord = CompassPie::chord(place, from, settings.ranking);
        out.push_back(Target{.bearing = CompassPie::gate().bearings[index],
                             .name = chord ? chord->name() : "—",
                             .detail = CompassPie::edit(place, from, settings.ranking).value_or(""),
                             .fit = chord ? chord->fit(settings.key) : ChordFit::inKey,
                             .isAimed = place == compassAim_,
                             .isKept = place == keptStep_,
                             .isHidden = chord ? !settings.playable(*chord) : false});
    }
    return out;
}

Legend TwinRings::legend(const DeskSettings &settings) const {
    Legend legend = commonLegend(settings);
    legend[PadControl::leftStick()] = "Degree · " + numeral(degree_, settings.key);
    legend[PadControl::rightStick()] = isOnFavorites_ ? "Favorites: flick keeps, hold plays"
                                       : isOnCompass_ ? "Step compass: flick keeps, hold plays"
                                       : isExtended_  ? "Ring to the 13th: flick keeps, hold plays"
                                                      : "Color ring: flick keeps, hold plays";
    legend[PadControl::rightTrigger()] = "Strike · pull = swell";
    const auto rate = arpeggioRate(arpeggioStep_);
    legend[PadControl::leftTrigger()] = "Arpeggio " + (rate ? name(*rate) : std::string("off"));
    legend[PadControl::button(PadButton::a)] =
        isOnFavorites_ ? "Pin this chord to " + settings.favorites.table().name : std::string("Strike");
    legend[PadControl::button(PadButton::b)] = "Let go";
    legend[PadControl::button(PadButton::x)] =
        isOnFavorites_ ? std::string("Unpin the favorite aimed at")
                       : "Voice leading " + std::string(settings.voiceLeading ? "on" : "off");
    legend[PadControl::button(PadButton::y)] =
        "Tap: hold " + std::string(holds_ ? "on" : "off") + " · hold: favorites";
    legend[PadControl::button(PadButton::lb)] =
        "Tap: key a 5th down · long-press: compass " + std::string(compassLatched_ ? "off" : "on");
    legend[PadControl::button(PadButton::rb)] = "Tap: key a 5th up · hold: to 13th";
    legend[PadControl::button(PadButton::l3)] = "Ring: " + name(settings.ringArrangement) + " → next";
    const auto back = resetsTo(settings);
    legend[PadControl::button(PadButton::r3)] =
        back ? "Keep aimed · at rest: back to " + back->name() : std::string("Keep the cell aimed");
    if (isOnCompass_) {
        legend[PadControl::button(PadButton::l3)] = "LB layer: " + name(settings.lbLayer) + " → " +
                                                    (settings.lbLayer == LBLayer::compass ? "Voices" : "Compass");
    }
    if (isOnVoices_) {
        legend[PadControl::leftStick()] = "Bass ↑ ↓: flick takes, hold plays";
        legend[PadControl::rightStick()] = "Voices: ↕ top, ↔ middle, diagonals both; outer ring two semitones";
    }
    return legend;
}

} // namespace perfecto::desk
