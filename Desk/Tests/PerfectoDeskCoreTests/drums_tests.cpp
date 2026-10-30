// The drums: patterns, the machine that plays them in time, the hands that
// play them in Face Chords, and the studio that plays them beside the desk.

#include <doctest.h>

#include "perfecto/desk/drums.hpp"
#include "perfecto/desk/scene.hpp"
#include "perfecto/desk/studio.hpp"

#include <algorithm>
#include <cmath>
#include <vector>

using namespace perfecto::desk;

namespace {

using Hits = std::vector<DrumEffect::Hit>;

/// 120 beats a minute: a sixteenth is an eighth of a second, exactly.
constexpr double tempo120 = 120;
constexpr double sixteenth120 = 0.125;

Hits hits(const std::vector<DrumEffect> &effects) {
    Hits out;
    for (const auto &effect : effects)
        if (const auto *hit = std::get_if<DrumEffect::Hit>(&effect.value())) out.push_back(*hit);
    return out;
}

/// The times `drum` is struck in `effects`.
std::vector<double> times(const std::vector<DrumEffect> &effects, Drum drum) {
    std::vector<double> out;
    for (const auto &hit : hits(effects))
        if (hit.drum == drum) out.push_back(hit.time);
    return out;
}

/// A machine playing `pattern` from `start`, stepped every `frame` seconds
/// until `end`: everything it gave.
std::vector<DrumEffect> play(DrumMachine &machine, double start, double end, double frame = 0.004) {
    std::vector<DrumEffect> out = machine.start(start, tempo120);
    for (double time = start + frame; time < end; time += frame) {
        const auto more = machine.advance(time, tempo120);
        for (const auto &hit : hits(more)) {
            // Nothing is given before it is within the lookahead, and nothing late.
            CHECK(hit.time >= time - 1e-9);
            CHECK(hit.time < time + DrumMachine::lookahead);
        }
        out.insert(out.end(), more.begin(), more.end());
    }
    return out;
}

const SoundCatalog catalog({{"Keys", {{"electricPiano", "Electric Piano"}}}, {"Synth", {{"soloLead", "Solo Lead"}}}});

GamepadFrame frame(double time, std::set<PadButton> buttons = {}, double leftTrigger = 0) {
    return GamepadFrame{.time = time, .leftTrigger = leftTrigger, .buttons = std::move(buttons)};
}

bool strikesChords(const std::vector<DeskEffect> &effects) {
    return std::any_of(effects.begin(), effects.end(),
                       [](const DeskEffect &e) { return std::holds_alternative<DeskEffect::Sound>(e.value()); });
}

/// The items of `panel` that are a `T`.
template <class T> std::vector<T> items(const Panel &panel) {
    std::vector<T> out;
    for (const auto &item : panel.items)
        if (const auto *found = std::get_if<T>(&item)) out.push_back(*found);
    return out;
}

} // namespace

