// Chords as voices moving, after Dmitri Tymoczko's "A Geometry of Music":
// a chord is a point with a coordinate for each voice, and the distance to
// another chord is how far its voices move. A triad is a point in three
// dimensions, and a semitone of one voice is a step along one axis. The
// consonant chords are the nearly even ones, which are exactly the ones a
// small motion of the voices joins, so a space laid out by nearness keeps
// consonance close at hand.
//
// Every move here is exact, so a direction always means the same motion:
// the top voice up, the middle down, the two in contrast. A move that lands
// on a chord that is not consonant is offered dimmed and cannot be taken.

#ifndef PERFECTO_DESK_VOICE_LEADING_HPP
#define PERFECTO_DESK_VOICE_LEADING_HPP

#include "perfecto/desk/gates.hpp"
#include "perfecto/desk/music.hpp"

#include <perfecto/theory/key.hpp>

#include <array>
#include <optional>
#include <set>
#include <string>
#include <vector>

namespace perfecto::desk {

/// A motion of the voices: which move and how far.
struct VoiceMove {
    /// For the right stick, a direction clockwise from up (`VoiceLeading::moves`);
    /// for the bass, up or down.
    int direction;
    /// Semitones each moving voice goes: 1 in the inner shell, 2 in the outer.
    int shell;

    bool operator==(const VoiceMove &) const = default;
    auto operator<=>(const VoiceMove &) const = default;
};

namespace VoiceLeading {

/// How far the top voice and the middle voice move, in steps of the shell.
struct Motion {
    int top;
    int middle;
};

/// The right stick's eight directions, clockwise from up, as how far the
/// top voice and the middle voice move (in steps of the shell): up and
/// down the top, right and left the middle, the diagonals both, the
/// upper right and lower left together and the other two in contrast.
inline constexpr std::array<Motion, 8> moves = {{
    {1, 0}, {1, 1}, {0, 1}, {-1, 1}, {-1, 0}, {-1, -1}, {0, -1}, {1, -1},
}};

inline const std::array<std::string, 8> names = {
    "top ↑", "both ↑", "middle ↑", "closer", "top ↓", "both ↓", "middle ↓", "wider",
};

const PieGate &gate();
/// The bass on the left stick: up and down.
const PieGate &bassGate();
inline constexpr ClosedRange<int> shells = {1, 2};

/// The notes a chord can be moved among.
inline constexpr ClosedRange<int> range = {24, 108};

/// `notes` (ascending) with the two highest voices moved as `move` says;
/// none if a voice would cross another, meet it, or leave the range.
std::optional<std::vector<int>> moved(const std::vector<int> &notes, const VoiceMove &move);

/// `notes` with the lowest voice moved up (direction 0) or down.
std::optional<std::vector<int>> bassMoved(const std::vector<int> &notes, const VoiceMove &move);

/// The chord qualities that count as consonant, as tones above the root,
/// in the order an ambiguous set is read: triads, then the 7ths and the
/// added 9ths, then the evenly divided ones, then the 9ths. The 11ths
/// and 13ths, which stack a tone over another, are not among them.
const std::vector<std::vector<int>> &consonant();

/// Whether `pitches` (pitch classes, three or more) make a consonant chord
/// on one of them.
bool isConsonant(const std::set<int> &pitches);

/// The chord `notes` sound, read in `key`, if it is consonant: the root
/// is the bass if it can be, and otherwise the note that reads most
/// plainly.
std::optional<DeskChord> chord(const std::vector<int> &notes, const theory::Key &key);

/// The chord a move of the upper voices makes from `notes`, if consonant.
std::optional<DeskChord> neighbour(const std::vector<int> &notes, const VoiceMove &move, const theory::Key &key);

/// The chord a move of the bass makes from `notes`, if consonant.
std::optional<DeskChord> bassNeighbour(const std::vector<int> &notes, const VoiceMove &move, const theory::Key &key);

} // namespace VoiceLeading

} // namespace perfecto::desk

#endif
