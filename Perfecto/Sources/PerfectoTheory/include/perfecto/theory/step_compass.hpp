// The step compass: the colors one step from the chord sounding (a tone
// added, taken away, or moved a semitone; `colorSteps`), by kind of step,
// each kind in an order. Its places are the kinds and their first and
// second choices, so a place means the same before a chord is struck as
// after; what it plays is worked out from the chord
// (docs/chord-dependent-coloration.md).

#ifndef PERFECTO_THEORY_STEP_COMPASS_HPP
#define PERFECTO_THEORY_STEP_COMPASS_HPP

#include "perfecto/theory/chord_color.hpp"
#include "perfecto/theory/chord_tones.hpp"
#include "perfecto/theory/key.hpp"

#include <array>
#include <map>
#include <optional>
#include <string>
#include <vector>

namespace perfecto::theory {

/// A kind of step from a chord.
enum class ColorStepKind {
    /// A tone it has not got.
    add,
    /// One of its tones a semitone up.
    raise,
    /// One of its tones a semitone down.
    lower,
    /// One of its tones, not the root, left out.
    takeAway,
};

inline constexpr std::array<ColorStepKind, 4> allColorStepKinds = {
    ColorStepKind::add, ColorStepKind::raise, ColorStepKind::lower, ColorStepKind::takeAway};

/// A place on the compass: a kind of step and which of its choices, 1 the
/// first (the near place) and 2 the second (the far one).
class CompassPlace {
public:
    CompassPlace(ColorStepKind kind, int rank);

    ColorStepKind kind() const { return kind_; }
    int rank() const { return rank_; }

    bool operator==(const CompassPlace &) const = default;
    auto operator<=>(const CompassPlace &) const = default;

    /// Every place, each kind's first choice before its second.
    static const std::vector<CompassPlace> &all();

private:
    ColorStepKind kind_;
    int rank_;
};

/// How well a step's chord fits the key, best first.
enum class ColorFit {
    /// Every tone in the key, and none a semitone over another tone.
    inKey = 1,
    /// In the key, but the tone added or moved is a semitone over a tone of
    /// the chord: the minor 9th that jazz calls an avoid note (C add11).
    avoid,
    /// A tone from outside the key: borrowed (C minor on I in C major).
    borrowed,
};

/// The order each kind's choices are in.
enum class ColorStepRanking {
    /// In the key first; then, of adds, the degree's own next stack tone
    /// (its 7th, 9th, 13th, 11th); of moves, the 3rd before the 5th; of
    /// tones taken away, the 5th before the 3rd.
    theory,
    /// By how often the chord is played, the commonest first (7, maj7, min7,
    /// sus4, sus2, add9, 6 …), whether or not it is in the key; then as theory.
    common,
};

/// One step from a chord: its kind, the chord it makes, the tone it takes
/// from (moved or taken away) and to (added or moved), and how the chord fits.
struct ColorStep {
    ColorStepKind kind;
    ChordTones tones;
    std::optional<int> from;
    std::optional<int> to;
    ColorFit fit;

    bool operator==(const ColorStep &) const = default;

    /// What the step does, by the tones' names above the root: "+♭7", "3→4", "−5".
    std::string editName() const;
};

/// The tones `spec` plays in `key`: any color, as the notes above its root,
/// so a step can be taken from a chord however it was colored.
ChordTones chordTones(const Key &key, const ChordSpec &spec);

namespace StepCompass {

/// A kind's choices on the compass.
inline constexpr int firstRank = 1;
inline constexpr int lastRank = 2;

/// The chord `degree` plays in `key` before it is colored: its triad.
ChordTones base(const Key &key, Degree degree);

/// Every step from `tones` on `degree` in `key`, by kind (every kind
/// present), each kind in `ranking`'s order.
std::map<ColorStepKind, std::vector<ColorStep>> steps(const ChordTones &tones, const Key &key, Degree degree,
                                                      ColorStepRanking ranking);

/// The step at `place` from `tones`, or none if its kind has no choice that
/// far down (a chord of two notes has nothing to take away).
std::optional<ColorStep> step(const CompassPlace &place, const ChordTones &tones, const Key &key, Degree degree,
                              ColorStepRanking ranking);

/// The chord a walk of places makes from `degree`'s triad: each place a step
/// from where the last one led, a place with no choice left out. The walk
/// is of places, not chords, so the same walk on another degree is that
/// degree's own (two adds are G9 on V and Dm9 on ii).
ChordTones walk(const std::vector<CompassPlace> &places, const Key &key, Degree degree, ColorStepRanking ranking);

} // namespace StepCompass

} // namespace perfecto::theory

#endif