TEST_SUITE("Drums") {

TEST_CASE("a pattern reads its lines a step at a time, round the bar") {
    const DrumPattern &backbeat = drumPatterns().at(0);
    CHECK(backbeat.name == "Backbeat");
    using Struck = std::vector<std::pair<Drum, double>>;
    CHECK(backbeat.at(0) == Struck{{Drum::kick, 1.0}, {Drum::closedHat, 1.0}});
    CHECK(backbeat.at(2) == Struck{{Drum::closedHat, 0.75}});
    CHECK(backbeat.at(4) == Struck{{Drum::snare, 1.0}, {Drum::closedHat, 1.0}});
    CHECK(backbeat.at(1).empty());
    CHECK_FALSE(backbeat.isStruck(1));
    CHECK(backbeat.at(16) == backbeat.at(0));
    CHECK(backbeat.at(-12) == backbeat.at(4));
}

TEST_CASE("every pattern is a bar of steps, each a rest, a ghost, a hit or an accent") {
    CHECK(drumPatterns().size() == 6);
    for (const auto &pattern : drumPatterns()) {
        CHECK(pattern.isStruck(0));
        for (const auto &[drum, line] : pattern.lines) {
            CHECK(line.size() == size_t(DrumPattern::steps));
            CHECK(std::all_of(line.begin(), line.end(), [](char c) { return std::string(".oxX").find(c) != std::string::npos; }));
        }
    }
    CHECK(level('.') == 0);
    CHECK(level('o') < level('x'));
    CHECK(level('x') < level('X'));
}

TEST_CASE("swing makes the second sixteenth of each pair late") {
    DrumPattern straight{"Straight", {}};
    CHECK(straight.lateness(1) == 0);
    DrumPattern triplet{"Triplet", {}, 2.0 / 3};
    CHECK(triplet.lateness(0) == 0);
    CHECK(triplet.lateness(1) == doctest::Approx(1.0 / 3));
    CHECK(triplet.lateness(2) == 0);
}

TEST_CASE("each drum has its General MIDI note, every one its own") {
    std::set<int> notes;
    for (const Drum drum : allDrums) notes.insert(generalMidi(drum));
    CHECK(notes.size() == allDrums.size());
    CHECK(generalMidi(Drum::kick) == 36);
    CHECK(generalMidi(Drum::snare) == 38);
    CHECK(generalMidi(Drum::closedHat) == 42);
    CHECK(generalMidi(Drum::openHat) == 46);
}

TEST_CASE("a closed hat chokes the open one") {
    CHECK(chokes(Drum::closedHat) == std::vector<Drum>{Drum::openHat});
    CHECK(chokes(Drum::openHat).empty());
    CHECK(strike(Drum::closedHat, 0.5, 2) ==
          std::vector<DrumEffect>{DrumEffect::choke(Drum::openHat, 2), DrumEffect::hit(Drum::closedHat, 0.5, 2)});
    CHECK(strike(Drum::kick, 1, 2) == std::vector<DrumEffect>{DrumEffect::hit(Drum::kick, 1, 2)});
}

TEST_CASE("the beat starts on its first step at once") {
    DrumMachine machine;
    CHECK(machine.start(10, tempo120) == std::vector<DrumEffect>{DrumEffect::hit(Drum::kick, 1, 10),
                                                              DrumEffect::choke(Drum::openHat, 10),
                                                              DrumEffect::hit(Drum::closedHat, 1, 10)});
    CHECK(machine.isPlaying());
    CHECK(machine.step(10) == 0);
}

TEST_CASE("each step is given once, ahead of its time, a sixteenth after the last") {
    DrumMachine machine;
    const auto played = play(machine, 10, 12.01);
    CHECK(times(played, Drum::kick) ==
          std::vector<double>{10, 10 + 6 * sixteenth120, 10 + 8 * sixteenth120, 10 + 10 * sixteenth120, 12});
    CHECK(times(played, Drum::snare) == std::vector<double>{10 + 4 * sixteenth120, 10 + 12 * sixteenth120});
    CHECK(times(played, Drum::closedHat).size() == 9);
}

TEST_CASE("unevenly stepped, the beat sounds the same") {
    DrumMachine even, uneven;
    const auto evenly = play(even, 0, 4, 0.004);
    const auto unevenly = play(uneven, 0, 4, 0.0313);
    CHECK(evenly == unevenly);
}

TEST_CASE("a change of tempo is heard from the next step") {
    DrumMachine machine;
    std::vector<DrumEffect> played = machine.start(0, tempo120);
    for (double time = 0.004; time < 0.3; time += 0.004) {
        const auto more = machine.advance(time, tempo120);
        played.insert(played.end(), more.begin(), more.end());
    }
    // Three steps placed at 120; from the fourth, each is a sixteenth at 60.
    for (double time = 0.3; time < 2.5; time += 0.004) {
        const auto more = machine.advance(time, 60);
        played.insert(played.end(), more.begin(), more.end());
    }
    CHECK(times(played, Drum::snare) == std::vector<double>{3 * sixteenth120 + 0.25});
    CHECK(times(played, Drum::kick) == std::vector<double>{0, 3 * sixteenth120 + 3 * 0.25, 3 * sixteenth120 + 5 * 0.25, 3 * sixteenth120 + 7 * 0.25});
}

TEST_CASE("a swung pattern's off sixteenths come late") {
    DrumMachine machine;
    machine.choose(3);
    CHECK(machine.played().name == "Shuffle");
    const auto played = play(machine, 0, 0.44);
    const double late = (0.64 - 0.5) * 2 * sixteenth120;
    CHECK(times(played, Drum::closedHat) == std::vector<double>{0, 2 * sixteenth120, 3 * sixteenth120 + late});
}

TEST_CASE("a step long past is skipped, not sounded late") {
    DrumMachine machine;
    machine.start(0, tempo120);
    // The desk was held up for a second: only what is due now is given.
    const auto late = machine.advance(1.01, tempo120);
    CHECK(hits(late).size() == 2);
    CHECK(times(late, Drum::kick) == std::vector<double>{1});
    CHECK(machine.step(1.01) == 8);
}

TEST_CASE("the step sounding is the latest given that has come") {
    DrumMachine machine;
    CHECK_FALSE(machine.step(0).has_value());
    machine.start(0, tempo120);
    machine.advance(0.1, tempo120);
    CHECK(machine.step(0.1) == 0);
    CHECK(machine.step(sixteenth120) == 1);
    machine.stop();
    CHECK_FALSE(machine.isPlaying());
    CHECK_FALSE(machine.step(1).has_value());
    CHECK(machine.advance(1, tempo120).empty());
}

TEST_CASE("the patterns go round, and a new one takes up the bar where it is") {
    DrumMachine machine;
    machine.choose(-1);
    CHECK(machine.pattern() == 5);
    machine.choose(2);
    CHECK(machine.pattern() == 1);
    machine.choose(-1);
    machine.start(0, tempo120);
    machine.advance(4 * sixteenth120 - 0.06, tempo120);
    machine.choose(1);
    CHECK(times(machine.advance(4 * sixteenth120 - 0.01, tempo120), Drum::clap) == std::vector<double>{4 * sixteenth120});
}

TEST_CASE("L3 starts and stops the beat, where the drums can be played") {
    Drums drums;
    DeskSettings settings;
    GamepadFrame last = frame(0);
    const auto step = [&](const GamepadFrame &next, bool reachable = true) {
        auto out = drums.step(PadInput(next, last), reachable, settings);
        last = next;
        return out;
    };
    auto pressed = step(frame(1, {PadButton::l3}));
    CHECK(drums.machine().isPlaying());
    CHECK(times(pressed.drums, Drum::kick) == std::vector<double>{1});
    CHECK(pressed.effects == std::vector<DeskEffect>{DeskEffect::rumble(Rumble::bump)});
    CHECK_FALSE(pressed.frame.isDown(PadButton::l3));
    step(frame(1.1));
    step(frame(1.2, {PadButton::l3}));
    CHECK_FALSE(drums.machine().isPlaying());
    step(frame(1.3));
    // Out of reach, L3 is the layout's.
    const auto elsewhere = step(frame(1.4, {PadButton::l3}), false);
    CHECK_FALSE(drums.machine().isPlaying());
    CHECK(elsewhere.frame.isDown(PadButton::l3));
}

TEST_CASE("RB held makes the face buttons pads, and keeps them from the chords until let go") {
    Drums drums;
    DeskSettings settings;
    GamepadFrame last = frame(0);
    const auto step = [&](const GamepadFrame &next) {
        auto out = drums.step(PadInput(next, last), true, settings);
        last = next;
        return out;
    };
    auto held = step(frame(1, {PadButton::rb}));
    CHECK(drums.isLayered());
    CHECK_FALSE(held.frame.isDown(PadButton::rb));
    held = step(frame(1.1, {PadButton::rb, PadButton::a}));
    CHECK(held.drums == std::vector<DrumEffect>{DrumEffect::hit(Drum::kick, 0.9, 1.1)});
    CHECK_FALSE(held.frame.isDown(PadButton::a));
    // RB let go, A still held: still the drums', not a chord.
    held = step(frame(1.2, {PadButton::a}));
    CHECK_FALSE(drums.isLayered());
    CHECK_FALSE(held.frame.isDown(PadButton::a));
    step(frame(1.3));
    // Pressed without RB, A is the chords'.
    CHECK(step(frame(1.4, {PadButton::a})).frame.isDown(PadButton::a));
}

TEST_CASE("with LT held in the drum layer the pads are the toms and the clap") {
    CHECK(Drums::pad(PadButton::a, false) == Drum::kick);
    CHECK(Drums::pad(PadButton::b, false) == Drum::snare);
    CHECK(Drums::pad(PadButton::x, false) == Drum::closedHat);
    CHECK(Drums::pad(PadButton::y, false) == Drum::openHat);
    CHECK(Drums::pad(PadButton::a, true) == Drum::lowTom);
    CHECK(Drums::pad(PadButton::b, true) == Drum::clap);
    CHECK(Drums::pad(PadButton::x, true) == Drum::midTom);
    CHECK(Drums::pad(PadButton::y, true) == Drum::highTom);
    CHECK_FALSE(Drums::pad(PadButton::lb, false).has_value());

    Drums drums;
    DeskSettings settings;
    drums.step(PadInput(frame(1, {PadButton::rb}, 0.9), frame(0)), true, settings);
    const auto clap = drums.step(PadInput(frame(1.1, {PadButton::rb, PadButton::b}, 0.9), frame(1, {PadButton::rb}, 0.9)),
                                 true, settings);
    CHECK(drums.isShifted());
    CHECK(clap.drums == std::vector<DrumEffect>{DrumEffect::hit(Drum::clap, 0.9, 1.1)});
}

TEST_CASE("while RB is held the desk sees LT where it was, and after, where it is") {
    Drums drums;
    DeskSettings settings;
    GamepadFrame last = frame(0, {}, 0.2);
    const auto step = [&](const GamepadFrame &next) {
        auto out = drums.step(PadInput(next, last), true, settings);
        last = next;
        return out;
    };
    CHECK(step(frame(1, {}, 0.2)).frame.leftTrigger == 0.2);
    CHECK(step(frame(1.1, {PadButton::rb}, 0.2)).frame.leftTrigger == 0.2);
    CHECK(step(frame(1.2, {PadButton::rb}, 0.9)).frame.leftTrigger == 0.2);
    CHECK(drums.isShifted());
    CHECK(step(frame(1.3, {}, 0.9)).frame.leftTrigger == 0.9);
}

TEST_CASE("RB and the d-pad choose the pattern and the tempo, within reach") {
    Drums drums;
    DeskSettings settings;
    GamepadFrame last = frame(0, {PadButton::rb});
    drums.step(PadInput(last, frame(0)), true, settings);
    const auto press = [&](PadButton button) {
        const GamepadFrame down = frame(last.time + 0.1, {PadButton::rb, button});
        auto out = drums.step(PadInput(down, last), true, settings);
        const GamepadFrame up = frame(down.time + 0.1, {PadButton::rb});
        drums.step(PadInput(up, down), true, settings);
        last = up;
        return out;
    };
    auto right = press(PadButton::right);
    CHECK(drums.machine().pattern() == 1);
    CHECK(right.effects == std::vector<DeskEffect>{DeskEffect::rumble(Rumble::tick)});
    CHECK_FALSE(right.frame.isDown(PadButton::right));
    press(PadButton::left);
    press(PadButton::left);
    CHECK(drums.machine().pattern() == 5);
    press(PadButton::up);
    CHECK(settings.tempo == 100);
    press(PadButton::down);
    press(PadButton::down);
    CHECK(settings.tempo == 92);
    settings.tempo = DeskSettings::tempos.upperBound;
    CHECK(press(PadButton::up).effects.empty());
    CHECK(settings.tempo == DeskSettings::tempos.upperBound);
}

TEST_CASE("without RB the d-pad is left to the layout") {
    Drums drums;
    DeskSettings settings;
    const auto out = drums.step(PadInput(frame(1, {PadButton::up}), frame(0)), true, settings);
    CHECK(out.frame.isDown(PadButton::up));
    CHECK(settings.tempo == 96);
}

TEST_CASE("the legend says what the drums' controls do") {
    Drums drums;
    DeskSettings settings;
    const Legend plain = drums.legend({}, true);
    CHECK(plain.at(PadControl::button(PadButton::l3)) == "Start the beat · Backbeat");
    CHECK(plain.at(PadControl::button(PadButton::rb)) == "Hold: drum pads");
    CHECK(drums.legend({}, false).empty());
    drums.step(PadInput(frame(1, {PadButton::rb}), frame(0)), true, settings);
    const Legend layered = drums.legend({}, true);
    CHECK(layered.at(PadControl::button(PadButton::a)) == "Kick");
    CHECK(layered.at(PadControl::button(PadButton::y)) == "Open hat");
    CHECK(layered.at(PadControl::button(PadButton::right)) == "Next pattern");
    CHECK(layered.at(PadControl::leftTrigger()) == "Hold: toms, clap");
}

} // TEST_SUITE

