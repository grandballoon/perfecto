// The drum kits' recordings: each the same every time, as long and as loud
// as it says, starting and ending quietly, and pitched where its drum is;
// and the kits each the character they are named for.

#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include <doctest.h>

#include "perfecto/drumkit/kit.hpp"

#include <algorithm>
#include <cmath>
#include <set>

using namespace perfecto::drumkit;

namespace {

constexpr double rate = 48000;

double loudest(const std::vector<float> &samples, size_t from, size_t to) {
    double most = 0;
    for (size_t i = from; i < std::min(to, samples.size()); ++i) most = std::max(most, double(std::abs(samples[i])));
    return most;
}

/// How often it crosses zero in its first `seconds`, a second: low for a
/// drum's thud, high for a cymbal's hiss.
double crossings(const std::vector<float> &samples, double seconds) {
    const size_t frames = std::min(samples.size(), size_t(seconds * rate));
    int count = 0;
    for (size_t i = 1; i < frames; ++i)
        if ((samples[i - 1] < 0) != (samples[i] < 0)) ++count;
    return count / seconds;
}

/// How loud it still is a tenth of a second on, against its strike: low
/// for a drum that is over fast, high for one held up.
double held(const std::vector<float> &samples) {
    return loudest(samples, size_t(0.08 * rate), size_t(0.12 * rate)) / loudest(samples, 0, samples.size());
}

const Kit &kit(const std::string &name) {
    return *std::find_if(kits().begin(), kits().end(), [&](const Kit &kit) { return kit.name == name; });
}

} // namespace

TEST_SUITE("Drum kits") {

TEST_CASE("there are eight kits, each named once") {
    std::set<std::string> names;
    for (const Kit &kit : kits()) names.insert(kit.name);
    CHECK(kits().size() == 8);
    CHECK(names == std::set<std::string>{"Analog", "Punch", "Glue", "Harsh", "Lo-fi", "FM", "Room", "Tight"});
    CHECK(kits().front().name == "Analog");
}

TEST_CASE("each piece is the same every time it is rendered") {
    for (const Kit &kit : kits())
        for (const Piece piece : allPieces) CHECK(render(kit, piece, rate) == render(kit, piece, rate));
}

TEST_CASE("each piece is as long and as loud as it says, and nothing is out of range") {
    for (const Kit &kit : kits())
        for (const Piece piece : allPieces) {
            const auto samples = render(kit, piece, rate);
            CAPTURE(kit.name);
            CAPTURE(name(piece));
            CHECK(samples.size() == size_t(std::ceil(length(kit, piece) * rate)));
            CHECK(length(kit, piece) <= 2.0);
            CHECK(loudest(samples, 0, samples.size()) == doctest::Approx(peak(piece)).epsilon(1e-6));
            CHECK(std::all_of(samples.begin(), samples.end(), [](float x) { return std::isfinite(x); }));
        }
}

TEST_CASE("each piece starts without a step, strikes at once and dies away to nothing") {
    for (const Kit &kit : kits())
        for (const Piece piece : allPieces) {
            const auto samples = render(kit, piece, rate);
            CAPTURE(kit.name);
            CAPTURE(name(piece));
            CHECK(std::abs(samples.front()) < 0.05);
            CHECK(samples.back() == 0);
            // Its last tenth of a second is far quieter than its strike.
            CHECK(loudest(samples, samples.size() - size_t(0.1 * rate), samples.size()) < 0.1 * peak(piece));
            // It is struck at once: within its first 60 ms it is about as
            // loud as it ever is (a kit that folds or rings may match it
            // later, never pass it by much).
            CHECK(loudest(samples, 0, size_t(0.06 * rate)) > 0.9 * peak(piece));
        }
}

TEST_CASE("in every kit the kick is lowest, the hats highest, and the toms rise") {
    for (const Kit &kit : kits()) {
        CAPTURE(kit.name);
        const auto pitch = [&](Piece piece) { return crossings(render(kit, piece, rate), 0.08); };
        const double kick = pitch(Piece::kick), snare = pitch(Piece::snare), clap = pitch(Piece::clap);
        const double closed = pitch(Piece::closedHat), open = pitch(Piece::openHat);
        CHECK(kick < snare);
        CHECK(kick < clap);
        CHECK(snare < closed);
        CHECK(clap < closed);
        CHECK(snare < open);
        CHECK(pitch(Piece::lowTom) < pitch(Piece::midTom));
        CHECK(pitch(Piece::midTom) < pitch(Piece::highTom));
    }
}

TEST_CASE("the open hat rings longer than the closed one, in every kit") {
    for (const Kit &kit : kits()) CHECK(length(kit, Piece::openHat) > length(kit, Piece::closedHat));
}

TEST_CASE("no two kits sound alike") {
    for (const Piece piece : allPieces)
        for (size_t i = 0; i < kits().size(); ++i)
            for (size_t j = i + 1; j < kits().size(); ++j) {
                CAPTURE(name(piece));
                CHECK(render(kits()[i], piece, rate) != render(kits()[j], piece, rate));
            }
}

TEST_CASE("Glue is held up under its strikes, more than Punch") {
    for (const Piece piece : {Piece::snare, Piece::clap, Piece::lowTom, Piece::highTom}) {
        CAPTURE(name(piece));
        CHECK(held(render(kit("Glue"), piece, rate)) > 1.1 * held(render(kit("Punch"), piece, rate)));
    }
    CHECK(held(render(kit("Glue"), Piece::closedHat, rate)) > 2 * held(render(kit("Punch"), Piece::closedHat, rate)));
}

TEST_CASE("Harsh is brighter than Analog") {
    for (const Piece piece : {Piece::kick, Piece::snare, Piece::lowTom}) {
        CAPTURE(name(piece));
        CHECK(crossings(render(kit("Harsh"), piece, rate), 0.1) > 1.5 * crossings(render(kit("Analog"), piece, rate), 0.1));
    }
}

TEST_CASE("Lo-fi is sampled at few bits and a low rate") {
    const auto samples = render(kit("Lo-fi"), Piece::snare, rate);
    // Before the fade, it holds each of few levels three or four frames.
    const std::vector<float> held(samples.begin(), samples.end() - size_t(0.03 * rate));
    CHECK(std::set<float>(held.begin(), held.end()).size() <= 1025);
    int changes = 0;
    for (size_t i = 1; i < held.size(); ++i) changes += held[i] != held[i - 1];
    CHECK(changes < held.size() * 14000 / rate + 1);
}

TEST_CASE("Room rings on after its drums, and Tight is over first") {
    for (const Piece piece : allPieces) {
        CAPTURE(name(piece));
        CHECK(length(kit("Room"), piece) > length(kit("Tight"), piece));
        for (const Kit &kit : kits()) CHECK(length(kit, piece) >= length(::kit("Tight"), piece));
    }
    // A tenth of a second after its snare is struck, the room is still loud.
    const auto room = render(kit("Room"), Piece::snare, rate), tight = render(kit("Tight"), Piece::snare, rate);
    CHECK(loudest(room, size_t(0.3 * rate), size_t(0.4 * rate)) > 0.05);
    CHECK(tight.size() < size_t(0.4 * rate));
}

TEST_CASE("at another rate a piece lasts as long") {
    for (const Kit &kit : kits())
        for (const Piece piece : allPieces)
            CHECK(render(kit, piece, 44100).size() == size_t(std::ceil(length(kit, piece) * 44100)));
}

} // TEST_SUITE
