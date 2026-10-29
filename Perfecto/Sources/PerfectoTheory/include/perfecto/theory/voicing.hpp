// A chord as MIDI notes, and how a chord's notes are rolled and placed.

#ifndef PERFECTO_THEORY_VOICING_HPP
#define PERFECTO_THEORY_VOICING_HPP

#include "perfecto/theory/chord_color.hpp"
#include "perfecto/theory/key.hpp"

#include <optional>
#include <vector>

namespace perfecto::theory {

class Voicing {
public:
    /// The notes MIDI can carry.
    static constexpr int midiLow = 0;
    static constexpr int midiHigh = 127;

    /// Notes outside the MIDI range are moved by octaves into it, keeping
    /// their pitch class: a chord voiced near the top of the range folds its
    /// highest notes down rather than losing them.
    explicit Voicing(const std::vector<int> &notes, std::optional<int> bassNote = std::nullopt);

    bool operator==(const Voicing &) const = default;

    /// MIDI note numbers, sorted low to high, without duplicates, all within
    /// the MIDI range, so every consumer can send them as MIDI data bytes.
    const std::vector<int> &notes() const { return notes_; }
    /// An optional slash-chord bass, also within the MIDI range.
    std::optional<int> bassNote() const { return bassNote_; }

private:
    std::vector<int> notes_;
    std::optional<int> bassNote_;
};

/// How far a chord's notes are rolled from root position, as a pianist
/// inverts a chord. The notes within an octave of the root take turns in
/// the bass: each step up takes the lowest of them up an octave, and each
/// step down the highest of them down one, so the first two steps up are
/// the first and second inversions. The notes a ninth or more above the
/// root (the 9th, 11th and 13th) are not inverted: they stay on top, as
/// they are spaced, an octave further up where a note rolled up would
/// otherwise pass them. So once each note within the octave has had its
/// turn the chord is as it was in root position, an octave up or down,
/// whatever it has above. It has no end either way.
struct Inversion {
    /// Steps up from root position; below 0 is steps down.
    int steps = 0;

    bool operator==(const Inversion &) const = default;
    auto operator<=>(const Inversion &) const = default;

    static constexpr Inversion root() { return {0}; }
    static constexpr Inversion first() { return {1}; }
    static constexpr Inversion second() { return {2}; }

    /// This inversion rolled `by` further.
    constexpr Inversion rolled(int by) const { return {steps + by}; }

    /// `intervals` (a chord's notes, in semitones from its root) rolled this
    /// far: the same pitch classes, sorted.
    std::vector<int> applied(const std::vector<int> &intervals) const;
};

/// The MIDI notes for the chord `spec` in `key`, voiced by the given
/// settings. Middle C = C4 = note 60, so the chord's root is the key's root
/// + (octave + 1) × 12 + the degree's offset.
Voicing computeVoicing(const Key &key, const ChordSpec &spec, Inversion inversion, int octave, bool voiceLeading,
                       const std::optional<Voicing> &previousVoicing);

} // namespace perfecto::theory

#endif
