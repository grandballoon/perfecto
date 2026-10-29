// A chord given by its tones: the pitch classes above its root, whatever
// stack or table they came from. The step compass makes its colors this way
// (a tone added to a chord, taken away or moved a semitone), so a color is
// what sounds, named the way a lead sheet names it.

#ifndef PERFECTO_THEORY_CHORD_TONES_HPP
#define PERFECTO_THEORY_CHORD_TONES_HPP

#include <optional>
#include <string>
#include <vector>

namespace perfecto::theory {

/// The pitch classes of a chord above its root, 0 (the root) always among
/// them: C E G B♭ on C is [0, 4, 7, 10].
class ChordTones {
public:
    explicit ChordTones(const std::vector<int> &pitchClasses);

    bool operator==(const ChordTones &) const = default;
    auto operator<=>(const ChordTones &) const = default;

    /// Ascending, unique, each 0...11, the first 0. Of a temporary
    /// (`chord.tones().pitchClasses()`) they are its own copy, so a loop over
    /// them never reads a value already gone.
    const std::vector<int> &pitchClasses() const & { return pitchClasses_; }
    std::vector<int> pitchClasses() && { return std::move(pitchClasses_); }

    bool has(int pitchClass) const;

    /// The intervals the chord is voiced in: each tone in the octave above
    /// the root, but a tension over the chord (a 9th, 11th or 13th) an
    /// octave higher, where a lead sheet puts it, so it stays on top of an
    /// inversion (`Inversion`).
    std::vector<int> intervals() const;

    /// The chord's quality, as the rest of the app names chords ("maj",
    /// "min7", "7♭9", "min add9", "sus4"): the 3rd (or a suspension), the
    /// 5th, the 7th or a 6th, then the tensions, and a tone a chord of its
    /// kind would have but this one has not as "no5".
    std::string name() const;

    struct Slash {
        /// The other chord's root, in semitones above this one's.
        int root;
        std::string quality;
        bool operator==(const Slash &) const = default;
    };

    /// A chord whose own name is awkward (a tone left out, a ♭13 over no
    /// 7th) but whose tones are a plain triad or 7th chord on another of
    /// them, over this root: C E G over E is "C/E".
    std::optional<Slash> slash() const;

private:
    std::vector<int> pitchClasses_;
};

} // namespace perfecto::theory

#endif
