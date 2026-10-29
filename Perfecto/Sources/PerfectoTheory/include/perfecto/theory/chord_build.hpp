// A chord built from buttons, as an Orchid builds one: a type (the triad)
// and any extensions added to it. Each button says one thing about the
// chord, so the chord is the same on every root and in every key.

#ifndef PERFECTO_THEORY_CHORD_BUILD_HPP
#define PERFECTO_THEORY_CHORD_BUILD_HPP

#include "perfecto/theory/chord_shape.hpp"

#include <array>
#include <optional>
#include <set>
#include <string>

namespace perfecto::theory {

/// The triad a chord is built on, chosen by a button.
enum class ChordType {
    /// The root alone, with nothing built on it.
    note,
    diminished,
    minor,
    major,
    /// The fourth in the third's place.
    suspended,
};

inline constexpr std::array<ChordType, 5> allChordTypes = {
    ChordType::note, ChordType::diminished, ChordType::minor, ChordType::major, ChordType::suspended,
};

/// What its button is marked.
std::string mark(ChordType t);

/// A note added to a chord's triad, chosen by a button.
enum class ChordExtension {
    /// The sixth, which over a seventh is a thirteenth.
    sixth,
    minorSeventh,
    majorSeventh,
    ninth,
};

inline constexpr std::array<ChordExtension, 4> allChordExtensions = {
    ChordExtension::sixth, ChordExtension::minorSeventh, ChordExtension::majorSeventh, ChordExtension::ninth,
};

/// What its button is marked.
std::string mark(ChordExtension e);

/// A chord as buttons build it: a type, or the degree's own triad, and the
/// extensions added to it.
class ChordBuild {
public:
    explicit ChordBuild(std::optional<ChordType> type, std::set<ChordExtension> extensions = {});

    bool operator==(const ChordBuild &) const = default;
    auto operator<=>(const ChordBuild &) const = default;

    /// None: the triad of the degree that plays, as the key has it.
    const std::optional<ChordType> &type() const { return type_; }
    /// A note has none: they are kept only for a triad.
    const std::set<ChordExtension> &extensions() const { return extensions_; }

    /// The buttons that build it, as an Orchid's are marked: "Min · m7 9".
    std::string legend() const;

    /// The chord on a degree whose own triad is `base`.
    ///
    /// The extensions are added above the triad: the sixth (a diminished
    /// triad's is its seventh, so a diminished seventh), a seventh, and the
    /// ninth an octave above the second. The sixth over a seventh is the
    /// thirteenth, above the ninth's octave, and the two sevenths together
    /// are the major one.
    ChordShape shape(TriadBase base) const;

private:
    std::optional<ChordType> type_;
    std::set<ChordExtension> extensions_;
};

} // namespace perfecto::theory

#endif
