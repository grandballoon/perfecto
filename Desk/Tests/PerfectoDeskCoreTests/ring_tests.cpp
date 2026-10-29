// Ported from Tests/DeskCoreTests/RingTests.swift.
//
// Not here: `theStickFindsTheModeWhereTheArrangementPutsIt`,
// `l3TurnsTheRingAndTheKeptColorStays` and `aStickCannotReachAFilteredSector`
// play `TwinRings`, and `petalsDepthFollowsTheArrangement` and
// `petalsStepsByBrightnessWhateverTheOrder` play `Petals`, so they are ported
// with them; `settingsKeptBeforeTheRingWasASettingStillLoad` tests the
// settings' Codable form, which the C++ core has not (persistence is the
// shell's).

#include <doctest.h>

#include "perfecto/desk/music.hpp"
#include "perfecto/desk/ring_pie.hpp"

#include <algorithm>
#include <cmath>
#include <map>
#include <numeric>
#include <optional>
#include <string>
#include <vector>

using namespace perfecto::desk;
using namespace perfecto::theory;

namespace {

const Key c{PitchClass::C, ScaleType::major};
constexpr double span = RingPie::sectorSpan;

std::optional<double> bearing(HeptatonicMode mode, const RingPie &pie) {
    for (const auto &sector : pie.sectors)
        if (sector.mode == mode) return sector.bearing;
    return std::nullopt;
}

int brightness(HeptatonicMode mode) {
    const auto &steps = intervals(mode);
    return std::accumulate(steps.begin(), steps.end(), 0);
}

std::vector<double> bearings(const RingPie &pie) {
    std::vector<double> out;
    for (const auto &sector : pie.sectors) out.push_back(sector.bearing);
    return out;
}

/// Each mode's place, in sectors clockwise from the top.
std::map<HeptatonicMode, int> places(RingOrder order, RingArrangement arrangement = RingArrangement::home,
                                     Degree degree = Degree::I, const std::optional<DeskChord> &near = std::nullopt) {
    const RingPie pie(arrangement, order, RingFilter::all, c, degree, near);
    std::map<HeptatonicMode, int> out;
    for (const auto &sector : pie.sectors)
        out[sector.mode] = static_cast<int>(std::round(sector.bearing / RingPie::sectorSpan));
    return out;
}

std::optional<int> at(const std::map<HeptatonicMode, int> &ring, HeptatonicMode mode) {
    const auto found = ring.find(mode);
    if (found == ring.end()) return std::nullopt;
    return found->second;
}

} // namespace

TEST_SUITE("The ring's arrangements") {

TEST_CASE("home puts the own mode on top and the gap where the ends are") {
    const RingPie pie(RingArrangement::home, c, Degree::I);
    CHECK(bearing(HeptatonicMode::ionian, pie) == 0);
    CHECK(bearing(HeptatonicMode::lydian, pie) == span);
    CHECK(bearing(HeptatonicMode::locrian, pie) == -5 * span);
    // On I the ring is lopsided: one brighter, five darker, the gap on the right.
    CHECK(std::abs(pie.gap() - (180 - 2 * span)) < 0.001);
    CHECK(RingPie(RingArrangement::home, c, Degree::ii).gap() == 180);
}

TEST_CASE("fixed never turns") {
    for (Degree degree : allDegrees) {
        const RingPie pie(RingArrangement::fixed, c, degree);
        CHECK(bearing(HeptatonicMode::dorian, pie) == 0);
        CHECK(pie.gap() == 180);
    }
    const RingPie fixed(RingArrangement::fixed, c, Degree::I);
    const auto own = std::find_if(fixed.sectors.begin(), fixed.sectors.end(), [](const auto &s) { return s.isOwn; });
    REQUIRE(own != fixed.sectors.end());
    CHECK(own->mode == HeptatonicMode::ionian);
    CHECK(bearing(HeptatonicMode::ionian, fixed) == 2 * span);
}

TEST_CASE("centred puts the own mode on top among its nearest in brightness") {
    for (Degree degree : allDegrees) {
        const RingPie pie(RingArrangement::centred, c, degree);
        const auto own = std::find_if(pie.sectors.begin(), pie.sectors.end(), [](const auto &s) { return s.isOwn; });
        REQUIRE(own != pie.sectors.end());
        CHECK(own->bearing == 0);
        std::vector<int> sums;
        for (const auto &sector : pie.sectors) sums.push_back(brightness(sector.mode));
        CHECK(std::is_sorted(sums.begin(), sums.end()));
    }
    // Dorian is in the middle of the brightness order: three either side.
    const RingPie ii(RingArrangement::centred, c, Degree::ii);
    std::vector<double> expected;
    for (int i = -3; i <= 3; ++i) expected.push_back(static_cast<double>(i) * span);
    CHECK(bearings(ii) == expected);
    // I is near the bright end, but is balanced better than at home.
    const RingPie i(RingArrangement::centred, c, Degree::I);
    CHECK(std::count_if(i.sectors.begin(), i.sectors.end(), [](const auto &s) { return s.bearing > 0; }) >= 2);
}

TEST_CASE("a cell plays the same chord whichever way the ring is turned") {
    const RingCell cell{HeptatonicMode::mixolydian, StackHeight::seventh};
    std::vector<std::string> chords;
    for (RingArrangement arrangement : allRingArrangements)
        chords.push_back(DeskChord(c, Degree::I, RingPie(arrangement, c, Degree::I).color(cell)).name());
    CHECK(chords == std::vector<std::string>{"C 7", "C 7", "C 7"});
}

}

