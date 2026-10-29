// Ported from Tests/MusicTheoryCoreTests/MidiFileTests.swift.

#include <doctest.h>

#include "perfecto/theory/midi_file.hpp"

#include <cstdint>
#include <string>
#include <vector>

using namespace perfecto::theory;

namespace {

using Bytes = std::vector<std::uint8_t>;

Bytes encodedKind(const MidiEvent::Kind &kind) { return MidiEvent{0, kind}.encoded(); }

Bytes concat(Bytes head, const std::string &text) {
    head.insert(head.end(), text.begin(), text.end());
    return head;
}

} // namespace

TEST_SUITE("MidiFile") {

TEST_CASE("variable length quantity matches the spec examples") {
    // Examples from the Standard MIDI File 1.0 spec.
    CHECK(variableLengthQuantity(0x00) == Bytes{0x00});
    CHECK(variableLengthQuantity(0x40) == Bytes{0x40});
    CHECK(variableLengthQuantity(0x7F) == Bytes{0x7F});
    CHECK(variableLengthQuantity(0x80) == Bytes{0x81, 0x00});
    CHECK(variableLengthQuantity(0x2000) == Bytes{0xC0, 0x00});
    CHECK(variableLengthQuantity(0x3FFF) == Bytes{0xFF, 0x7F});
    CHECK(variableLengthQuantity(0x4000) == Bytes{0x81, 0x80, 0x00});
    CHECK(variableLengthQuantity(0x0FFF'FFFF) == Bytes{0xFF, 0xFF, 0xFF, 0x7F});
}

TEST_CASE("single track file is format zero with exact bytes") {
    const MidiFile file{480, {
        MidiTrack{{
            MidiEvent{0,   MidiEvent::NoteOn{0, 60, 100}},
            MidiEvent{120, MidiEvent::NoteOff{0, 60}},
        }, 480},
    }};
    CHECK(file.encoded() == Bytes{
        0x4D, 0x54, 0x68, 0x64,  0, 0, 0, 6,  0, 0,  0, 1,  0x01, 0xE0,  // MThd
        0x4D, 0x54, 0x72, 0x6B,  0, 0, 0, 13,                            // MTrk
        0x00, 0x90, 60, 100,
        0x78, 0x80, 60, 0,
        0x82, 0x68, 0xFF, 0x2F, 0x00,   // end of track 360 ticks later
    });
}

TEST_CASE("several tracks are format one") {
    const MidiTrack track{};
    const Bytes bytes = MidiFile{96, {track, track}}.encoded();
    CHECK(Bytes(bytes.begin() + 8, bytes.begin() + 12) == Bytes{0, 1, 0, 2});
}

TEST_CASE("events are sorted meta then note off then note on within a tick") {
    // Deliberately shuffled input: a retrigger of the same pitch at tick 0
    // must release before re-striking, and tempo must precede both.
    const MidiTrack track{{
        MidiEvent{0, MidiEvent::NoteOn{0, 64, 100}},
        MidiEvent{0, MidiEvent::NoteOff{0, 64}},
        MidiEvent{0, MidiEvent::Tempo{120}},
    }};
    CHECK(track.encodedBody() == Bytes{
        0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20,   // 500 000 µs per quarter
        0x00, 0x80, 64, 0,
        0x00, 0x90, 64, 100,
        0x00, 0xFF, 0x2F, 0x00,
    });
}

TEST_CASE("meta events encode their payloads") {
    CHECK(encodedKind(MidiEvent::TimeSignature{4, 4}) == Bytes{0xFF, 0x58, 0x04, 4, 2, 24, 8});
    CHECK(encodedKind(MidiEvent::TimeSignature{6, 8}) == Bytes{0xFF, 0x58, 0x04, 6, 3, 24, 8});
    CHECK(encodedKind(MidiKeySignature{-3, true}) == Bytes{0xFF, 0x59, 0x02, 0xFD, 1});
    CHECK(encodedKind(MidiEvent::TrackName{"Perfecto"}) == concat({0xFF, 0x03, 8}, "Perfecto"));
    CHECK(encodedKind(MidiEvent::Marker{"C#m7"}) == concat({0xFF, 0x06, 4}, "C#m7"));
}

TEST_CASE("note data is clamped to seven bits") {
    CHECK(encodedKind(MidiEvent::NoteOn{0, 200, 300}) == Bytes{0x90, 127, 127});
    CHECK(encodedKind(MidiEvent::NoteOff{0, -5}) == Bytes{0x80, 0, 0});
}

TEST_CASE("track length never cuts off a later event") {
    const MidiTrack track{{MidiEvent{10, MidiEvent::Marker{""}}}, 5};
    const Bytes body = track.encodedBody();
    CHECK(Bytes(body.end() - 4, body.end()) == Bytes{0x00, 0xFF, 0x2F, 0x00});
}

TEST_CASE("key signature uses the major or minor key on the same tonic") {
    struct Row {
        PitchClass root;
        ScaleType scale;
        int sharps;
        bool isMinor;
    };
    const std::vector<Row> rows = {
        {PitchClass::C,  ScaleType::major,           0,  false},
        {PitchClass::G,  ScaleType::major,           1,  false},
        {PitchClass::F,  ScaleType::major,           -1, false},
        {PitchClass::Fs, ScaleType::major,           6,  false},
        {PitchClass::Cs, ScaleType::major,           -5, false},  // spelled D♭
        {PitchClass::As, ScaleType::major,           -2, false},  // spelled B♭
        {PitchClass::A,  ScaleType::naturalMinor,    0,  true},
        {PitchClass::E,  ScaleType::harmonicMinor,   1,  true},
        {PitchClass::C,  ScaleType::minorPentatonic, -3, true},
        {PitchClass::D,  ScaleType::dorian,          -1, true},   // D minor
        {PitchClass::G,  ScaleType::mixolydian,      1,  false},  // G major
        {PitchClass::F,  ScaleType::lydian,          -1, false},  // F major
        {PitchClass::A,  ScaleType::blues,           0,  true},
    };
    for (const Row &row : rows) {
        CHECK_MESSAGE(midiKeySignature(Key{row.root, row.scale}) == (MidiKeySignature{row.sharps, row.isMinor}),
                      name(row.root), " ", displayName(row.scale));
    }
}

}