TEST_SUITE("Studio · drums") {

TEST_CASE("in Face Chords the drum pads strike drums, not chords") {
    Studio studio(Desk(catalog, DeskSettings(), LayoutKind::faceChords));
    CHECK(studio.reachable());
    studio.step(frame(1, {PadButton::rb}));
    const auto pad = studio.step(frame(1.1, {PadButton::rb, PadButton::a}));
    CHECK_FALSE(strikesChords(pad.effects));
    CHECK(pad.drums == std::vector<DrumEffect>{DrumEffect::hit(Drum::kick, 0.9, 1.1)});
    studio.step(frame(1.2));
    CHECK(strikesChords(studio.step(frame(1.3, {PadButton::a})).effects));
}

TEST_CASE("in Face Chords the toms' LT leaves a held chord as it is") {
    Studio studio(Desk(catalog, DeskSettings(), LayoutKind::faceChords));
    studio.step(frame(1, {PadButton::b}));
    CHECK(studio.desk().faceChords().heard()->second == perfecto::theory::Degree::IV);
    studio.step(frame(1.1, {PadButton::b, PadButton::rb}));
    const auto toms = studio.step(frame(1.2, {PadButton::b, PadButton::rb}, 0.9));
    CHECK_FALSE(strikesChords(toms.effects));
    CHECK(studio.desk().faceChords().heard()->second == perfecto::theory::Degree::IV);
}

TEST_CASE("the beat plays on under the menu, and stops with another layout") {
    Studio studio(Desk(catalog, DeskSettings(), LayoutKind::faceChords));
    studio.step(frame(1, {PadButton::l3}));
    studio.step(frame(1.1));
    studio.step(frame(1.2, {PadButton::start}));
    CHECK(studio.desk().menu().has_value());
    CHECK_FALSE(studio.reachable());
    CHECK(studio.drums().machine().isPlaying());
    CHECK_FALSE(studio.step(frame(1.6)).drums.empty());
    studio.step(frame(1.7, {PadButton::start}));
    studio.step(frame(1.8));
    studio.step(frame(1.9, {PadButton::back}));
    CHECK(studio.desk().layout() == LayoutKind::twinRings);
    CHECK_FALSE(studio.drums().machine().isPlaying());
}

TEST_CASE("a layout chosen by the mouse stops the beat, and so does letting go") {
    Studio studio(Desk(catalog, DeskSettings(), LayoutKind::faceChords));
    studio.step(frame(1, {PadButton::l3}));
    studio.choose(LayoutKind::petals);
    CHECK_FALSE(studio.drums().machine().isPlaying());
    studio.choose(LayoutKind::faceChords);
    studio.step(frame(2));
    studio.step(frame(2.1, {PadButton::l3}));
    CHECK(studio.drums().machine().isPlaying());
    studio.letGo();
    CHECK_FALSE(studio.drums().machine().isPlaying());
}

TEST_CASE("the screen shows the beat under Face Chords, and the pads while RB is held") {
    Studio studio(Desk(catalog, DeskSettings(), LayoutKind::faceChords));
    studio.step(frame(1, {PadButton::l3}));
    studio.step(frame(1.13));
    auto shown = scene(studio, false);
    // The left stick's panel is first, beside the face buttons'.
    const auto &panel = shown.stage.at(1);
    const auto captions = items<Caption>(panel);
    CHECK(captions.back().title == "Drums");
    CHECK(captions.back().aside == "▶ 96 bpm");
    const auto bar = items<Chips>(panel).at(0);
    CHECK(bar.columns == 16);
    CHECK(bar.chips[0] == Chips::Chip{"1", true, false});
    CHECK(bar.chips[1] == Chips::Chip{"·", false, true});
    CHECK(bar.chips[4].text == "2");
    // At 96 a sixteenth is 0.15625 s: the second step is given, but sounds from 1.15625.
    CHECK(std::count_if(bar.chips.begin(), bar.chips.end(), [](const auto &c) { return c.isLit; }) == 1);
    const auto patterns = items<Choices>(panel).at(0);
    CHECK(patterns.names.front() == "Backbeat");
    CHECK(patterns.chosen == 0);
    CHECK(items<Faces>(panel).at(0).faces[0].numeral == "I");
    CHECK(std::any_of(shown.hand.right.begin(), shown.hand.right.end(),
                      [](const auto &e) { return e.mark == "RB" && e.text == "Hold: drum pads"; }));

    studio.step(frame(1.2, {PadButton::rb, PadButton::x}));
    shown = scene(studio, false);
    const auto pads = items<Faces>(shown.stage.at(1)).at(0);
    CHECK(pads.faces[1] == Faces::Face{PadButton::x, 270, "Closed hat", "", "+LT Mid tom", true, false});
    CHECK(pads.detail == "Drum pads");
    CHECK(items<Caption>(shown.stage.at(1)).at(0).title == "Drum pads");
    // The hand shows X held, as the hands hold it.
    CHECK(std::any_of(shown.hand.right.begin(), shown.hand.right.end(),
                      [](const auto &e) { return e.mark == "X" && e.isHeld && e.text == "Closed hat"; }));
}

TEST_CASE("the drums take their buttons before the timeline, and the hand shows both") {
    Studio studio(Desk(catalog, DeskSettings(), LayoutKind::faceChords));
    studio.step(frame(1));
    // RB and RT held, and A: a kick, and no take begins.
    GamepadFrame kick = frame(1.1, {PadButton::rb, PadButton::a});
    kick.rightTrigger = 1;
    CHECK(studio.step(kick).drums == std::vector<DrumEffect>{DrumEffect::hit(Drum::kick, 0.9, 1.1)});
    CHECK_FALSE(studio.timeline().recording());
    studio.step(frame(1.2));
    // RT and A without RB: the timeline records.
    GamepadFrame record = frame(1.3, {PadButton::a});
    record.rightTrigger = 1;
    studio.step(record);
    CHECK(studio.timeline().recording());
    const auto shown = scene(studio, false);
    CHECK(shown.timeline.has_value());
    CHECK(std::any_of(shown.hand.right.begin(), shown.hand.right.end(),
                      [](const auto &e) { return e.mark == "RB" && e.text == "Hold: drum pads"; }));
    CHECK(std::any_of(shown.hand.right.begin(), shown.hand.right.end(), [](const auto &e) { return e.mark == "RT"; }));
}

TEST_CASE("in another layout the screen has no drums") {
    Studio studio(Desk(catalog, DeskSettings(), LayoutKind::twinRings));
    CHECK_FALSE(studio.reachable());
    for (const auto &panel : scene(studio, false).stage)
        for (const auto &caption : items<Caption>(panel)) CHECK(caption.title != "Drums");
}

} // TEST_SUITE
