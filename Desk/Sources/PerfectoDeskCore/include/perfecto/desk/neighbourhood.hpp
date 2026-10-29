// Model 3, the neighbourhood: no chord is chosen by name. The screen is
// centred on the chord sounding, and round it, at the right stick's eight
// directions, are the chords one step away, by a lens the bumpers choose.
// A flick moves there and strikes it; a lean held plays it while it is held
// and comes back. Every move offered is a note, or one rule, from where the
// music is, so consonance is the default and the theory is the layout.

#ifndef PERFECTO_DESK_NEIGHBOURHOOD_HPP
#define PERFECTO_DESK_NEIGHBOURHOOD_HPP

#include "perfecto/desk/gates.hpp"
#include "perfecto/desk/layout.hpp"
#include "perfecto/desk/music.hpp"
#include "perfecto/desk/pad.hpp"

#include <perfecto/theory/chord_tones.hpp>
#include <perfecto/theory/key.hpp>

#include <array>
#include <optional>
#include <string>
#include <vector>

namespace perfecto::desk {

class Neighbourhood {
public:
    /// What "one step" means.
    enum class Lens {
        /// The colors of this degree a step away: a tone added (up), raised
        /// (right), taken away (down) or lowered (left).
        color,
        /// The triads a voice-leading move away: the Tonnetz's flips and
        /// their nearest compounds.
        tonnetz,
        /// The key's other degrees, by the cycle of thirds: those sharing
        /// two notes to either side, the fifths above them.
        degrees,
    };

    static constexpr std::array<Lens, 3> allLenses = {Lens::color, Lens::tonnetz, Lens::degrees};

    /// A neighbour: the chord, and the move that reaches it.
    struct Neighbour {
        DeskChord chord;
        std::string move;

        bool operator==(const Neighbour &) const = default;
    };

    static const PieGate &gate();

    Neighbourhood();

    bool operator==(const Neighbourhood &) const = default;

    const DeskChord &centre() const { return centre_; }
    Lens lens() const { return lens_; }
    /// The chords moved through, and where along them the centre is.
    const std::vector<DeskChord> &path() const { return path_; }
    int pathIndex() const { return pathIndex_; }
    /// Eight chords kept to come back to.
    const std::vector<std::optional<DeskChord>> &palette() const { return palette_; }
    /// The neighbour or bookmark being listened to while the stick leans.
    std::optional<int> audition() const { return audition_; }
    const ChordLine &line() const { return line_; }
    bool isOnPalette() const { return isOnPalette_; }

    std::vector<DeskEffect> step(const PadInput &input, DeskSettings &settings);

    std::vector<DeskEffect> releaseAll();

    // The lenses

    /// The neighbours at the stick's eight directions, clockwise from up;
    /// none where the lens has none.
    std::vector<std::optional<Neighbour>> neighbours(const DeskSettings &settings) const;

    // What the screen shows

    std::vector<std::optional<Target>> neighbourTargets(const DeskSettings &settings) const;

    /// What the centre is in the key: its numeral, or borrowed.
    std::string centreDetail(const DeskSettings &settings) const;

    Legend legend(const DeskSettings &settings) const;

private:
    DeskChord centre_;
    Lens lens_ = Lens::color;
    std::vector<DeskChord> path_;
    int pathIndex_ = -1;
    std::vector<std::optional<DeskChord>> palette_;
    std::optional<int> audition_;
    ChordLine line_;
    bool isOnPalette_ = false;

    StickGesture gesture_;
    bool wasSounding_ = false;
    double swell_ = 0.8;
    double brightness_ = 1.0;
    /// The left stick walks the path a step each time it is pushed aside.
    bool pathArmed_ = true;

    /// Makes `chord` the centre, on the path after where the centre was,
    /// and strikes it.
    std::vector<DeskEffect> move(const DeskChord &chord, const DeskSettings &settings, double time);

    /// Lets go of a neighbour listened to: back to the centre if it was
    /// sounding, or to silence.
    std::vector<DeskEffect> endAudition(const DeskSettings &settings);
};

/// "Color", "Tonnetz", "Degrees".
std::string name(Neighbourhood::Lens lens);

/// A major or minor triad, for the Tonnetz's moves. A chord that is
/// neither is read by its third: minor if it has a minor one, major otherwise.
struct Triad {
    theory::PitchClass root;
    bool isMajor;

    Triad(theory::PitchClass root, bool isMajor) : root(root), isMajor(isMajor) {}

    explicit Triad(const DeskChord &chord);

    bool operator==(const Triad &) const = default;

    theory::ChordTones tones() const;

    /// The moves round a triad, clockwise from up as the stick reaches them.
    enum class Move { parallel, relative, dominant, hexatonicUp, nebenverwandt, hexatonicDown, subdominant, leadingTone };

    static constexpr std::array<Move, 8> allMoves = {Move::parallel,      Move::relative,     Move::dominant,
                                                     Move::hexatonicUp,   Move::nebenverwandt, Move::hexatonicDown,
                                                     Move::subdominant,   Move::leadingTone};

    /// The triad sharing two notes with this one and the other third.
    Triad p() const { return moved(0, !isMajor); }
    /// The relative: C major's A minor, A minor's C major.
    Triad r() const { return isMajor ? moved(9, false) : moved(3, true); }
    /// The leading-tone exchange: C major's E minor, E minor's C major.
    Triad l() const { return isMajor ? moved(4, false) : moved(8, true); }

    Triad applying(Move move) const;

private:
    Triad moved(int semitones, bool major) const;
};

/// "P · parallel", "a 5th up", "N".
std::string name(Triad::Move move);

} // namespace perfecto::desk

#endif
