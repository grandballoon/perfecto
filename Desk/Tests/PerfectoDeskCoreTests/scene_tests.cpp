// What the screen shows, and what the mouse does: `scene` and `perform`.

#include <doctest.h>

#include "perfecto/desk/inputs.hpp"
#include "perfecto/desk/ring_pie.hpp"
#include "perfecto/desk/scene.hpp"

#include <algorithm>

using namespace perfecto::desk;
using namespace perfecto::theory;

namespace {

const SoundCatalog catalog({
    {"Keys", {{"electricPiano", "Electric Piano"}, {"organ", "Organ"}}},
    {"Synth", {{"soloLead", "Solo Lead"}}},
});

GamepadFrame frame(double time, std::set<PadButton> buttons = {}) {
    return GamepadFrame{.time = time, .buttons = std::move(buttons)};
}

/// The items of `panel` that are a `T`.
template <class T> std::vector<T> items(const Panel &panel) {
    std::vector<T> out;
    for (const auto &item : panel.items)
        if (const auto *found = std::get_if<T>(&item)) out.push_back(*found);
    return out;
}

const Hand::Entry *entry(const std::vector<Hand::Entry> &entries, const std::string &mark) {
    const auto found = std::find_if(entries.begin(), entries.end(), [&](const auto &e) { return e.mark == mark; });
    return found == entries.end() ? nullptr : &*found;
}

} // namespace

