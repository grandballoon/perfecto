#ifndef PERFECTO_DESK_TWIN_RINGS_HPP
#define PERFECTO_DESK_TWIN_RINGS_HPP

#include "perfecto/desk/gates.hpp"
#include "perfecto/desk/layout.hpp"
#include "perfecto/desk/music.hpp"
#include "perfecto/desk/pad.hpp"
#include "perfecto/desk/ring_pie.hpp"
#include "perfecto/desk/voice_leading.hpp"

#include <perfecto/theory/key.hpp>

#include <functional>
#include <optional>
#include <vector>

namespace perfecto::desk {

/// Model 1, Twin rings: each stick is a ring the app already has. The left
/// stick is a pie of the seven degrees in scale order; the right is
/// the color ring, its angle the mode and its radius the stack height; the
/// right trigger strikes, how fast it is pulled how loud. A colored chord is
/// one gesture, and a change of color under a held chord is the right thumb
/// moving.
///
/// The right stick is played, not kept: a lean is heard while it is held
/// and goes back when it is let go. A flick (out and back quickly) keeps
/// the cell it pointed at, so the kept color and the played one are told
/// apart by the hand, with no latch to press.
class TwinRings {
public:
    /// The moves of the upper voices, the inner shell and the outer (Swift's
    /// tuple `(inner:outer:)`).
    struct VoiceTargets {
        std::vector<std::optional<Target>> inner;
        std::vector<std::optional<Target>> outer;

        bool operator==(const VoiceTargets &) const = default;
    };

    TwinRings() = default;

    bool operator==(const TwinRings &) const = default;

    theory::Degree degree() const { return degree_; }
    /// The ring's cell leaned at, and the one kept.
    std::optional<RingCell> aim() const { return aim_; }
    std::optional<RingCell> kept() const { return kept_; }
    /// The step compass's place leaned at and kept, while LB is held.
    std::optional<int> compassAim() const { return compassAim_; }
    std::optional<int> keptStep() const { return keptStep_; }
    /// The favorite leaned at and kept, while Y is held: an index of the
    /// degree's favorites in the table played.
    std::optional<int> favoriteAim() const { return favoriteAim_; }
    std::optional<int> keptFavorite() const { return keptFavorite_; }
    /// Whether a chord goes on sounding when the strike lets go.
    bool holds() const { return holds_; }
    const ChordLine &line() const { return line_; }
    /// The arpeggio's step on LT: 0 off.
    int arpeggioStep() const { return arpeggioStep_; }
    /// The chord last struck, which the ring's nearest order is turned to:
    /// not the chord sounding, which a lean changes, or the ring would turn
    /// under the thumb.
    const std::optional<DeskChord> &struck() const { return struck_; }

    /// Whether RB is extending the ring to the 13th.
    bool isExtended() const { return isExtended_; }
    /// Whether LB has the right stick on the step compass.
    bool isOnCompass() const { return isOnCompass_; }
    /// Whether a long-press of LB has left the compass on, so it stays on
    /// the right stick without LB held, until another long-press.
    bool compassLatched() const { return compassLatched_; }
    /// Whether Y has the right stick on the favorites.
    bool isOnFavorites() const { return isOnFavorites_; }
    /// Whether the LB layer is on with the voices on the sticks.
    bool isOnVoices() const { return isOnVoices_; }
    /// The move of the upper voices leaned at, and of the bass.
    std::optional<VoiceMove> voiceAim() const { return voiceAim_; }
    std::optional<VoiceMove> bassAim() const { return bassAim_; }
    /// The chord the voices have walked to, kept until R3 takes it back or
    /// another degree is chosen.
    const std::optional<DeskChord> &walked() const { return walked_; }

    /// The favorites' gate: a direction for each of a chord's eight.
    static const PieGate &favoritesGate();

    std::vector<DeskEffect> step(const PadInput &input, DeskSettings &settings);

    std::vector<DeskEffect> releaseAll();

    /// The chord the hands are on now.
    DeskChord chord(const DeskSettings &settings) const;

    /// The chord the voices move from: where they have walked to, or the
    /// colored chord. (Internal in Swift.)
    DeskChord voiced(const DeskSettings &settings) const;

    /// The chord the degree, the ring or a favorite, and the compass make.
    /// (Internal in Swift.)
    DeskChord colored(const DeskSettings &settings) const;

    // What the screen shows

    /// The chord R3 at rest goes back to: the chord before the compass's
    /// step, or with none the plain chord; none when it is plain already.
    std::optional<DeskChord> resetsTo(const DeskSettings &settings) const;

    /// The moves of the upper voices from the chord the voices are on, the
    /// inner shell (a semitone) and the outer (two), clockwise from up; none
    /// where a move crosses voices, and dimmed where it is not consonant.
    VoiceTargets voiceTargets(const DeskSettings &settings) const;

    /// The bass's moves: up a semitone and two, then down a semitone and two.
    std::vector<std::optional<Target>> bassTargets(const DeskSettings &settings) const;

    std::vector<Target> degreeTargets(const DeskSettings &settings) const;

    /// The ring's cells for the degree chosen, ring by ring (inside out),
    /// each sector darkest first.
    std::vector<std::vector<Target>> ringTargets(const DeskSettings &settings) const;

    /// The degree's favorites in the table played, round the stick, while Y
    /// is held.
    std::vector<std::optional<Target>> favoriteTargets(const DeskSettings &settings) const;

    /// The step compass's places from the ring's chord, while LB is held.
    std::vector<Target> compassTargets(const DeskSettings &settings) const;

    Legend legend(const DeskSettings &settings) const;

private:
    theory::Degree degree_ = theory::Degree::I;
    std::optional<int> degreeSector_ = DegreePie::sector(theory::Degree::I);
    std::optional<RingCell> aim_;
    std::optional<RingCell> kept_;
    std::optional<int> compassAim_;
    std::optional<int> keptStep_;
    std::optional<int> favoriteAim_;
    std::optional<int> keptFavorite_;
    bool holds_ = false;
    ChordLine line_;
    int arpeggioStep_ = 0;

    StickGesture ring_;
    std::optional<int> band_;
    StickGesture compass_;
    TriggerStrike strike_;
    double struckLevel_ = 0.8;
    std::optional<DeskChord> struck_;
    StickGesture favorites_;
    TapOrHold lb_;
    TapOrHold rb_;
    TapOrHold y_;

    bool isExtended_ = false;
    bool isOnCompass_ = false;
    bool compassLatched_ = false;
    /// When LB went down, while it is held and has not yet been held long.
    std::optional<double> lbHeldSince_;
    bool isOnFavorites_ = false;
    bool isOnVoices_ = false;
    std::optional<VoiceMove> voiceAim_;
    std::optional<VoiceMove> bassAim_;
    std::optional<DeskChord> walked_;
    StickGesture voices_;
    std::optional<int> voiceBand_;
    StickGesture bass_;
    std::optional<int> bassBand_;

    // The voices

    /// The right stick on the upper voices: a lean plays the move, a flick
    /// takes it, R3 while leaning takes it too; the outer ring moves each
    /// voice two semitones.
    std::vector<DeskEffect> stepVoices(const PadInput &input, const DeskSettings &settings);

    /// The left stick on the bass, up and down, as the right is on the upper voices.
    std::vector<DeskEffect> stepBass(const PadInput &input, const DeskSettings &settings);

    /// Whether the guard would play the chord the hands would be on after `change`.
    bool allows(const std::function<void(TwinRings &)> &change, const DeskSettings &settings) const;

    void letGoOfVoices();
};

} // namespace perfecto::desk

#endif
