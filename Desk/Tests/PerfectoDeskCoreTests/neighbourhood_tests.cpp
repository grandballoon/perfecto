// Ported from Tests/DeskCoreTests/LayoutTests.swift ("Neighbourhood").

#include <doctest.h>

#include "perfecto/desk/music.hpp"
#include "perfecto/desk/neighbourhood.hpp"
#include "rig.hpp"

#include <optional>
#include <string>
#include <vector>

using namespace perfecto::desk;
using namespace perfecto::desk::testing;

namespace {

using Names = std::vector<std::optional<std::string>>;

Names neighbourNames(const Rig<Neighbourhood> &rig) {
    Names names;
    for (const auto &neighbour : rig.layout.neighbours(rig.settings))
        names.push_back(neighbour ? std::optional<std::string>(neighbour->chord.name()) : std::nullopt);
    return names;
}

} // namespace

TEST_SUITE("Neighbourhood") {

TEST_CASE("the Tonnetz lens has the flips") {
    Rig rig(Neighbourhood{});
    rig.at(1, [](GamepadFrame &f) { f.buttons = {PadButton::rb}; });
    CHECK(rig.layout.lens() == Neighbourhood::Lens::tonnetz);
    CHECK(neighbourNames(rig) == Names{"C min", "A min", "G maj", "D# maj", "F min", "G# maj", "F maj", "E min"});
}

TEST_CASE("a flick moves and strikes") {
    Rig rig(Neighbourhood{});
    rig.at(1);
    // Up, in the color lens: the 7th added.
    rig.at(2, [](GamepadFrame &f) { f.right = lean(0); });
    const auto out = rig.at(2.1, [](GamepadFrame &f) { f.right = Stick::rest(); });
    CHECK(rig.layout.centre().name() == "C maj7");
    CHECK(sounded(out) == std::vector<std::vector<int>>{{60, 64, 67, 71}});
    std::vector<std::string> path;
    for (const DeskChord &chord : rig.layout.path()) path.push_back(chord.name());
    CHECK(path == std::vector<std::string>{"C maj", "C maj7"});
}

TEST_CASE("a hold listens and comes back") {
    Rig rig(Neighbourhood{});
    rig.at(1, [](GamepadFrame &f) { f.buttons = {PadButton::a}; });
    rig.at(2, [](GamepadFrame &f) { f.right = lean(0); });
    rig.at(2.5, [](GamepadFrame &f) { f.right = lean(0); });
    const auto out = rig.at(2.6, [](GamepadFrame &f) { f.right = Stick::rest(); });
    CHECK(rig.layout.centre().name() == "C maj");
    CHECK(sounded(out) == std::vector<std::vector<int>>{{60, 64, 67}});
}

TEST_CASE("the left stick walks the path") {
    Rig rig(Neighbourhood{});
    rig.at(1);
    rig.at(2, [](GamepadFrame &f) { f.right = lean(0); });
    rig.at(2.1, [](GamepadFrame &f) { f.right = Stick::rest(); });
    rig.at(3, [](GamepadFrame &f) { f.left = lean(270); });
    CHECK(rig.layout.centre().name() == "C maj");
    rig.at(3.5, [](GamepadFrame &f) { f.left = Stick::rest(); });
    rig.at(4, [](GamepadFrame &f) { f.left = lean(90); });
    CHECK(rig.layout.centre().name() == "C maj7");
}

TEST_CASE("degrees share notes with their neighbours") {
    Rig rig(Neighbourhood{});
    rig.at(1, [](GamepadFrame &f) { f.buttons = {PadButton::lb}; });
    CHECK(rig.layout.lens() == Neighbourhood::Lens::degrees);
    CHECK(neighbourNames(rig) == Names{std::nullopt, "G maj", "E min", "B dim", std::nullopt, "D min", "A min", "F maj"});
}

}
