// Ported from the "Arranger" and "Arrangement" suites of
// Tests/DeskCoreTests/LayoutTests.swift.

#include <doctest.h>

#include "perfecto/desk/arrangement.hpp"
#include "perfecto/desk/arranger.hpp"
#include "rig.hpp"

#include <algorithm>
#include <charconv>
#include <cmath>
#include <optional>
#include <string>
#include <variant>
#include <vector>

using namespace perfecto::desk;
using namespace perfecto::desk::testing;
using namespace perfecto::theory;

namespace {

/// Seconds a beat lasts at the settings' 96 bpm.
constexpr double beat = 60.0 / 96;

/// A `Double` as Swift's string interpolation writes it: the shortest form
/// that reads back the same, with ".0" on a whole number.
std::string described(double value) {
    char buffer[64];
    const auto result = std::to_chars(buffer, buffer + sizeof buffer, value);
    std::string text(buffer, result.ptr);
    if (text.find_first_of(".e") == std::string::npos) text += ".0";
    return text;
}

/// Presses `button` `times` times, from `time`, a frame down and a frame up each.
void tap(Rig<Arranger> &rig, PadButton button, int times, double time) {
    for (int i = 0; i < times; ++i) {
        const double at = time + static_cast<double>(i) * 0.02;
        rig.at(at, [&](GamepadFrame &f) { f.buttons = {button}; });
        rig.at(at + 0.01, [](GamepadFrame &f) { f.buttons = {}; });
    }
}

void tap(Rig<Arranger> &rig, PadButton button, double time) { tap(rig, button, 1, time); }

std::vector<std::string> placed(const Rig<Arranger> &rig) {
    std::vector<std::string> out;
    for (const Placed &chord : rig.layout.arrangement().chords())
        out.push_back(chord.chord.name() + " " + described(chord.start) + "+" + described(chord.length));
    return out;
}

using Notes = std::vector<std::vector<int>>;
using Names = std::vector<std::string>;

bool contains(const std::vector<DeskEffect> &effects, const DeskEffect &effect) {
    return std::ranges::find(effects, effect) != effects.end();
}

} // namespace

