// Standard MIDI File (SMF) encoder: turns timed note and meta events into
// the bytes of a `.mid` file that any DAW imports as an ordinary instrument
// track. Only what Perfecto needs is modelled (notes, tempo, time and key
// signature, and text) and no program change is ever written, so the
// importing DAW is free to assign any instrument.
//
// Events carry absolute tick positions; encoding sorts them and converts to
// the delta times the format requires.

#ifndef PERFECTO_THEORY_MIDI_FILE_HPP
#define PERFECTO_THEORY_MIDI_FILE_HPP

#include "perfecto/theory/key.hpp"

#include <cstdint>
#include <string>
#include <variant>
#include <vector>

namespace perfecto::theory {

/// An SMF key signature: count of sharps (positive) or flats (negative) in
/// −7…7, plus the major/minor flag. The tonic is implied by the pair.
struct MidiKeySignature {
    int sharps;
    bool isMinor;
    bool operator==(const MidiKeySignature &) const = default;
};

/// The key signature a DAW should adopt for `key`. SMF only knows major and
/// minor keys, so every scale maps to the major or minor key on the same
/// tonic, decided by `isMinor`: D Dorian → D minor, G Mixolydian → G major.
/// Flat spellings are used for the black keys except F♯ (six sharps).
MidiKeySignature midiKeySignature(const Key &key);

struct MidiEvent {
    /// `channel` is 0-based (0 = MIDI channel 1).
    struct NoteOn {
        int channel, note, velocity;
        bool operator==(const NoteOn &) const = default;
    };
    struct NoteOff {
        int channel, note;
        bool operator==(const NoteOff &) const = default;
    };
    struct Tempo {
        double bpm;
        bool operator==(const Tempo &) const = default;
    };
    struct TimeSignature {
        int numerator, denominator;
        bool operator==(const TimeSignature &) const = default;
    };
    struct TrackName {
        std::string name;
        bool operator==(const TrackName &) const = default;
    };
    /// Timeline marker; DAWs such as Logic show these by name.
    struct Marker {
        std::string text;
        bool operator==(const Marker &) const = default;
    };
    using Kind = std::variant<NoteOn, NoteOff, Tempo, TimeSignature, MidiKeySignature, TrackName, Marker>;

    int tick;
    Kind kind;

    bool operator==(const MidiEvent &) const = default;

    /// The event's bytes, without its delta time.
    std::vector<std::uint8_t> encoded() const;
};

struct MidiTrack {
    std::vector<MidiEvent> events;
    /// Tick at which the track ends. The end-of-track marker is placed here
    /// (or at the last event, if later) so trailing silence survives import:
    /// a pattern ending in rests keeps its full bar length.
    int length = 0;

    bool operator==(const MidiTrack &) const = default;

    std::vector<std::uint8_t> encodedBody() const;
};

struct MidiFile {
    /// Timing resolution (PPQN): ticks per quarter note.
    int ticksPerQuarter;
    std::vector<MidiTrack> tracks;

    bool operator==(const MidiFile &) const = default;

    /// The complete file. A single track is written as format 0, several as
    /// format 1 (simultaneous tracks).
    std::vector<std::uint8_t> encoded() const;
};

/// SMF variable-length quantity: 7 bits per byte, most significant first,
/// high bit set on every byte except the last.
std::vector<std::uint8_t> variableLengthQuantity(int value);

} // namespace perfecto::theory

#endif
