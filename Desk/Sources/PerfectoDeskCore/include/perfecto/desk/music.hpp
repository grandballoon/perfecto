// What the layouts play, as values: a chord in a key, the settings every
// layout shares, and the effects the shell is asked to perform.

#ifndef PERFECTO_DESK_MUSIC_HPP
#define PERFECTO_DESK_MUSIC_HPP

#include "perfecto/desk/consonance.hpp"
#include "perfecto/desk/favorites.hpp"
#include "perfecto/desk/gates.hpp"

#include <perfecto/theory/chord_color.hpp>
#include <perfecto/theory/chord_tones.hpp>
#include <perfecto/theory/key.hpp>
#include <perfecto/theory/step_compass.hpp>
#include <perfecto/theory/voicing.hpp>

#include <array>
#include <cstdint>
#include <optional>
#include <set>
#include <string>
#include <type_traits>
#include <utility>
#include <variant>
#include <vector>

namespace perfecto::desk {

// Settings whose types are in the files that use them (arrangement.hpp,
// ring_pie.hpp), declared here so the settings can hold them.
enum class BeatGrid : int;
enum class RingArrangement : int;
enum class RingOrder : int;
enum class RingFilter : int;
class RingPie;

/// Swift's `ClosedRange`: from `lowerBound` to `upperBound`, both in it.
template <class T> struct ClosedRange {
    T lowerBound;
    T upperBound;

    constexpr bool contains(T value) const { return lowerBound <= value && value <= upperBound; }
    bool operator==(const ClosedRange &) const = default;
};

/// What Twin rings' LB layer puts on the sticks.
enum class LBLayer {
    /// The step compass: a tone of the chord added, raised, taken away or
    /// lowered, its root kept.
    compass,
    /// The voices: the top two on the right stick and the bass on the left,
    /// each moved a semitone or two to the consonant chords nearest
    /// (`VoiceLeading`), the root free to move.
    voices,
};

inline constexpr std::array<LBLayer, 2> allLBLayers = {LBLayer::compass, LBLayer::voices};

std::string name(LBLayer layer);

/// Where notes go: the kernel's own sound, MIDI, or both.
enum class DeskOutput { synth, midi, both };

inline constexpr std::array<DeskOutput, 3> allDeskOutputs = {DeskOutput::synth, DeskOutput::midi, DeskOutput::both};

std::string name(DeskOutput output);
inline bool sounds(DeskOutput output) { return output != DeskOutput::midi; }
inline bool sendsMIDI(DeskOutput output) { return output != DeskOutput::synth; }

struct DeskSettings;

/// How a chord sits in the key: the consonance a target is drawn with.
enum class ChordFit {
    inKey,
    /// In the key, with a tone a semitone over another.
    tense,
    /// A note from outside the key.
    borrowed,
};

/// A chord as played: a spec in a key. A borrowed chord is a degree of the
/// key it is borrowed from, as the octave layout plays one (`KeyDegree`).
struct DeskChord {
    theory::Key key;
    theory::ChordSpec spec;
    /// The notes it is sounded on, when they were chosen one voice at a
    /// time (`VoiceLeading`) rather than worked out from the voicing set.
    std::optional<std::vector<int>> voicing;

    DeskChord(const theory::Key &key, const theory::ChordSpec &spec,
              std::optional<std::vector<int>> voicing = std::nullopt);

    DeskChord(const theory::Key &key, theory::Degree degree,
              const theory::ChordColor &color = theory::ChordColor::base());

    /// The chord `tones` on `root`, read in `home`: its own degree there, or
    /// borrowed from the parallel mode nearest it. (Swift's
    /// `init(root:tones:in:voicing:)`.)
    static DeskChord onRoot(theory::PitchClass root, const theory::ChordTones &tones, const theory::Key &home,
                            std::optional<std::vector<int>> voicing = std::nullopt);

    bool operator==(const DeskChord &) const = default;
    auto operator<=>(const DeskChord &) const = default;

    theory::PitchClass root() const;
    theory::ChordTones tones() const;
    /// "G 7", "C/E"; a voiced chord over another of its notes is named over
    /// that bass, "A min/C".
    std::string name() const;

