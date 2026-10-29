// Ported from Tests/MusicTheoryCoreTests/ChordWireTests.swift.

#include <doctest.h>

#include "perfecto/theory/chord_wire.hpp"

#include <algorithm>
#include <cstdint>
#include <set>
#include <vector>

using namespace perfecto::theory;

namespace {

using Bytes = std::vector<std::uint8_t>;

ChordAnnouncement announcement() {
    return ChordAnnouncement{
        Key{PitchClass::C, ScaleType::major},
        Degree::I,
        JoystickMode::default_,
        JoystickDirection::right,
        Inversion::root(),
        4,
        false,
        Voicing({60, 64, 67, 71}),
    };
}

const Key cMajor{PitchClass::C, ScaleType::major};
const ChordSpec triad{Degree::I, ChordColor::joystick(JoystickMode::default_, JoystickDirection::center)};

bool decodesTo(const Bytes &bytes, const ChordWire::Frame &frame) {
    const auto decoded = ChordWire::decode(bytes);
    return decoded.has_value() && *decoded == frame;
}

template <class T, std::size_t N> bool coversEveryCase(const std::array<T, N> &table, std::size_t caseCount) {
    const std::set<T> unique(table.begin(), table.end());
    return table.size() == unique.size() && unique.size() == caseCount;
}

} // namespace

