#include "perfecto/desk/arranger.hpp"

#include <algorithm>
#include <cmath>
#include <utility>
#include <variant>

namespace perfecto::desk {

using namespace theory;

namespace {

void append(std::vector<DeskEffect> &out, const std::vector<DeskEffect> &more) {
    out.insert(out.end(), more.begin(), more.end());
}

} // namespace

std::vector<DeskEffect> Arranger::step(const PadInput &input, DeskSettings &settings) {
    std::vector<DeskEffect> out;
    const double time = input.time();
    const BeatGrid grid = settings.grid;
    const double length = Arrangement::length;

    // The cursor, a line of the grid or a bar at a time.
    if (!writing_) {
        if (input.pressed(PadButton::left)) cursor_ = wrap(nearest(grid, cursor_ - move(grid)));
        if (input.pressed(PadButton::right)) cursor_ = wrap(nearest(grid, cursor_ + move(grid)));
        if (input.pressed(PadButton::up)) cursor_ = wrap(cursor_ - static_cast<double>(Arrangement::beatsPerBar));
        if (input.pressed(PadButton::down)) cursor_ = wrap(cursor_ + static_cast<double>(Arrangement::beatsPerBar));
    }
    if (input.pressed(PadButton::l3)) {
        settings.moveGrid(1);
        cursor_ = wrap(nearest(settings.grid, cursor_));
        out.push_back(DeskEffect::rumble(Rumble::tick));
    }

    // The aim: the degree and the ring, as Twin rings has them.
    degreeSector_ = DegreePie::gate().select(input.frame.left, degreeSector_);
    if (degreeSector_ && input.frame.left.radius() >= PieGate::rest) degree_ = DegreePie::degree(*degreeSector_);
    // Turned to nearness from the chord the cursor follows, which aiming does not change.
    const auto near = arrangement_.chordNear(cursor_);
    const RingPie pie = settings.ring(degree_, near ? std::optional(near->chord) : std::nullopt);
    const RingPie::Gate ring = pie.gate(false);
    const std::vector<int> &reachable = ring.sectors;
    ringSector_ = ring.gate.select(input.frame.right, ringSector_);
    if (ringSector_ && *ringSector_ >= 0 && *ringSector_ < static_cast<int>(reachable.size())) {
        band_ = RadialBands::three().band(input.frame.right.radius(), band_);
        aim_ = pie.cell(reachable[static_cast<size_t>(*ringSector_)], *band_, false);
    } else {
        band_ = std::nullopt;
        aim_ = std::nullopt;
    }

    // Playing: Y starts and stops, from the cursor.
    if (input.pressed(PadButton::y)) {
        if (!playing_) {
            playing_ = Playing{time, cursor_};
        } else {
            playing_ = std::nullopt;
            playhead_ = std::nullopt;
            heard_ = std::nullopt;
            if (!writing_) append(out, line_.release());
        }
    }
    int round = 0;
    if (playing_) {
        const double beats = playing_->from + (time - playing_->since) * settings.tempo / 60;
        round = static_cast<int>(std::floor(beats / length));
        playhead_ = beats - static_cast<double>(round) * length;
    }

    // A: a beat's chord at the cursor.
    if (input.pressed(PadButton::a) && !writing_) {
        if (const auto why = settings.consonance.refusal(aimed(settings), settings.key)) {
            out.push_back(DeskEffect::refuse(*why));
        } else {
            const DeskChord chord = aimed(settings);
            const double at = cursor_;
            edit([&](Arrangement &arrangement) { arrangement.place(chord, at, 1); });
            cursor_ = wrap(cursor_ + 1);
        }
    }

    // RT: a chord for as long as it is held.
    for (const auto &event : commit_.step(input.frame.rightTrigger, time)) {
        if (const auto *strike = std::get_if<TriggerStrike::Strike>(&event)) {
            if (const auto why = settings.consonance.refusal(aimed(settings), settings.key)) {
                out.push_back(DeskEffect::refuse(*why));
                continue;
            }
            const bool live = playhead_.has_value();
            const double start = live ? wrap(nearest(grid, *playhead_)) : cursor_;
            writing_ = Writing{start, time, 0, live};
            ticked_ = 0;
            append(out, line_.strike(aimed(settings), strike->level, settings, time));
            heard_ = std::nullopt;
        } else if (std::holds_alternative<TriggerStrike::Depth>(event)) {
            continue;
        } else {
            if (!writing_) continue;
            const Writing done = *writing_;
            writing_ = std::nullopt;
            const double held = (time - done.since) * settings.tempo / 60;
            const double written = std::min(desk::length(grid, held), length - done.start);
            const DeskChord chord = aimed(settings);
            edit([&](Arrangement &arrangement) { arrangement.place(chord, done.start, written); });
            out.push_back(DeskEffect::rumble(Rumble::bump));
            if (done.isLive) {
                // What sounds is the chord just written: playing carries on from it.
                heard_ = Heard{done.start, round};
            } else {
                cursor_ = wrap(done.start + written);
                append(out, line_.release());
            }
        }
    }
    if (writing_) {
        Writing held = *writing_;
        held.length = std::min(length - held.start, (time - held.since) * settings.tempo / 60);
        writing_ = held;
        const int beat = static_cast<int>(std::floor(held.length));
        if (beat > ticked_) {
            ticked_ = beat;
            out.push_back(DeskEffect::rumble(Rumble::tick));
        }
        if (settings.playable(aimed(settings))) append(out, line_.change(aimed(settings), settings));
    }

    // LB and RB: the chord at the cursor shorter and longer.
    for (const auto &[button, direction] : {std::pair(PadButton::lb, -1.0), std::pair(PadButton::rb, 1.0)}) {
        if (input.pressed(button) && !writing_) {
            if (const auto placed = arrangement_.chordNear(cursor_)) {
                undo_.push_back(arrangement_);
                stretch_ = Stretch{placed->start, placed->length, direction, time};
                ticked_ = 0;
            }
        }
        if (input.released(button) && stretch_ && stretch_->direction == direction) stretch_ = std::nullopt;
    }
    if (stretch_) {
        const Stretch stretch = *stretch_;
        const double held = std::max(0.0, time - stretch.since - stretchDelay);
        const double by = move(grid) + held * stretchRate;
        const double wanted = nearest(grid, stretch.from + stretch.direction * by);
        const bool atEnd = !arrangement_.chordAt(cursor_).has_value();
        if (const auto made = arrangement_.resize(stretch.start, wanted, shortest(grid))) {
            if (atEnd) cursor_ = wrap(stretch.start + *made);
            const int steps = static_cast<int>(std::floor(std::fabs(*made - stretch.from) / move(grid)));
            if (steps > ticked_) {
                ticked_ = steps;
                out.push_back(DeskEffect::rumble(Rumble::tick));
            }
        }
    }

    if (input.pressed(PadButton::x) && !writing_) {
        const double at = cursor_;
        edit([&](Arrangement &arrangement) { arrangement.clear(at); });
    }
    if (input.pressed(PadButton::b) && !writing_ && !undo_.empty()) {
        arrangement_ = undo_.back();
        undo_.pop_back();
    }

    // LT listens to the chord aimed, while nothing plays or is written.
    const bool listening =
        input.frame.leftTrigger > 0.1 && !playing_ && !writing_ && settings.playable(aimed(settings));
    if (listening) {
        append(out, isAuditioning_
                        ? line_.change(aimed(settings), settings)
                        : line_.strike(aimed(settings), 0.3 + 0.6 * input.frame.leftTrigger, settings, time));
    } else if (isAuditioning_ && !writing_) {
        append(out, line_.release());
    }
    isAuditioning_ = listening;

    // What plays: the chord under the playhead, struck as it starts.
    if (playhead_ && !writing_) {
        const auto placed = arrangement_.chordAt(*playhead_);
        const std::optional<double> placedStart = placed ? std::optional(placed->start) : std::nullopt;
        const std::optional<double> heardStart = heard_ ? std::optional(heard_->start) : std::nullopt;
        const std::optional<int> heardRound = heard_ ? std::optional(heard_->round) : std::nullopt;
        if (placedStart != heardStart || (placed && std::optional(round) != heardRound)) {
            if (placed) {
                heard_ = Heard{placed->start, round};
                append(out, line_.strike(placed->chord, 0.8, settings, time));
            } else {
                heard_ = std::nullopt;
                append(out, line_.release());
            }
        }
    }
    append(out, line_.tick(settings, time));
    return out;
}

DeskChord Arranger::aimed(const DeskSettings &settings) const {
    return DeskChord(settings.key, degree_, aim_ ? settings.ring(degree_).color(*aim_) : ChordColor::base());
}

void Arranger::edit(const std::function<void(Arrangement &)> &change) {
    undo_.push_back(arrangement_);
    if (undo_.size() > 64) undo_.erase(undo_.begin());
    change(arrangement_);
}

double Arranger::wrap(double beats) {
    const double length = Arrangement::length;
    const double wrapped = std::fmod(beats, length);
    return wrapped < 0 ? wrapped + length : wrapped;
}

std::vector<DeskEffect> Arranger::releaseAll() {
    playing_ = std::nullopt;
    playhead_ = std::nullopt;
    heard_ = std::nullopt;
    isAuditioning_ = false;
    writing_ = std::nullopt;
    stretch_ = std::nullopt;
    commit_ = TriggerStrike();
    return line_.release();
}

std::optional<MidiFile> Arranger::midiFile(const DeskSettings &settings) const {
    if (arrangement_.isEmpty()) return std::nullopt;
    const int ticks = 480;
    const auto tick = [&](double beats) { return static_cast<int>(std::round(beats * static_cast<double>(ticks))); };
    std::vector<MidiEvent> events = {
        MidiEvent{0, MidiEvent::TrackName{"Perfecto Desk"}},
        MidiEvent{0, MidiEvent::Tempo{settings.tempo}},
        MidiEvent{0, MidiEvent::TimeSignature{Arrangement::beatsPerBar, 4}},
        MidiEvent{0, midiKeySignature(settings.key)},
    };
    std::optional<std::vector<int>> previous;
    for (const Placed &placed : arrangement_.chords()) {
        const std::vector<int> notes = placed.chord.notes(settings, 0, 0, previous);
        previous = notes;
        events.push_back(MidiEvent{tick(placed.start), MidiEvent::Marker{placed.chord.name()}});
        for (int note : notes) {
            events.push_back(MidiEvent{tick(placed.start), MidiEvent::NoteOn{0, note, 100}});
            events.push_back(MidiEvent{tick(placed.end()), MidiEvent::NoteOff{0, note}});
        }
    }
    return MidiFile{ticks, {MidiTrack{std::move(events), tick(Arrangement::length)}}};
}

// What the screen shows

std::vector<Target> Arranger::degreeTargets(const DeskSettings &settings) const {
    return desk::degreeTargets(degree_, std::nullopt, settings);
}

Legend Arranger::legend(const DeskSettings &settings) const {
    Legend legend = commonLegend(settings, false);
    const BeatGrid grid = settings.grid;
    const std::string stepName = desk::step(grid) ? name(grid) : "a sixteenth";
    legend[PadControl::button(PadButton::left)] = "Cursor back " + stepName;
    legend[PadControl::button(PadButton::right)] = "Cursor on " + stepName;
    legend[PadControl::button(PadButton::up)] = "Cursor up a bar";
    legend[PadControl::button(PadButton::down)] = "Cursor down a bar";
    legend[PadControl::leftStick()] = "Degree · " + numeral(degree_, settings.key);
    legend[PadControl::rightStick()] = "Color ring";
    legend[PadControl::rightTrigger()] = !playing_ ? "Hold to write: as long as it's held" : "Record live at the playhead";
    legend[PadControl::leftTrigger()] = "Listen to the aimed chord";
    legend[PadControl::button(PadButton::a)] = "Write a beat";
    legend[PadControl::button(PadButton::x)] = "Clear the chord";
    legend[PadControl::button(PadButton::y)] = !playing_ ? "Play from the cursor" : "Stop";
    legend[PadControl::button(PadButton::b)] = "Undo";
    legend[PadControl::button(PadButton::lb)] = "Shorter: tap a step, hold smoothly";
    legend[PadControl::button(PadButton::rb)] = "Longer: tap a step, hold smoothly";
    legend[PadControl::button(PadButton::l3)] = "Grid: " + name(grid) + " → next";
    return legend;
}

} // namespace perfecto::desk
