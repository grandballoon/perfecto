// Ported from Tests/DeskCoreTests/DeskTests.swift, with the tests of
// ConsonanceTests.swift and FavoritesTests.swift that play a whole desk.

#include <doctest.h>

#include "perfecto/desk/desk.hpp"
#include "rig.hpp"

#include <algorithm>

using namespace perfecto::desk;
using namespace perfecto::desk::testing;
using namespace perfecto::theory;

namespace {

const SoundCatalog catalog({
    {"Keys", {{"electricPiano", "Electric Piano"}, {"organ", "Organ"}}},
    {"Synth", {{"soloLead", "Solo Lead"}}},
});

GamepadFrame frame(double time, std::set<PadButton> buttons = {}) {
    return GamepadFrame{.time = time, .buttons = std::move(buttons)};
}

bool contains(const std::vector<DeskEffect> &effects, const DeskEffect &effect) {
    return std::find(effects.begin(), effects.end(), effect) != effects.end();
}

} // namespace

TEST_SUITE("Desk") {

TEST_CASE("Back goes to the next layout and lets go") {
    Desk desk(catalog);
    desk.step(frame(1, {PadButton::a}));
    const auto out = desk.step(frame(2, {PadButton::a, PadButton::back}));
    CHECK(desk.layout() == LayoutKind::petals);
    CHECK(contains(out, DeskEffect::silence(Line::chord)));
}

TEST_CASE("the menu changes the chord sound and plays it") {
    Desk desk(catalog);
    desk.step(frame(1, {PadButton::start}));
    CHECK(desk.menu().has_value());
    for (int i = 0; i < 8; ++i) {
        desk.step(frame(2 + double(i) * 0.1, {PadButton::down}));
        desk.step(frame(2.05 + double(i) * 0.1));
    }
    const auto out = desk.step(frame(3, {PadButton::right}));
    CHECK(desk.settings.chordSound == "organ");
    CHECK(out == std::vector<DeskEffect>{DeskEffect::preview("organ", {60, 64, 67})});
    desk.step(frame(4, {PadButton::b}));
    CHECK(!desk.menu().has_value());
}

TEST_CASE("the library browses by category") {
    Desk desk(catalog);
    desk.step(frame(1, {PadButton::start}));
    for (int i = 0; i < 8; ++i) {
        desk.step(frame(2 + double(i) * 0.1, {PadButton::down}));
        desk.step(frame(2.05 + double(i) * 0.1));
    }
    desk.step(frame(3, {PadButton::a}));
    REQUIRE(desk.menu().has_value());
    CHECK(desk.menu()->library == DeskMenu::Library{Line::chord, 0, 0});
    desk.step(frame(4, {PadButton::right}));
    CHECK(desk.settings.chordSound == "soloLead");
    desk.step(frame(5, {PadButton::a}));
    REQUIRE(desk.menu().has_value());
    CHECK(!desk.menu()->library.has_value());
    CHECK(desk.menu().has_value());
}

TEST_CASE("the menu's key row moves by semitones") {
    Desk desk(catalog);
    desk.step(frame(1, {PadButton::start}));
    const std::vector<PadButton> buttons = {PadButton::down, PadButton::down, PadButton::down, PadButton::down,
                                            PadButton::down, PadButton::down, PadButton::down, PadButton::down,
                                            PadButton::down, PadButton::down, PadButton::right};
    for (size_t i = 0; i < buttons.size(); ++i) {
        desk.step(frame(double(i) * 2 + 2, {buttons[i]}));
        desk.step(frame(double(i) * 2 + 3));
    }
    CHECK(desk.settings.key == Key{PitchClass::Cs, ScaleType::major});
}

TEST_CASE("a chord's fit is read against the key") {
    const Key c{PitchClass::C, ScaleType::major};
    CHECK(DeskChord(c, Degree::V, ChordColor::grid(StackHeight::seventh)).fit(c) == ChordFit::inKey);
    CHECK(DeskChord::onRoot(PitchClass::Ds, ChordTones({0, 4, 7}), c).fit(c) == ChordFit::borrowed);
    CHECK(DeskChord(c, Degree::I, ChordColor::tones(ChordTones({0, 4, 5, 7}))).fit(c) == ChordFit::tense);
}

}

TEST_SUITE("The consonance guard") {

TEST_CASE("a degree outside the run is not chosen") {
    Desk desk(SoundCatalog({}));
    desk.settings.consonance.mode = GuardMode::run;
    // Strike C major: the run is C E G.
    desk.step(GamepadFrame{.time = 1, .buttons = {PadButton::a}});
    desk.step(GamepadFrame{.time = 1.1});
    // V, G major, brings B and D, two new notes: the stick leaves I chosen.
    desk.step(GamepadFrame{.time = 2, .left = lean(4 * 360.0 / 7)});
    CHECK(desk.twinRings().degree() == Degree::I);
    // iii, E minor, brings only B.
    desk.step(GamepadFrame{.time = 3, .left = lean(2 * 360.0 / 7)});
    const auto played = desk.step(GamepadFrame{.time = 3.2, .left = Stick::rest(), .buttons = {PadButton::a}});
    CHECK(sounded(played) == std::vector<std::vector<int>>{{64, 67, 71}});
}

TEST_CASE("a strike outside the run is refused and says why") {
    Desk desk(SoundCatalog({}));
    // The run is heard while the guard is off, too.
    desk.step(GamepadFrame{.time = 1, .buttons = {PadButton::a}});
    desk.step(GamepadFrame{.time = 1.1});
    desk.step(GamepadFrame{.time = 2, .left = lean(4 * 360.0 / 7)});
    desk.step(GamepadFrame{.time = 2.1});
    desk.settings.consonance.mode = GuardMode::run;
    const auto refused = desk.step(GamepadFrame{.time = 3, .buttons = {PadButton::a}});
    CHECK(contains(refused, DeskEffect::refuse("G maj is outside the run")));
    CHECK(sounded(refused).empty());
}

}

TEST_SUITE("Favorites") {

TEST_CASE("a key changed turns to its table") {
    const Key g{PitchClass::G, ScaleType::major};
    Desk desk(SoundCatalog({}));
    desk.settings.favorites.addTable("G's");
    desk.settings.favorites.setDefault(g, true);
    desk.settings.favorites.play(0);
    // A tap of RB in Twin Rings moves the key a fifth up, to G.
    desk.step(GamepadFrame{.time = 1, .buttons = {PadButton::rb}});
    desk.step(GamepadFrame{.time = 1.1});
    CHECK(desk.settings.key == g);
    CHECK(desk.settings.favorites.table().name == "G's");
}

}
