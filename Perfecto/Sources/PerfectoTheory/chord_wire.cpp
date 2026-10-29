#include "perfecto/theory/chord_wire.hpp"

#include "perfecto/theory/require.hpp"

#include <algorithm>

namespace perfecto::theory::ChordWire {

namespace {

// Frame header: F0 <non-commercial mfr> 'P' 'F' <version>.
constexpr std::uint8_t manufacturer = 0x7D; // MIDI "non-commercial / research" ID
constexpr std::uint8_t tagP = 0x50;
constexpr std::uint8_t tagF = 0x46;
constexpr std::uint8_t version = 0x01;

constexpr std::uint8_t typeChord = 0x01;
constexpr std::uint8_t typeRelease = 0x02;

/// Wire number of `value` in `table`. Every table lists every case, so a
/// missing case stops instead of silently encoding as index 0.
template <class T, size_t N> std::uint8_t indexIn(const T &value, const std::array<T, N> &table) {
    const auto found = std::find(table.begin(), table.end(), value);
    PERFECTO_REQUIRE(found != table.end(), "value missing from its ChordWire numbering table");
    return static_cast<std::uint8_t>(found - table.begin());
}

/// SysEx data bytes must stay below 0x80; clamp rather than truncate so an
/// out-of-range value can never masquerade as a status byte.
std::uint8_t clamp7Bit(int value) { return static_cast<std::uint8_t>(std::clamp(value, 0, 127)); }

} // namespace

std::vector<std::uint8_t> encodeChord(const ChordAnnouncement &a) {
    const auto &notes = a.voicing.notes();
    std::vector<std::uint8_t> bytes = {
        sysExStart,
        manufacturer,
        tagP,
        tagF,
        version,
        typeChord,
        static_cast<std::uint8_t>(raw(a.key.root)),
        indexIn(a.key.scale, scaleOrder),
        static_cast<std::uint8_t>(indexIn(a.degree, degreeOrder) + 1),
        indexIn(a.joystickMode, modeOrder),
        indexIn(a.joystickDirection, directionOrder),
        indexIn(a.inversion, inversionOrder),
        clamp7Bit(a.octave),
        static_cast<std::uint8_t>(a.voiceLeading ? 1 : 0),
        static_cast<std::uint8_t>(a.voicing.bassNote() ? 1 : 0),
        clamp7Bit(a.voicing.bassNote().value_or(0)),
        clamp7Bit(static_cast<int>(notes.size())),
    };
    for (int note : notes) bytes.push_back(clamp7Bit(note));
    bytes.push_back(sysExEnd);
    return bytes;
}

std::optional<Stated> stated(Inversion inversion, int octave, const Key &key, const ChordSpec &spec) {
    if (std::find(inversionOrder.begin(), inversionOrder.end(), inversion) != inversionOrder.end())
        return Stated{inversion, octave};
    const auto notes = [&](Inversion inv, int oct) {
        return computeVoicing(key, spec, inv, oct, false, std::nullopt).notes();
    };
    const auto rolled = notes(inversion, octave);
    for (int oct = octaveLow; oct <= octaveHigh; ++oct)
        for (Inversion inv : inversionOrder)
            if (notes(inv, oct) == rolled) return Stated{inv, oct};
    return std::nullopt;
}

std::vector<std::uint8_t> encodeRelease() {
    return {sysExStart, manufacturer, tagP, tagF, version, typeRelease, sysExEnd};
}

std::optional<Frame> decode(const std::vector<std::uint8_t> &bytes) {
    if (bytes.size() < 7 || bytes[0] != sysExStart || bytes[1] != manufacturer || bytes[2] != tagP ||
        bytes[3] != tagF || bytes[4] != version || bytes.back() != sysExEnd)
        return std::nullopt;

    const std::uint8_t type = bytes[5];
    if (type == typeRelease) {
        if (bytes.size() == 7) return Release{};
        return std::nullopt;
    }
    if (type != typeChord || bytes.size() < 18) return std::nullopt;

    const int root = bytes[6];
    const size_t scaleIdx = bytes[7];
    const int degreeRaw = bytes[8];
    const size_t modeIdx = bytes[9];
    const size_t dirIdx = bytes[10];
    const size_t invIdx = bytes[11];
    const int octave = bytes[12];
    const std::uint8_t vlFlag = bytes[13];
    const std::uint8_t bassFlag = bytes[14];
    const int bass = bytes[15];
    const size_t count = bytes[16];

    if (root > 11 || scaleIdx >= scaleOrder.size() || degreeRaw < 1 ||
        degreeRaw > static_cast<int>(degreeOrder.size()) || modeIdx >= modeOrder.size() ||
        dirIdx >= directionOrder.size() || invIdx >= inversionOrder.size() || octave < octaveLow ||
        octave > octaveHigh || vlFlag > 1 || bassFlag > 1 || bytes.size() != 17 + count + 1)
        return std::nullopt;

    std::vector<int> notes(bytes.begin() + 17, bytes.begin() + 17 + static_cast<std::ptrdiff_t>(count));
    for (size_t i = 1; i < notes.size(); ++i)
        if (notes[i - 1] >= notes[i]) return std::nullopt; // ascending

    return ChordAnnouncement{
        Key{pitchClass(root), scaleOrder[scaleIdx]},
        degreeOrder[degreeRaw - 1],
        modeOrder[modeIdx],
        directionOrder[dirIdx],
        inversionOrder[invIdx],
        octave,
        vlFlag == 1,
        Voicing(notes, bassFlag == 1 ? std::optional<int>(bass) : std::nullopt),
    };
}

} // namespace perfecto::theory::ChordWire
