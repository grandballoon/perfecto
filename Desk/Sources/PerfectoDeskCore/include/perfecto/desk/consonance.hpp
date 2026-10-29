// The consonance guard: a switch that makes the chords and notes that are
// not consonant unplayable, in every layout. What is unplayable stays where
// it is, dimmed and out of reach, so a direction keeps its meaning; a button
// that would strike it does nothing, and the controller says no.
//
// "Consonant" is one rule (`VoiceLeading::consonant`: triads, 7ths, added
// 9ths, 9ths, and the evenly divided diminished and augmented), and the
// guard's mode says against what it is read.

#ifndef PERFECTO_DESK_CONSONANCE_HPP
#define PERFECTO_DESK_CONSONANCE_HPP

#include <perfecto/theory/key.hpp>

#include <array>
#include <optional>
#include <set>
#include <string>
#include <vector>

namespace perfecto::desk {

struct DeskChord;
class DeskEffect;

/// Against what the guard reads a chord or a note.
enum class GuardMode {
    off,
    /// A chord of a consonant quality; a note of the key.
    always,
    /// As always, and with what is sounding now: a chord that shares a note
    /// with the chord sounding (the move is near), and is consonant with the
    /// line's note; a note consonant with the chord sounding.
    sounding,
    /// As always, and within the run: the notes of the last few chords
    /// played, so a chord can bring at most one note from outside them and
    /// the music drifts a step at a time.
    run,
};

inline constexpr std::array<GuardMode, 4> allGuardModes = {GuardMode::off, GuardMode::always, GuardMode::sounding,
                                                           GuardMode::run};

/// "Off", "With what's sounding".
std::string name(GuardMode mode);

/// The guard: its mode, and what it has heard. Only `mode` and `inKey` are
/// settings; the rest is what the layouts have played.
class ConsonanceGuard {
public:
    GuardMode mode = GuardMode::off;
    /// Whether a chord or note from outside the key is unplayable too.
    bool inKey = false;

    /// How many chords the run remembers.
    static constexpr int window = 6;

    bool operator==(const ConsonanceGuard &) const = default;

    /// The pitch classes of the last chords played, oldest first.
    const std::vector<std::set<int>> &recent() const { return recent_; }
    /// The chord sounding now, and the line's note, as pitch classes.
    const std::optional<std::set<int>> &chord() const { return chord_; }
    std::optional<int> note() const { return note_; }

    /// The notes of the run: every pitch class of its chords.
    std::set<int> pool() const;

    // Hearing

    /// Hears what the layouts had sounded: chords struck, lines let go.
    void hear(const std::vector<DeskEffect> &effects);

    /// Forgets the run, as if nothing had been played.
    void forgetRun() { recent_.clear(); }

    // Reading

    /// Why `chord` cannot be played in `key` now; none if it can.
    std::optional<std::string> refusal(const DeskChord &chord, const theory::Key &key) const;

    /// Why `note` cannot be played in `key` now, over the chord sounding;
    /// none if it can. (Swift's `refusal(ofNote:in:)`.)
    std::optional<std::string> refusalOfNote(int note, const theory::Key &key) const;

    bool allows(const DeskChord &chord, const theory::Key &key) const;

    /// (Swift's `allows(note:in:)`.)
    bool allowsNote(int note, const theory::Key &key) const;

private:
    std::vector<std::set<int>> recent_;
    std::optional<std::set<int>> chord_;
    std::optional<int> note_;
};

} // namespace perfecto::desk

#endif
