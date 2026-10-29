// Ported from Tests/DeskCoreTests/FavoritesTests.swift.
//
// Not here: `yAPinsAndYHeldPlaysTheFavorites`, `aTapOfYStillHolds` and
// `yXUnpinsTheFavoriteAimedAt` play `TwinRings`, and `aKeyChangedTurnsToItsTable`
// plays `Desk`, so they are ported with them; `favoritesAreKeptWithTheSettings`
// tests the settings' Codable form, which the C++ core has not (persistence is
// the shell's).

#include <doctest.h>

#include "perfecto/desk/favorites.hpp"
#include "perfecto/desk/music.hpp"

#include <optional>
#include <string>
#include <vector>

using namespace perfecto::desk;
using namespace perfecto::theory;

namespace {

const Key c{PitchClass::C, ScaleType::major};
const Key g{PitchClass::G, ScaleType::major};

std::vector<std::string> names(const Favorites &favorites) {
    std::vector<std::string> out;
    for (const auto &table : favorites.tables()) out.push_back(table.name);
    return out;
}

} // namespace

TEST_SUITE("Favorites") {

TEST_CASE("a pin is kept by key and chord") {
    Favorites favorites;
    const DeskChord seventh(c, Degree::V, ChordColor::grid(StackHeight::seventh, std::nullopt));
    const bool pinned1 = favorites.pin(seventh, c);
    CHECK(pinned1);
    // The same color again, or another key's, is not the same pin.
    const bool pinned2 = favorites.pin(seventh, c);
    CHECK(!pinned2);
    CHECK(favorites.colors(c, Degree::V) ==
          std::vector<ChordColor>{ChordColor::grid(StackHeight::seventh, std::nullopt)});
    CHECK(favorites.colors(g, Degree::V).empty());
    favorites.unpin(c, Degree::V, 0);
    CHECK(favorites.colors(c, Degree::V).empty());
    CHECK(favorites.table().pins.empty());
}

TEST_CASE("a borrowed chord is pinned by its tones") {
    Favorites favorites;
    // E♭ major, borrowed into C, has no degree there: it cannot be pinned.
    const bool pinned3 = favorites.pin(DeskChord::onRoot(PitchClass::Ds, ChordTones({0, 4, 7}), c), c);
    CHECK(!pinned3);
    // C minor on I is pinned to I by its notes.
    const DeskChord minor = DeskChord::onRoot(PitchClass::C, ChordTones({0, 3, 7}), c);
    const bool pinned4 = favorites.pin(minor, c);
    CHECK(pinned4);
    CHECK(DeskChord(c, Degree::I, favorites.colors(c, Degree::I)[0]).name() == "C min");
}

TEST_CASE("a chord holds eight at most") {
    Favorites favorites;
    const std::vector<StackHeight> heights = {StackHeight::triad, StackHeight::seventh, StackHeight::ninth,
                                              StackHeight::eleventh, StackHeight::thirteenth};
    const std::vector<std::optional<HeptatonicMode>> modes = {std::nullopt, HeptatonicMode::lydian};
    for (StackHeight height : heights)
        for (const auto &mode : modes) favorites.pin(DeskChord(c, Degree::I, ChordColor::grid(height, mode)), c);
    CHECK(static_cast<int>(favorites.colors(c, Degree::I).size()) == Favorites::perChord);
}

TEST_CASE("tables are named and one is played") {
    Favorites favorites;
    favorites.pin(DeskChord(c, Degree::I, ChordColor::grid(StackHeight::seventh, std::nullopt)), c);
    favorites.addTable("Jazz");
    favorites.addTable("Jazz");
    CHECK(names(favorites) == std::vector<std::string>{"Favorites", "Jazz", "Jazz 2"});
    CHECK(favorites.table().name == "Jazz 2");
    CHECK(favorites.colors(c, Degree::I).empty());
    favorites.play(0);
    CHECK(favorites.colors(c, Degree::I).size() == 1);
    favorites.removeTable(0);
    CHECK(names(favorites) == std::vector<std::string>{"Jazz", "Jazz 2"});
    favorites.removeTable(0);
    favorites.removeTable(0);
    CHECK(favorites.tables().size() == 1);
}

TEST_CASE("a key can have a table of its own") {
    Favorites favorites;
    favorites.addTable("Bright");
    favorites.setDefault(g, true);
    favorites.play(0);
    favorites.keyChanged(c);
    CHECK(favorites.table().name == "Favorites");
    favorites.keyChanged(g);
    CHECK(favorites.table().name == "Bright");
    favorites.rename(1, "Sunny");
    CHECK(favorites.defaultTable(g) == "Sunny");
}

}
