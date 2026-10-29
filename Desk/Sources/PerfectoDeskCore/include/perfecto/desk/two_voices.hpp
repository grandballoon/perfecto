// Model 4, two hands, two voices: each hand an instrument, each with its
// trigger as pressure. The left hand plays the chords, LT their swell, an
// organ's expression pedal; the right hand plays a line over them, the
// stick a pie of the key's notes and RT the pressure a phone cannot sense.
// With RB held the right stick is a Trautonium's bar: the line's pitch
// follows the stick, and comes to rest on the key's nearest note.

#ifndef PERFECTO_DESK_TWO_VOICES_HPP
#define PERFECTO_DESK_TWO_VOICES_HPP

#include "perfecto/desk/gates.hpp"
#include "perfecto/desk/layout.hpp"
#include "perfecto/desk/music.hpp"
#include "perfecto/desk/pad.hpp"

#include <perfecto/theory/key.hpp>
#include <perfecto/theory/tertian.hpp>

#include <optional>
#include <string>
#include <vector>

namespace perfecto::desk {

/// One note at a time: struck, then shaped and bent while it is held, which
/// is heard as a slide.
class MelodyVoice {
public:
    MelodyVoice() = default;

    bool operator==(const MelodyVoice &) const = default;

    /// The note struck, sounding.
    std::optional<int> note() const { return note_; }
    /// How far it is bent from its pitch, in semitones.
    double bend() const { return bend_; }
    double level() const { return level_; }
    double brightness() const { return brightness_; }

    /// The pitch it sounds at, bend and all.
    std::optional<double> pitch() const;

    std::vector<DeskEffect> strike(int note, double level, const std::string &sound);

    /// Slides what sounds to `pitch`.
    std::vector<DeskEffect> glide(double pitch);

    std::vector<DeskEffect> shape(double level, double brightness);

    std::vector<DeskEffect> release();

private:
    std::optional<int> note_;
    double bend_ = 0.0;
    double level_ = 0.8;
    double brightness_ = 1.0;
};

class TwoVoices {
public:
    /// A note petal: the note, whether the chord has it, and whether the
    /// stick can point at it. (Swift's tuple.)
    struct Petal {
        int note;
        bool isChordTone;
        bool isReachable;
        bool operator==(const Petal &) const = default;
    };

    static constexpr ClosedRange<int> lineOctaves = {0, 3};
    /// The bar's range, in semitones above the tonic.
    static constexpr double barSpan = 24.0;
    /// How long the bar's pitch has to stay put to come to rest on a note.
    static constexpr double restTime = 0.12;

    TwoVoices() = default;

    bool operator==(const TwoVoices &) const = default;

    theory::Degree degree() const { return degree_; }
    theory::StackHeight height() const { return height_; }
    const ChordLine &chords() const { return chords_; }
    /// Whether the chord sounds whether or not LT is pulled.
    bool drones() const { return drones_; }
    const MelodyVoice &melody() const { return melody_; }
    /// The note petal pointed at, and whether in the outer ring.
    std::optional<int> petal() const { return petal_; }
    /// The line's octave above the chords'.
    int lineOctave() const { return lineOctave_; }
    /// Whether only the chord's own notes can be pointed at.
    bool chordTonesOnly() const { return chordTonesOnly_; }
    bool isOnBar() const { return isOnBar_; }
    /// The bar's pitch, and when it last moved.
    std::optional<double> barPitch() const { return barPitch_; }

    std::vector<DeskEffect> step(const PadInput &input, DeskSettings &settings);

    /// The chord the left hand is on.
    DeskChord chord(const DeskSettings &settings) const;

    std::vector<Target> degreeTargets(const DeskSettings &settings) const;

    /// The pitch of the tonic the line starts from.
    int lineTonic(const DeskSettings &settings) const;

    /// The petals: the key's notes clockwise from the tonic at the top,
    /// those the chord has marked.
    std::vector<Petal> petals(const DeskSettings &settings) const;

    std::vector<DeskEffect> releaseAll();

    Legend legend(const DeskSettings &settings) const;

private:
    theory::Degree degree_ = theory::Degree::I;
    std::optional<int> degreeSector_ = DegreePie::sector(theory::Degree::I);
    theory::StackHeight height_ = theory::StackHeight::triad;
    ChordLine chords_;
    bool drones_ = false;
    MelodyVoice melody_;
    std::optional<int> petal_;
    std::optional<int> band_;
    int lineOctave_ = 1;
    bool chordTonesOnly_ = false;
    bool isOnBar_ = false;
    std::optional<double> barPitch_;
    double barMoved_ = 0.0;
    TriggerStrike swell_;
    TriggerStrike pressure_;

    /// The chord the left hand would be on at `degree`.
    DeskChord chord(theory::Degree degree, const DeskSettings &settings) const;

    std::optional<double> petalPitch(const Stick &stick, const DeskSettings &settings);

    /// (Swift's `barPitch(_:_:)`, which C++ cannot name as the getter.)
    double barPitchOf(const PadInput &input, const DeskSettings &settings);
};

} // namespace perfecto::desk

#endif
