// Pitch classes, scales, keys and degrees: what every other part of the
// theory is read against.

#ifndef PERFECTO_THEORY_KEY_HPP
#define PERFECTO_THEORY_KEY_HPP

#include <array>
#include <optional>
#include <string>
#include <vector>

namespace perfecto::theory {

enum class PitchClass { C = 0, Cs, D, Ds, E, F, Fs, G, Gs, A, As, B };

inline constexpr std::array<PitchClass, 12> allPitchClasses = {
    PitchClass::C, PitchClass::Cs, PitchClass::D, PitchClass::Ds, PitchClass::E, PitchClass::F,
    PitchClass::Fs, PitchClass::G, PitchClass::Gs, PitchClass::A, PitchClass::As, PitchClass::B,
};

inline int raw(PitchClass p) { return static_cast<int>(p); }

/// The pitch class `semitones` is, any number of octaves from C.
PitchClass pitchClass(int semitones);

/// "C", "C#", … "B".
std::string name(PitchClass p);

/// The seven degrees. Their numbers are stored in saved patterns, so they
/// are spelled out rather than implied by declaration order.
enum class Degree { I = 1, ii = 2, iii = 3, IV = 4, V = 5, vi = 6, viiDim = 7 };

inline constexpr std::array<Degree, 7> allDegrees = {
    Degree::I, Degree::ii, Degree::iii, Degree::IV, Degree::V, Degree::vi, Degree::viiDim,
};

/// Zero-based index into the scale's intervals.
inline int index(Degree d) { return static_cast<int>(d) - 1; }

/// The degree numbered `number` (1 is I), if there is one.
std::optional<Degree> degree(int number);

enum class ScaleType {
    major,
    naturalMinor,
    harmonicMinor,
    melodicMinor,
    majorPentatonic,
    minorPentatonic,
    blues,
    dorian,
    mixolydian,
    lydian,
};

inline constexpr std::array<ScaleType, 10> allScaleTypes = {
    ScaleType::major,           ScaleType::naturalMinor,    ScaleType::harmonicMinor, ScaleType::melodicMinor,
    ScaleType::majorPentatonic, ScaleType::minorPentatonic, ScaleType::blues,         ScaleType::dorian,
    ScaleType::mixolydian,      ScaleType::lydian,
};

std::string displayName(ScaleType s);

/// Semitones above the tonic of each note, ascending from 0.
const std::vector<int> &intervals(ScaleType s);

/// A seven-note scale. Chord building stacks thirds by skipping every other
/// scale step, which only yields tertian chords on a seven-note scale.
bool isHeptatonic(ScaleType s);

/// Semitones above the tonic of the note `step` scale steps up, continuing
/// into higher octaves (step 7 of a seven-note scale is the octave).
int semitones(ScaleType s, int step);

/// Semitones above the tonic of `degree`'s root.
int offset(ScaleType s, Degree degree);

struct Key {
    PitchClass root;
    ScaleType scale;

    bool operator==(const Key &) const = default;
    auto operator<=>(const Key &) const = default;

    /// Whether `note`, a MIDI note, is a note of the key.
    bool has(int note) const;

    /// The note of the key nearest `pitch`, a MIDI note and any part of a
    /// semitone past it; of two as near, the lower. It is where a pitch
    /// that can be anywhere is in tune.
    int noteNearest(double pitch) const;

    /// Semitones from the tonic up to `pitch`, within an octave.
    int offsetOf(PitchClass pitch) const;

    /// The degree whose chord is built on `pitch`; none for a note outside
    /// the scale.
    std::optional<Degree> degreeOf(PitchClass pitch) const;

    /// Whether the key is minor: its scale has a minor third above the tonic
    /// and no major third. D Dorian is minor, G Mixolydian major. On
    /// seven-note scales this is exactly whether degree I plays a minor
    /// triad; unlike `triadBase`, it is also right for pentatonic and blues
    /// scales.
    bool isMinor() const;
};

} // namespace perfecto::theory

#endif