    /// The notes it sounds with `settings`' octave and inversion, voice-led
    /// from `previous` if they say so.
    /// A voiced chord sounds its own notes, moved by octaves only.
    std::vector<int> notes(const DeskSettings &settings, int octaveShift = 0, int roll = 0,
                           const std::optional<std::vector<int>> &previous = std::nullopt) const;

    /// How it sits in `home`: every note in it, or not.
    ChordFit fit(const theory::Key &home) const;

    // From Layout.swift.

    /// Whether `other` is one step from this: a note added, taken away or
    /// moved a semitone, the root kept.
    bool isOneStep(const std::optional<DeskChord> &other) const;

    /// The pitch classes it sounds, as notes of the octave.
    std::set<int> pitchClasses() const;

    /// Whether it shares two notes with `other`: the smooth moves between
    /// degrees.
    bool sharesTwo(const std::optional<DeskChord> &other) const;
};

/// What every layout shares: the key, the voicing, the sounds and where they
/// go. A sound is named by its preset's id (`SynthPreset.rawValue`), so the
/// core needs nothing of the audio.
struct DeskSettings {
    theory::Key key = {theory::PitchClass::C, theory::ScaleType::major};
    /// The chord's octave, as `computeVoicing` takes it: 4 puts C's chord on
    /// middle C.
    int octave = 4;
    theory::Inversion inversion = theory::Inversion::root();
    /// Whether each chord is voiced as near the last as it can be.
    bool voiceLeading = false;
    std::string chordSound = "electricPiano";
    std::string lineSound = "soloLead";
    double tempo = 96.0;
    DeskOutput output = DeskOutput::both;
    /// The order of the step compass's choices, where a layout uses it.
    theory::ColorStepRanking ranking = theory::ColorStepRanking::theory;
    /// How the color ring is laid round the stick (home to start with).
    RingArrangement ringArrangement;
    /// The order the ring's sectors go round in, and which cells it lets
    /// through (brightness and all to start with).
    RingOrder ringOrder;
    RingFilter ringFilter;
    /// The grid the arranger snaps its times to (sixteenths to start with).
    BeatGrid grid;
    /// Colors pinned to the chords of keys, in named tables.
    Favorites favorites;
    /// What LB puts on the sticks in Twin rings.
    LBLayer lbLayer = LBLayer::compass;
    /// Which chords and notes can be played, and what the guard has heard.
    ConsonanceGuard consonance;

    DeskSettings();

    bool operator==(const DeskSettings &) const = default;

    /// The ring laid the next way round (`steps` < 0, the way before).
    void moveRingArrangement(int steps);

    static constexpr ClosedRange<int> octaves = {1, 6};
    static constexpr ClosedRange<double> tempos = {40.0, 220.0};
    /// The scales a key can be in: the heptatonic ones, where every degree
    /// stacks thirds.
    static constexpr std::array<theory::ScaleType, 7> scales = {
        theory::ScaleType::major,  theory::ScaleType::naturalMinor, theory::ScaleType::harmonicMinor,
        theory::ScaleType::melodicMinor, theory::ScaleType::dorian, theory::ScaleType::mixolydian,
        theory::ScaleType::lydian,
    };

    /// The octave `steps` up (down, below 0), within reach.
    void moveOctave(int steps);

    /// The inversion `steps` further, within two octaves of root position
    /// either way.
    void roll(int steps);

    /// The key a fifth up (`steps` > 0) or down, round the circle of fifths.
    void moveKey(int fifths);

    /// The next scale of `scales` (`steps` < 0, the one before).
    void moveScale(int steps);

    /// "C Major · 4 / root".
    std::string summary() const;

    std::string voicingName() const;

    // From Arrangement.swift.

    /// The grid laid the next way (`steps` < 0, the way before).
    void moveGrid(int steps);

    // From Consonance.swift.

    /// Whether the guard lets `chord` be played now.
    bool playable(const DeskChord &chord) const;

    /// The guard's mode the next one along (`steps` < 0, the one before).
    void moveGuard(int steps);

    // From RingPie.swift.

    /// The ring for `degree` as these settings lay it, turned to nearness
    /// from `sounding`.
    RingPie ring(theory::Degree degree, const std::optional<DeskChord> &sounding = std::nullopt) const;

