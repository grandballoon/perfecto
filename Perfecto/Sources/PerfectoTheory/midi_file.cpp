#include "perfecto/theory/midi_file.hpp"

#include <algorithm>
#include <cmath>
#include <numeric>
#include <tuple>

namespace perfecto::theory {

namespace {

std::vector<std::uint8_t> bigEndian(long value, int byteCount) {
    std::vector<std::uint8_t> bytes;
    for (int i = byteCount - 1; i >= 0; --i) bytes.push_back(static_cast<std::uint8_t>(value >> (i * 8)));
    return bytes;
}

std::vector<std::uint8_t> ascii(const std::string &text) { return {text.begin(), text.end()}; }

std::vector<std::uint8_t> meta(std::uint8_t type, const std::vector<std::uint8_t> &data) {
    std::vector<std::uint8_t> bytes = {0xFF, type};
    const auto length = variableLengthQuantity(static_cast<int>(data.size()));
    bytes.insert(bytes.end(), length.begin(), length.end());
    bytes.insert(bytes.end(), data.begin(), data.end());
    return bytes;
}

std::uint8_t clampByte(int value, int low, int high) { return static_cast<std::uint8_t>(std::clamp(value, low, high)); }

/// Order within a tick: meta first (tempo and key apply before any note),
/// then note-offs, then note-ons, so a pitch released and re-struck on the
/// same tick is heard as a new note rather than cut short.
int orderWithinTick(const MidiEvent::Kind &kind) {
    if (std::holds_alternative<MidiEvent::NoteOff>(kind)) return 1;
    if (std::holds_alternative<MidiEvent::NoteOn>(kind)) return 2;
    return 0;
}

void append(std::vector<std::uint8_t> &bytes, const std::vector<std::uint8_t> &more) {
    bytes.insert(bytes.end(), more.begin(), more.end());
}

} // namespace

MidiKeySignature midiKeySignature(const Key &key) {
    // A minor key shares its signature with the major key a minor third up.
    const bool minor = key.isMinor();
    const int relativeMajor = (raw(key.root) + (minor ? 3 : 0)) % 12;
    // Position on the circle of fifths: C=0, G=1, D=2 … F=11.
    const int fifths = (relativeMajor * 7) % 12;
    return {fifths > 6 ? fifths - 12 : fifths, minor};
}

std::vector<std::uint8_t> MidiEvent::encoded() const {
    if (const auto *on = std::get_if<NoteOn>(&kind))
        return {static_cast<std::uint8_t>(0x90 | (on->channel & 0x0F)), clampByte(on->note, 0, 127),
                clampByte(on->velocity, 1, 127)};
    if (const auto *off = std::get_if<NoteOff>(&kind))
        return {static_cast<std::uint8_t>(0x80 | (off->channel & 0x0F)), clampByte(off->note, 0, 127), 0};
    if (const auto *tempo = std::get_if<Tempo>(&kind)) {
        const double micros = std::clamp(std::round(60'000'000.0 / tempo->bpm), 1.0, double(0xFF'FFFF));
        return meta(0x51, bigEndian(static_cast<long>(micros), 3));
    }
    if (const auto *signature = std::get_if<TimeSignature>(&kind)) {
        // Denominator is stored as a power of two; 24 MIDI clocks per
        // metronome click and 8 thirty-seconds per quarter are the universal
        // defaults.
        int power = 0;
        while ((1 << (power + 1)) <= signature->denominator) ++power;
        return meta(0x58, {clampByte(signature->numerator, 0, 255), static_cast<std::uint8_t>(power), 24, 8});
    }
    if (const auto *key = std::get_if<MidiKeySignature>(&kind))
        return meta(0x59, {static_cast<std::uint8_t>(static_cast<std::int8_t>(key->sharps)),
                           static_cast<std::uint8_t>(key->isMinor ? 1 : 0)});
    if (const auto *name = std::get_if<TrackName>(&kind)) return meta(0x03, ascii(name->name));
    return meta(0x06, ascii(std::get<Marker>(kind).text));
}

std::vector<std::uint8_t> MidiTrack::encodedBody() const {
    std::vector<size_t> order(events.size());
    std::iota(order.begin(), order.end(), size_t{0});
    std::sort(order.begin(), order.end(), [&](size_t a, size_t b) {
        return std::make_tuple(events[a].tick, orderWithinTick(events[a].kind), a) <
               std::make_tuple(events[b].tick, orderWithinTick(events[b].kind), b);
    });

    std::vector<std::uint8_t> bytes;
    int lastTick = 0;
    for (size_t i : order) {
        const int tick = std::max(events[i].tick, 0);
        append(bytes, variableLengthQuantity(tick - lastTick));
        append(bytes, events[i].encoded());
        lastTick = tick;
    }
    const int end = std::max(length, lastTick);
    append(bytes, variableLengthQuantity(end - lastTick));
    append(bytes, {0xFF, 0x2F, 0x00}); // end of track
    return bytes;
}

std::vector<std::uint8_t> MidiFile::encoded() const {
    std::vector<std::uint8_t> bytes = ascii("MThd");
    append(bytes, bigEndian(6, 4));
    append(bytes, bigEndian(tracks.size() == 1 ? 0 : 1, 2));
    append(bytes, bigEndian(static_cast<long>(tracks.size()), 2));
    append(bytes, bigEndian(ticksPerQuarter, 2));
    for (const MidiTrack &track : tracks) {
        const auto body = track.encodedBody();
        append(bytes, ascii("MTrk"));
        append(bytes, bigEndian(static_cast<long>(body.size()), 4));
        append(bytes, body);
    }
    return bytes;
}

std::vector<std::uint8_t> variableLengthQuantity(int value) {
    unsigned remaining = static_cast<unsigned>(std::max(value, 0));
    std::vector<std::uint8_t> bytes = {static_cast<std::uint8_t>(remaining & 0x7F)};
    remaining >>= 7;
    while (remaining > 0) {
        bytes.insert(bytes.begin(), static_cast<std::uint8_t>((remaining & 0x7F) | 0x80));
        remaining >>= 7;
    }
    return bytes;
}

} // namespace perfecto::theory