TEST_SUITE("Arranger") {

TEST_CASE("A writes a beat and moves on") {
    Rig rig{Arranger()};
    tap(rig, PadButton::a, 1);
    rig.at(2, [](GamepadFrame &f) { f.left = lean(4 * 360.0 / 7); });
    tap(rig, PadButton::a, 3);
    CHECK(placed(rig) == Names{"C maj 0.0+1.0", "G maj 1.0+1.0"});
    CHECK(rig.layout.cursor() == 2);
}

TEST_CASE("RT writes for as long as it is held") {
    Rig rig{Arranger()};
    const auto struck = rig.at(1, [](GamepadFrame &f) { f.rightTrigger = 1; });
    CHECK(sounded(struck) == Notes{{60, 64, 67}});
    // A tick is felt as each beat passes.
    int ticks = 0;
    for (int i = 1; i <= 30; ++i)
        for (const DeskEffect &effect : rig.at(1 + static_cast<double>(i) * 0.05))
            if (effect == DeskEffect::rumble(Rumble::tick)) ++ticks;
    CHECK(ticks == 2);
    // Let go a beat and a half after striking: snapped to the sixteenths.
    rig.at(1 + 1.5 * beat, [](GamepadFrame &f) { f.rightTrigger = 0; });
    CHECK(placed(rig) == Names{"C maj 0.0+1.5"});
    CHECK(rig.layout.cursor() == 1.5);
}

TEST_CASE("a free grid keeps the length as held") {
    Rig rig{Arranger()};
    rig.settings.grid = BeatGrid::free;
    rig.at(1, [](GamepadFrame &f) { f.rightTrigger = 1; });
    rig.at(1 + 0.7 * beat, [](GamepadFrame &f) { f.rightTrigger = 0; });
    const auto &chords = rig.layout.arrangement().chords();
    const double length = chords.empty() ? 0 : chords.front().length;
    CHECK(std::abs(length - 0.7) < 0.001);
}

TEST_CASE("playing, RT records live at the playhead") {
    Rig rig{Arranger()};
    tap(rig, PadButton::y, 0);
    // Struck as the third beat starts, let go a beat later.
    rig.at(2 * beat, [](GamepadFrame &f) { f.rightTrigger = 1; });
    rig.at(2.5 * beat);
    rig.at(3 * beat, [](GamepadFrame &f) { f.rightTrigger = 0; });
    CHECK(placed(rig) == Names{"C maj 2.0+1.0"});
    CHECK(rig.layout.cursor() == 0);
}

TEST_CASE("the bumpers stretch the chord at the cursor") {
    Rig rig{Arranger()};
    tap(rig, PadButton::a, 1);
    tap(rig, PadButton::rb, 2);
    CHECK(placed(rig) == Names{"C maj 0.0+1.25"});
    // The cursor was at its end, and stays there.
    CHECK(rig.layout.cursor() == 1.25);
    tap(rig, PadButton::lb, 2, 3);
    CHECK(placed(rig) == Names{"C maj 0.0+0.75"});
}

TEST_CASE("a bumper held stretches smoothly") {
    Rig rig{Arranger()};
    rig.settings.grid = BeatGrid::free;
    tap(rig, PadButton::a, 1);
    rig.at(2, [](GamepadFrame &f) { f.buttons = {PadButton::rb}; });
    rig.at(2 + Arranger::stretchDelay + 0.5, [](GamepadFrame &f) { f.buttons = {PadButton::rb}; });
    const auto &chords = rig.layout.arrangement().chords();
    const double length = chords.empty() ? 0 : chords.front().length;
    CHECK(std::abs(length - (1 + 0.25 + 0.5 * Arranger::stretchRate)) < 0.001);
}

TEST_CASE("a stretch stops at the next chord") {
    Rig rig{Arranger()};
    tap(rig, PadButton::a, 2, 1);
    tap(rig, PadButton::left, 5, 2);
    CHECK(rig.layout.cursor() == 0.75);
    rig.at(3, [](GamepadFrame &f) { f.buttons = {PadButton::rb}; });
    rig.at(6, [](GamepadFrame &f) { f.buttons = {PadButton::rb}; });
    CHECK(placed(rig) == Names{"C maj 0.0+1.0", "C maj 1.0+1.0"});
}

TEST_CASE("playing strikes each chord as it starts and is silent between") {
    Rig rig{Arranger()};
    tap(rig, PadButton::a, 0);
    tap(rig, PadButton::right, 4, 0.1);
    rig.at(0.3, [](GamepadFrame &f) { f.left = lean(4 * 360.0 / 7); });
    tap(rig, PadButton::a, 0.4);
    tap(rig, PadButton::left, 12, 0.5);
    CHECK(placed(rig) == Names{"C maj 0.0+1.0", "G maj 2.0+1.0"});
    CHECK(rig.layout.cursor() == 0);
    const double start = 10.0;
    const auto first = rig.at(start, [](GamepadFrame &f) { f.buttons = {PadButton::y}; });
    CHECK(sounded(first) == Notes{{60, 64, 67}});
    const auto gap = rig.at(start + 1.5 * beat, [](GamepadFrame &f) { f.buttons = {}; });
    CHECK(contains(gap, DeskEffect::silence(Line::chord)));
    const auto second = rig.at(start + 2.25 * beat);
    CHECK(sounded(second) == Notes{{67, 71, 74}});
    // Round the loop, the first chord is struck again.
    const auto again = rig.at(start + 16.1 * beat);
    CHECK(sounded(again) == Notes{{60, 64, 67}});
}

TEST_CASE("undo takes back a write") {
    Rig rig{Arranger()};
    tap(rig, PadButton::a, 1);
    tap(rig, PadButton::b, 2);
    CHECK(rig.layout.arrangement().isEmpty());
}

TEST_CASE("the arrangement is a MIDI file with its lengths") {
    Rig rig{Arranger()};
    rig.at(1, [](GamepadFrame &f) { f.rightTrigger = 1; });
    rig.at(1 + 2 * beat, [](GamepadFrame &f) { f.rightTrigger = 0; });
    const auto file = rig.layout.midiFile(rig.settings);
    std::vector<int> offs;
    if (file && !file->tracks.empty())
        for (const MidiEvent &event : file->tracks.front().events)
            if (std::holds_alternative<MidiEvent::NoteOff>(event.kind)) offs.push_back(event.tick);
    CHECK(offs == std::vector<int>{960, 960, 960});
    CHECK(Arranger().midiFile(DeskSettings()) == std::nullopt);
}

}

TEST_SUITE("Arrangement") {

namespace {
const DeskChord c(Key{PitchClass::C, ScaleType::major}, Degree::I);
const DeskChord g(Key{PitchClass::C, ScaleType::major}, Degree::V);
} // namespace

TEST_CASE("a chord placed over another cuts it short") {
    Arrangement arrangement;
    arrangement.place(c, 0, 4);
    arrangement.place(g, 2, 1);
    CHECK(arrangement.chords() == std::vector<Placed>{Placed{0, 2, c}, Placed{2, 1, g}});
    arrangement.place(c, 1.5, 3);
    REQUIRE(!arrangement.chords().empty());
    std::vector<double> starts;
    for (const Placed &placed : arrangement.chords()) starts.push_back(placed.start);
    CHECK(starts == std::vector<double>{0, 1.5});
    CHECK(arrangement.chords().front().length == 1.5);
}

TEST_CASE("a chord ends at the loop's end") {
    Arrangement arrangement;
    arrangement.place(c, 15, 4);
    REQUIRE(!arrangement.chords().empty());
    CHECK(arrangement.chords().front().length == 1);
}

TEST_CASE("the grid snaps lengths") {
    CHECK(length(BeatGrid::sixteenth, 0.1) == 0.25);
    CHECK(length(BeatGrid::sixteenth, 1.02) == 1);
    CHECK(length(BeatGrid::quarter, 1.4) == 2);
    CHECK(length(BeatGrid::free, 0.05) == 0.125);
    CHECK(nearest(BeatGrid::eighth, 1.3) == 1.5);
}

}