    /// The ring in brightness order, unfiltered: what Petals' triggers step
    /// along, darker and brighter.
    RingPie brightnessRing(theory::Degree degree) const;

    /// The ring's order the next one along (`steps` < 0, the one before).
    void moveRingOrder(int steps);

    void moveRingFilter(int steps);
};

/// A line of notes the shell keeps: the chords, and a single line over them.
/// Each has its own sound and, over MIDI, its own channel.
enum class Line { chord, melody };

inline constexpr std::array<Line, 2> allLines = {Line::chord, Line::melody};

/// A felt event: the controller's motors say what the ear might miss, and
/// the screen says it too ("Rumble is information, never decoration").
enum class Rumble {
    /// A step crossed: a detent, a band, a rate.
    tick,
    /// A move made: a chord changed by a flick, a key changed.
    bump,
    /// A move refused: what was asked for is not playable now.
    refuse,
};

/// What a layout asks the shell to do.
class DeskEffect {
public:
    /// Sound `notes` on `line` in `sound`, in place of what it sounds. Tied,
    /// a note it is sounding already is held over, not struck again.
    struct Sound {
        desk::Line line;
        std::vector<int> notes;
        std::string sound;
        double level;
        double brightness;
        bool tie;
        bool operator==(const Sound &) const = default;
    };
    /// Glide what `line` sounds to a new level and brightness, and a bend in
    /// semitones from its pitch.
    struct Shape {
        desk::Line line;
        double level;
        double brightness;
        double bend;
        bool operator==(const Shape &) const = default;
    };
    /// Let go of everything on `line`.
    struct Silence {
        desk::Line line;
        bool operator==(const Silence &) const = default;
    };
    struct Rumble {
        desk::Rumble rumble;
        bool operator==(const Rumble &) const = default;
    };
    /// Play a short chord in `sound`, to hear it while choosing it.
    struct Preview {
        std::string sound;
        std::vector<int> notes;
        bool operator==(const Preview &) const = default;
    };
    /// Save `bytes` as a Standard MIDI File called `name`.
    struct SaveMIDI {
        std::vector<std::uint8_t> bytes;
        std::string name;
        bool operator==(const SaveMIDI &) const = default;
    };
    /// Something asked for was not played, and why: shown, and felt as
    /// `Rumble::refuse`.
    struct Refuse {
        std::string reason;
        bool operator==(const Refuse &) const = default;
    };

    using Value = std::variant<Sound, Shape, Silence, Rumble, Preview, SaveMIDI, Refuse>;

    template <class Alternative>
        requires std::is_constructible_v<Value, Alternative>
    DeskEffect(Alternative alternative) : value_(std::move(alternative)) {}

    static DeskEffect sound(desk::Line line, std::vector<int> notes, std::string sound, double level,
                            double brightness, bool tie) {
        return Sound{line, std::move(notes), std::move(sound), level, brightness, tie};
    }
    static DeskEffect shape(desk::Line line, double level, double brightness, double bend) {
        return Shape{line, level, brightness, bend};
    }
    static DeskEffect silence(desk::Line line) { return Silence{line}; }
    static DeskEffect rumble(desk::Rumble rumble) { return Rumble{rumble}; }
    static DeskEffect preview(std::string sound, std::vector<int> notes) {
        return Preview{std::move(sound), std::move(notes)};
    }
    static DeskEffect saveMIDI(std::vector<std::uint8_t> bytes, std::string name) {
        return SaveMIDI{std::move(bytes), std::move(name)};
    }
    static DeskEffect refuse(std::string reason) { return Refuse{std::move(reason)}; }

    const Value &value() const { return value_; }

    bool operator==(const DeskEffect &) const = default;

private:
    Value value_;
};

/// The rates an arpeggio can step at, in beats a note.
enum class ArpeggioRate { quarter = 1, eighth, sixteenth };

inline constexpr std::array<ArpeggioRate, 3> allArpeggioRates = {ArpeggioRate::quarter, ArpeggioRate::eighth,
                                                                 ArpeggioRate::sixteenth};

double beats(ArpeggioRate rate);
/// "♩", "♪", "♬".
std::string name(ArpeggioRate rate);

/// A line of chords: what it is sounding, how loud and bright, and an
/// arpeggio that plays the chord a note at a time when one is on. Every
/// layout plays its chords through one, so they all strike, tie, swell and
/// arpeggiate alike.
class ChordLine {
public:
    desk::Line line;