TEST_SUITE("Scene") {

TEST_CASE("the top bar names the layouts and what the desk is set to") {
    const Desk desk(catalog);
    const auto top = scene(desk, false).top;
    CHECK(top.layouts.size() == allLayoutKinds.size());
    CHECK(top.layouts[0] == "Face Chords");
    CHECK(top.layouts[1] == "Twin Rings");
    CHECK(top.chosen == 1);
    CHECK(top.summary == summary(LayoutKind::twinRings));
    CHECK_FALSE(top.guard.has_value());
    CHECK(top.facts[0] == std::pair<std::string, std::string>{"Key", "C Major"});
    CHECK(top.facts[2] == std::pair<std::string, std::string>{"Chords", "Electric Piano"});
    CHECK(top.facts[3] == std::pair<std::string, std::string>{"Line", "Solo Lead"});
}

TEST_CASE("the guard's chip shows its mode, and in the run what it has heard") {
    DeskSettings settings;
    settings.consonance.mode = GuardMode::run;
    const Desk desk(catalog, settings);
    const auto guard = scene(desk, false).top.guard;
    REQUIRE(guard.has_value());
    CHECK(guard->first == name(GuardMode::run));
    CHECK(guard->second == "nothing heard yet");
}

TEST_CASE("Twin rings shows the degree pie, and the color ring with its arrangements") {
    const Desk desk(catalog);
    const auto stage = scene(desk, false).stage;
    REQUIRE(stage.size() == 2);
    const auto pies = items<Pie>(stage[0]);
    REQUIRE(pies.size() == 1);
    CHECK(pies[0].title == "I");
    CHECK(pies[0].detail == "C Major");
    CHECK(pies[0].targets.size() == 7);
    const auto rings = items<Ring>(stage[1]);
    REQUIRE(rings.size() == 1);
    CHECK(rings[0].bands.size() == 3);
    CHECK(rings[0].sectors.size() == 7);
    CHECK(rings[0].detail == "plain");
    const auto choices = items<Choices>(stage[1]);
    REQUIRE(choices.size() == 1);
    CHECK(choices[0].names.size() == allRingArrangements.size());
    CHECK(choices[0].action == Action::Kind::arrangeRing);
    CHECK(items<Sounding>(stage[1]).at(0) == Sounding{false, "Strike with RT or A", ""});
}

TEST_CASE("a chord struck is named under the stage") {
    Desk desk(catalog);
    desk.step(frame(1));
    desk.step(frame(2, {PadButton::a}));
    const auto sounding = items<Sounding>(scene(desk, false).stage[1]).at(0);
    CHECK(sounding.isSounding);
    CHECK(sounding.text == desk.twinRings().line().chord()->name());
}

TEST_CASE("the hand lists what each control does, lit while it is held") {
    Desk desk(catalog);
    desk.step(frame(1, {PadButton::a}));
    const auto hand = scene(desk, false).hand;
    CHECK(hand.caption == "Controller");
    const auto *a = entry(hand.right, "A");
    REQUIRE(a != nullptr);
    CHECK(a->isHeld);
    CHECK(a->tint == Tint::a);
    CHECK(a->key.empty());
    const auto *stick = entry(hand.left, "LS");
    REQUIRE(stick != nullptr);
    CHECK_FALSE(stick->isHeld);
}

TEST_CASE("with the keyboard playing, each control shows its key") {
    const Desk desk(catalog);
    const auto hand = scene(desk, true).hand;
    CHECK(hand.caption == "Keyboard");
    CHECK(entry(hand.right, "A")->key == KeyboardPad::key(PadControl::button(PadButton::a)));
}

TEST_CASE("the menu lists every row, the one chosen lit") {
    Desk desk(catalog);
    CHECK_FALSE(scene(desk, false).menu.has_value());
    perform(desk, {Action::Kind::toggleMenu});
    const auto menu = scene(desk, false).menu;
    REQUIRE(menu.has_value());
    REQUIRE(menu->rows.size() == DeskMenu::allRows.size());
    CHECK(menu->rows[0] == MenuView::Row{"Layout", "Twin Rings", true, true});
    CHECK_FALSE(menu->rows.back().changes);
    CHECK_FALSE(menu->library.has_value());
}

TEST_CASE("a click chooses a layout, and one out of range does nothing") {
    Desk desk(catalog);
    perform(desk, {Action::Kind::chooseLayout, 2});
    CHECK(desk.layout() == LayoutKind::petals);
    const auto stage = scene(desk, false).stage;
    REQUIRE(items<Diamond>(stage[1]).size() == 1);
    CHECK(items<Diamond>(stage[1])[0].petals.size() == 4);
    perform(desk, {Action::Kind::chooseLayout, 9});
    CHECK(desk.layout() == LayoutKind::petals);
}

TEST_CASE("a click lays the ring another way") {
    Desk desk(catalog);
    perform(desk, {Action::Kind::arrangeRing, 1});
    CHECK(desk.settings.ringArrangement == RingArrangement::fixed);
    CHECK(items<Choices>(scene(desk, false).stage[1]).at(0).chosen == 1);
}

TEST_CASE("the favorites' tables are added, named, played and removed by the mouse") {
    Desk desk(catalog);
    CHECK_FALSE(scene(desk, false).favorites.canRemove);
    perform(desk, {Action::Kind::addTable});
    perform(desk, {.kind = Action::Kind::renameTable, .index = 1, .text = "Jazz"});
    perform(desk, {Action::Kind::playTable, 1});
    auto favorites = scene(desk, false).favorites;
    REQUIRE(favorites.tables.size() == 2);
    CHECK(favorites.tables[1] == FavoritesView::Table{"Jazz", true, false, 0});
    CHECK(favorites.canRemove);
    CHECK(favorites.pinnedTitle == "Pinned in Jazz");
    perform(desk, {.kind = Action::Kind::setKeyDefault, .value = 1});
    CHECK(scene(desk, false).favorites.isKeyDefault);
    perform(desk, {Action::Kind::removeTable});
    CHECK(scene(desk, false).favorites.tables.size() == 1);
}

TEST_CASE("the chord sounding is pinned by the mouse, and unpinned") {
    Desk desk(catalog);
    desk.step(frame(1));
    desk.step(frame(2, {PadButton::a}));
    auto favorites = scene(desk, false).favorites;
    CHECK(favorites.canPin);
    perform(desk, {Action::Kind::pinPlayed});
    favorites = scene(desk, false).favorites;
    CHECK(favorites.degrees[0].numeral == "I");
    CHECK(favorites.degrees[0].pinned.size() == 1);
    perform(desk, {Action::Kind::unpin, 0, 0});
    CHECK(scene(desk, false).favorites.degrees[0].pinned.empty());
}

TEST_CASE("the arranger's lanes are four bars, the grid in each, the cursor at the start") {
    Desk desk(catalog);
    perform(desk, {Action::Kind::chooseLayout, 5});
    const auto stage = scene(desk, false).stage;
    const auto lanes = items<Lanes>(stage[0]).at(0).lanes;
    REQUIRE(lanes.size() == 4);
    CHECK(lanes[0].number == 1);
    CHECK(lanes[0].lines.size() == 16);
    CHECK(lanes[0].lines[4] == Lanes::GridLine{0.25, true});
    CHECK(lanes[0].lines[1] == Lanes::GridLine{0.0625, false});
    CHECK(lanes[0].cursor == 0.0);
    CHECK_FALSE(lanes[1].cursor.has_value());
    CHECK(items<Facts>(stage[0]).at(0).facts[1].second == "bar 1 · beat 1");
    CHECK(items<Pies>(stage[1]).at(0).pies.size() == 2);
}

TEST_CASE("every layout but Face Chords has a stage of two panels") {
    for (size_t i = 0; i < allLayoutKinds.size(); ++i) {
        Desk desk(catalog);
        perform(desk, {Action::Kind::chooseLayout, static_cast<int>(i)});
        CHECK(scene(desk, false).stage.size() == (allLayoutKinds[i] == LayoutKind::faceChords ? 1u : 2u));
    }
}

TEST_CASE("Face Chords shows each button's chord by number and name, and the chord sounding") {
    Desk desk(catalog, DeskSettings(), LayoutKind::faceChords);
    auto faces = items<Faces>(scene(desk, false).stage.at(0)).at(0);
    REQUIRE(faces.faces.size() == 4);
    CHECK(faces.faces[0] == Faces::Face{PadButton::a, 180, "I", "C maj", "", false, false});
    CHECK(faces.faces[3] == Faces::Face{PadButton::b, 90, "IV", "F maj", "+LT ii", false, false});
    CHECK(faces.numeral.empty());
    CHECK(faces.detail == "Hold a face button");
    desk.step(frame(1, {PadButton::b}));
    desk.step(GamepadFrame{.time = 2, .leftTrigger = 1, .buttons = {PadButton::b}});
    const auto scene = perfecto::desk::scene(desk, false);
    faces = items<Faces>(scene.stage.at(0)).at(0);
    CHECK(faces.faces[3] == Faces::Face{PadButton::b, 90, "ii", "D min", "−LT IV", true, true});
    CHECK(faces.numeral == "ii");
    CHECK(faces.name == "D min");
    CHECK(items<Caption>(scene.stage.at(0)).at(0).title == "LT held");
}

}
