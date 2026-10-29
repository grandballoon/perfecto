// Ported from Tests/DeskCoreTests/VoiceLeadingTests.swift: the suite
// "Voice leading". Its other suite, "Twin rings' voices", plays `TwinRings`
// and is ported with it.

#include <doctest.h>

#include "perfecto/desk/music.hpp"
#include "perfecto/desk/voice_leading.hpp"

#include <optional>
#include <string>
#include <vector>

using namespace perfecto::desk;
using namespace perfecto::theory;

namespace {

const Key c{PitchClass::C, ScaleType::major};
const std::vector<int> cMajor = {60, 64, 67};

std::optional<std::string> name(const std::vector<int> &notes, int direction, int shell = 1) {
    const auto chord = VoiceLeading::neighbour(notes, VoiceMove{direction, shell}, c);
    if (!chord) return std::nullopt;
    return chord->name();
}

using Notes = std::optional<std::vector<int>>;

} // namespace

TEST_SUITE("Voice leading") {

TEST_CASE("each direction is one exact motion") {
    // Up: the top voice a semitone up, G to G♯.
    CHECK(VoiceLeading::moved(cMajor, VoiceMove{0, 1}) == Notes({60, 64, 68}));
    // Right: the middle voice up, E to F.
    CHECK(VoiceLeading::moved(cMajor, VoiceMove{2, 1}) == Notes({60, 65, 67}));
    // Upper left: the two apart, the top up and the middle down.
    CHECK(VoiceLeading::moved(cMajor, VoiceMove{7, 1}) == Notes({60, 63, 68}));
    // The outer shell moves each voice two semitones.
    CHECK(VoiceLeading::moved(cMajor, VoiceMove{1, 2}) == Notes({60, 66, 69}));
}

TEST_CASE("the neighbours are the consonant chords only") {
    CHECK(name(cMajor, 0) == "C aug");
    CHECK(name(cMajor, 2) == "C sus4");
    CHECK(name(cMajor, 6) == "C min");
    CHECK(name(cMajor, 0, 2) == "A min/C");
    // The top voice down a semitone makes C E F♯: not consonant.
    CHECK(name(cMajor, 4) == std::nullopt);
}

TEST_CASE("the bass moves too and the root may move") {
    const auto down = VoiceLeading::bassNeighbour(cMajor, VoiceMove{1, 1}, c);
    REQUIRE(down);
    CHECK(down->name() == "E min/B");
    CHECK(down->notes(DeskSettings()) == std::vector<int>{59, 64, 67});
}

TEST_CASE("voices never cross or meet") {
    CHECK(VoiceLeading::moved({60, 64, 65}, VoiceMove{4, 1}) == std::nullopt);
    CHECK(VoiceLeading::moved({60, 64, 66}, VoiceMove{4, 2}) == std::nullopt);
}

TEST_CASE("a chord is read from its bass when it can be") {
    const auto name = [](const std::vector<int> &notes) -> std::optional<std::string> {
        const auto chord = VoiceLeading::chord(notes, c);
        if (!chord) return std::nullopt;
        return chord->name();
    };
    CHECK(name({64, 67, 72}) == "C maj/E");
    CHECK(name({60, 64, 67, 70}) == "C 7");
    CHECK(VoiceLeading::chord({60, 61, 62}, c) == std::nullopt);
}

}