TEST_SUITE("ChordWire") {

// MARK: – Golden frames (shared with Harmonicland's chordwire.test.ts —
// if these bytes change, the protocol version must bump)

TEST_CASE("golden chord frame, C major I, maj7") {
    CHECK(ChordWire::encodeChord(announcement()) == Bytes{
        0xF0, 0x7D, 0x50, 0x46, 0x01,   // header: SysEx, non-commercial, 'P', 'F', v1
        0x01,                           // type: chord
        0, 0, 1, 0, 3, 0, 4, 0,         // C, major, I, default, right, root, octave 4, no VL
        0, 0,                           // no bass note
        4, 60, 64, 67, 71,              // Cmaj7 voicing
        0xF7,
    });
}

TEST_CASE("golden release frame") {
    CHECK(ChordWire::encodeRelease() == Bytes{0xF0, 0x7D, 0x50, 0x46, 0x01, 0x02, 0xF7});
}

// MARK: – Round-trips

TEST_CASE("chord round trip") {
    CHECK(decodesTo(ChordWire::encodeChord(announcement()), announcement()));
}

TEST_CASE("release round trip") {
    CHECK(decodesTo(ChordWire::encodeRelease(), ChordWire::Release{}));
}

TEST_CASE("round trip covers every scale, mode, direction and inversion") {
    for (ScaleType scale : allScaleTypes) {
        for (JoystickMode mode : ChordWire::modeOrder) {
            for (JoystickDirection direction : ChordWire::directionOrder) {
                for (Inversion inversion : ChordWire::inversionOrder) {
                    const ChordAnnouncement a{
                        Key{PitchClass::Fs, scale},
                        Degree::V,
                        mode,
                        direction,
                        inversion,
                        3,
                        true,
                        Voicing({54, 58, 61}, 42),
                    };
                    CHECK(decodesTo(ChordWire::encodeChord(a), a));
                }
            }
        }
    }
}

TEST_CASE("bass note survives round trip") {
    const ChordAnnouncement a{
        Key{PitchClass::A, ScaleType::naturalMinor},
        Degree::iii,
        JoystickMode::extended,
        JoystickDirection::downLeft,
        Inversion::second(),
        5,
        true,
        Voicing({72, 76, 79}, 45),
    };
    CHECK(decodesTo(ChordWire::encodeChord(a), a));
}

// MARK: – Inversions a frame cannot state

TEST_CASE("an inversion a frame has is stated as it is") {
    for (Inversion inversion : ChordWire::inversionOrder) {
        const auto stated = ChordWire::stated(inversion, 4, cMajor, triad);
        REQUIRE(stated.has_value());
        CHECK(stated->inversion == inversion);
        CHECK(stated->octave == 4);
    }
}

/// A chord rolled past the second inversion, or down, is stated as the
/// inversion and octave that have the same notes.
TEST_CASE("a chord rolled further is stated by the same notes in another octave") {
    for (int steps : {-4, -1, 3, 5, 8}) {
        const Inversion rolled{steps};
        const auto stated = ChordWire::stated(rolled, 4, cMajor, triad);
        if (!stated) {
            FAIL_CHECK(steps, " steps was not stated");
            continue;
        }
        const auto &order = ChordWire::inversionOrder;
        CHECK(std::find(order.begin(), order.end(), stated->inversion) != order.end());
        auto notes = [](Inversion inversion, int octave) {
            return computeVoicing(cMajor, triad, inversion, octave, false, std::nullopt).notes();
        };
        CHECK(notes(stated->inversion, stated->octave) == notes(rolled, 4));
    }
    const auto down = ChordWire::stated(Inversion{-1}, 4, cMajor, triad);
    REQUIRE(down.has_value());
    CHECK(down->inversion == Inversion::second());
    CHECK(down->octave == 3);
}

/// A four-note chord's third inversion is none of the three a frame has.
TEST_CASE("a third inversion cannot be stated") {
    const ChordSpec maj7{Degree::I, ChordColor::joystick(JoystickMode::default_, JoystickDirection::right)};
    CHECK(!ChordWire::stated(Inversion{3}, 4, cMajor, maj7).has_value());
}

// MARK: – 7-bit safety

TEST_CASE("out of range notes are clamped below the SysEx status range") {
    const ChordAnnouncement a{
        Key{PitchClass::C, ScaleType::major},
        Degree::I,
        JoystickMode::default_,
        JoystickDirection::center,
        Inversion::root(),
        4,
        false,
        Voicing({-3, 200}),
    };
    const Bytes bytes = ChordWire::encodeChord(a);
    // Every byte between the F0/F7 frame markers must stay below 0x80.
    CHECK(std::all_of(bytes.begin() + 1, bytes.end() - 1, [](std::uint8_t b) { return b < 0x80; }));
}

// MARK: – Rejection of malformed input

TEST_CASE("rejects foreign and malformed frames") {
    const Bytes good = ChordWire::encodeChord(announcement());
    CHECK(!ChordWire::decode({}).has_value());
    CHECK(!ChordWire::decode({0xF0, 0x7D, 0xF7}).has_value());                    // too short
    CHECK(!ChordWire::decode({0xF0, 0x43, 0x50, 0x46, 0x01, 0x02, 0xF7}).has_value()); // foreign mfr
    CHECK(!ChordWire::decode({0xF0, 0x7D, 0x50, 0x46, 0x02, 0x02, 0xF7}).has_value()); // future version
    CHECK(!ChordWire::decode(Bytes(good.begin(), good.end() - 1)).has_value());   // truncated
    Bytes mismatch(good.begin(), good.end() - 2);
    mismatch.push_back(0xF7);
    CHECK(!ChordWire::decode(mismatch).has_value());                              // note count mismatch
    Bytes badDegree = good;
    badDegree[8] = 9;                                                             // degree out of range
    CHECK(!ChordWire::decode(badDegree).has_value());
    Bytes badOctave = good;
    badOctave[12] = 9;                                                            // octave out of range
    CHECK(!ChordWire::decode(badOctave).has_value());
    Bytes unsorted = good;
    std::swap(unsorted[17], unsorted[18]);                                        // notes not ascending
    CHECK(!ChordWire::decode(unsorted).has_value());
}

// MARK: – Wire tables stay exhaustive

TEST_CASE("wire tables cover every case") {
    // Each table lists every case exactly once, so encoding never traps
    // and no two cases share a wire number.
    CHECK(coversEveryCase(ChordWire::scaleOrder, allScaleTypes.size()));
    CHECK(coversEveryCase(ChordWire::degreeOrder, allDegrees.size()));
    CHECK(coversEveryCase(ChordWire::modeOrder, 3));
    CHECK(coversEveryCase(ChordWire::directionOrder, 9));
    // Each table is also made of the same cases as the library's own list.
    CHECK(std::set<ScaleType>(ChordWire::scaleOrder.begin(), ChordWire::scaleOrder.end()) ==
          std::set<ScaleType>(allScaleTypes.begin(), allScaleTypes.end()));
    CHECK(std::set<Degree>(ChordWire::degreeOrder.begin(), ChordWire::degreeOrder.end()) ==
          std::set<Degree>(allDegrees.begin(), allDegrees.end()));
}

}