    ChordLine() : line(desk::Line::chord) {}
    explicit ChordLine(desk::Line line) : line(line) {}

    bool operator==(const ChordLine &) const = default;

    const std::optional<DeskChord> &chord() const { return chord_; }
    /// The notes of the chord sounding (all of them, when arpeggiated).
    const std::vector<int> &notes() const { return notes_; }
    bool isSounding() const { return isSounding_; }
    double level() const { return level_; }
    double brightness() const { return brightness_; }
    /// The arpeggio's rate; none plays the chord whole.
    std::optional<ArpeggioRate> arpeggio() const { return arpeggio_; }

    /// The note of the arpeggio sounding, if one is.
    std::optional<int> arpeggioNote() const;

    /// Sounds `chord` from silence, or in place of what sounds.
    std::vector<DeskEffect> strike(const DeskChord &chord, double level, double brightness,
                                   const DeskSettings &settings, double time);
    /// With the brightness whole.
    std::vector<DeskEffect> strike(const DeskChord &chord, double level, const DeskSettings &settings, double time) {
        return strike(chord, level, 1, settings, time);
    }

    /// The chord is now `chord`: heard at once, tied, if the line is
    /// sounding, and otherwise kept for the next strike.
    std::vector<DeskEffect> change(const DeskChord &chord, const DeskSettings &settings);

    /// The voicing changed: what sounds moves to it, tied.
    std::vector<DeskEffect> revoice(const DeskSettings &settings);

    /// Moves the chord from the settings' voicing: a bend held by a stick.
    std::vector<DeskEffect> bend(int octaves, int roll, const DeskSettings &settings);

    /// Glides what sounds to `level` and `brightness`.
    std::vector<DeskEffect> shape(double level, double brightness);

    std::vector<DeskEffect> release();

    /// Plays the chord a note at a time at `rate`, or whole with none.
    std::vector<DeskEffect> arpeggiate(std::optional<ArpeggioRate> rate, const DeskSettings &settings, double time);

    /// The arpeggio's next note, when its time has come.
    std::vector<DeskEffect> tick(const DeskSettings &settings, double time) { return advance(settings, time); }

private:
    std::optional<DeskChord> chord_;
    std::vector<int> notes_;
    bool isSounding_ = false;
    double level_ = 0.8;
    double brightness_ = 1.0;
    std::optional<ArpeggioRate> arpeggio_;
    /// When the arpeggio started, and the note of it sounding.
    double arpeggioStart_ = 0.0;
    int arpeggioStep_ = -1;
    /// Where the chord is moved from the settings' voicing.
    int octaveShift_ = 0;
    int roll_ = 0;

    std::vector<DeskEffect> advance(const DeskSettings &settings, double time);
    DeskEffect sound(const std::vector<int> &notes, const DeskSettings &settings, bool tie) const;
};

/// The diatonic cycle of thirds: I iii V vii° ii IV vi. Neighbours share two
/// notes, and it closes (vi back to I shares two), so a thumb rolling round
/// a pie in this order makes the smoothest chain of chords the key has.
namespace DiatonicCycle {

inline constexpr std::array<theory::Degree, 7> thirds = {
    theory::Degree::I,  theory::Degree::iii, theory::Degree::V, theory::Degree::viiDim,
    theory::Degree::ii, theory::Degree::IV,  theory::Degree::vi,
};

/// The degree `steps` thirds from `degree` round the cycle.
theory::Degree degree(int steps, theory::Degree from);

} // namespace DiatonicCycle

/// The key's seven degrees round a stick in scale order, I at the top and
/// on clockwise: I ii iii IV V vi vii°.
namespace DegreePie {

const PieGate &gate();
inline constexpr std::array<theory::Degree, 7> order = theory::allDegrees;

inline theory::Degree degree(int sector) { return order[static_cast<size_t>(sector)]; }
int sector(theory::Degree degree);

} // namespace DegreePie

} // namespace perfecto::desk

#endif