TEST_SUITE("The ring's orders and filters") {

TEST_CASE("character puts raised notes clockwise and lowered anticlockwise") {
    const auto ring = places(RingOrder::character);
    CHECK(at(ring, HeptatonicMode::ionian) == 0);
    CHECK((at(ring, HeptatonicMode::dorian) == 1 && at(ring, HeptatonicMode::lydian) == 2));
    CHECK((at(ring, HeptatonicMode::aeolian) == -1 && at(ring, HeptatonicMode::mixolydian) == -2 &&
           at(ring, HeptatonicMode::phrygian) == -3 && at(ring, HeptatonicMode::locrian) == -4));
}

TEST_CASE("quality puts major thirds on one side and minor on the other") {
    const RingPie pie(RingArrangement::fixed, RingOrder::quality, RingFilter::all, c, Degree::I);
    for (const auto &sector : pie.sectors) {
        const auto &steps = intervals(sector.mode);
        const auto has = [&](int interval) { return std::find(steps.begin(), steps.end(), interval) != steps.end(); };
        if (has(4)) CHECK(sector.bearing > 0);
        if (has(3) && has(7)) CHECK(sector.bearing < 0);
    }
    // Each side's brightest is by the seam at the top.
    const auto top = std::min_element(pie.sectors.begin(), pie.sectors.end(), [](const auto &a, const auto &b) {
        return std::abs(a.bearing) < std::abs(b.bearing);
    });
    CHECK((top->mode == HeptatonicMode::dorian || top->mode == HeptatonicMode::lydian));
}

TEST_CASE("fewest borrowed fans out from the key's own") {
    const auto ring = places(RingOrder::borrowed);
    CHECK(at(ring, HeptatonicMode::ionian) == 0);
    // One note borrowed either side, the brighter clockwise.
    CHECK((at(ring, HeptatonicMode::lydian) == 1 && at(ring, HeptatonicMode::mixolydian) == -1));
    CHECK((at(ring, HeptatonicMode::dorian) == 2 && at(ring, HeptatonicMode::aeolian) == -2));
    CHECK((at(ring, HeptatonicMode::phrygian) == 3 && at(ring, HeptatonicMode::locrian) == -3));
}

TEST_CASE("common first keeps Ionian on top when fixed") {
    for (Degree degree : allDegrees)
        CHECK(at(places(RingOrder::common, RingArrangement::fixed, degree), HeptatonicMode::ionian) == 0);
    // At home, the degree's own mode is on top.
    CHECK(at(places(RingOrder::common, RingArrangement::home, Degree::ii), HeptatonicMode::dorian) == 0);
}

TEST_CASE("nearest turns to the chord struck") {
    const DeskChord seventh(c, Degree::I, ChordColor::grid(StackHeight::seventh, HeptatonicMode::mixolydian));
    CHECK(at(places(RingOrder::nearness, RingArrangement::home, Degree::I, seventh), HeptatonicMode::mixolydian) == 0);
    CHECK(at(places(RingOrder::nearness), HeptatonicMode::ionian) == 0);
}

TEST_CASE("a filter leaves cells in place but out of reach") {
    const RingPie pie(RingArrangement::home, RingOrder::brightness, RingFilter::inKey, c, Degree::I);
    CHECK(pie.allows(RingCell{HeptatonicMode::lydian, StackHeight::seventh}));
    CHECK(!pie.allows(RingCell{HeptatonicMode::lydian, StackHeight::eleventh}));
    CHECK(!pie.allows(RingCell{HeptatonicMode::mixolydian, StackHeight::seventh}));
    std::vector<HeptatonicMode> reachable;
    for (int sector : pie.gate(false).sectors) reachable.push_back(pie.sectors[static_cast<size_t>(sector)].mode);
    CHECK(reachable == std::vector<HeptatonicMode>{HeptatonicMode::ionian, HeptatonicMode::lydian});
    // The sectors keep their places.
    CHECK(bearings(pie) == bearings(RingPie(RingArrangement::home, c, Degree::I)));
    // Dorian, Aeolian, Phrygian and Locrian have a minor third.
    CHECK(RingPie(RingArrangement::home, RingOrder::brightness, RingFilter::minorThird, c, Degree::I)
              .gate(false)
              .sectors.size() == 4);
}

}
