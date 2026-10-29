// Model 5, the couch arranger: the other layouts play, this one writes. The
// two sticks aim a chord as Twin rings does, and it is placed in four bars
// of time, each chord as long as it is held:
//
// - Stopped, RT held at the cursor writes the chord for as long as it is
//   held, at the tempo: the chord sounds and grows on the screen, a tick is
//   felt on each beat, and the length is snapped to the grid on letting go.
// - Playing, RT writes at the playhead, live: the chord starts where it was
//   struck and is as long as it was held.
// - LB and RB shorten and lengthen the chord at the cursor: a tap by a line
//   of the grid, a hold smoothly for as long as it is held.
//
// Y plays the bars round, through the same sound and MIDI as everything
// else, and the menu saves them as a MIDI file.

#ifndef PERFECTO_DESK_ARRANGER_HPP
#define PERFECTO_DESK_ARRANGER_HPP

#include "perfecto/desk/arrangement.hpp"
#include "perfecto/desk/gates.hpp"
#include "perfecto/desk/layout.hpp"
#include "perfecto/desk/music.hpp"
#include "perfecto/desk/pad.hpp"
#include "perfecto/desk/ring_pie.hpp"

#include <perfecto/theory/key.hpp>
#include <perfecto/theory/midi_file.hpp>

#include <functional>
#include <optional>
#include <vector>

namespace perfecto::desk {

class Arranger {
public:
    /// A chord being written by RT.
    struct Writing {
        double start;
        /// When RT struck, and how long it has been held, in beats.
        double since;
        double length;
        /// Written at the playhead while playing, not at the cursor.
        bool isLive;

        bool operator==(const Writing &) const = default;
    };

    /// When playing began, and the beat it began from. (Swift's tuple.)
    struct Playing {
        double since;
        double from;

        bool operator==(const Playing &) const = default;
    };

    /// How fast a bumper held stretches a chord, in beats a second.
    static constexpr double stretchRate = 2.0;
    /// How long a bumper is held before it stretches smoothly.
    static constexpr double stretchDelay = 0.3;

    Arranger() = default;

    bool operator==(const Arranger &) const = default;

    const Arrangement &arrangement() const { return arrangement_; }
    /// Where the next chord is written, in beats.
    double cursor() const { return cursor_; }
    theory::Degree degree() const { return degree_; }
    const std::optional<RingCell> &aim() const { return aim_; }
    const std::optional<Writing> &writing() const { return writing_; }
    /// When playing began, and the beat it began from; none while stopped.
    const std::optional<Playing> &playing() const { return playing_; }
    /// Where the playing is, in beats, while it plays.
    std::optional<double> playhead() const { return playhead_; }
    const ChordLine &line() const { return line_; }

    std::vector<DeskEffect> step(const PadInput &input, DeskSettings &settings);

    /// The chord the sticks aim at.
    DeskChord aimed(const DeskSettings &settings) const;

    std::vector<DeskEffect> releaseAll();

    /// The arrangement as a Standard MIDI File: one track of its chords, each
    /// as long as it was written, at the tempo and in the key set.
    std::optional<theory::MidiFile> midiFile(const DeskSettings &settings) const;

    // What the screen shows

    std::vector<Target> degreeTargets(const DeskSettings &settings) const;

    Legend legend(const DeskSettings &settings) const;

private:
    /// A chord being made longer or shorter by a bumper.
    struct Stretch {
        double start;
        double from;
        double direction;
        double since;

        bool operator==(const Stretch &) const = default;
    };

    /// The chord heard from the arrangement, by its start, and the time
    /// round the loop it is heard in. (Swift's tuple.)
    struct Heard {
        double start;
        int round;

        bool operator==(const Heard &) const = default;
    };

    Arrangement arrangement_;
    double cursor_ = 0.0;
    theory::Degree degree_ = theory::Degree::I;
    std::optional<int> degreeSector_ = DegreePie::sector(theory::Degree::I);
    std::optional<RingCell> aim_;
    std::optional<int> ringSector_;
    std::optional<int> band_;
    std::optional<Writing> writing_;
    std::optional<Stretch> stretch_;
    std::optional<Playing> playing_;
    std::optional<double> playhead_;
    std::optional<Heard> heard_;
    ChordLine line_;
    std::vector<Arrangement> undo_;
    TriggerStrike commit_;
    bool isAuditioning_ = false;
    /// The beat a write or a stretch last ticked on.
    int ticked_ = 0;

    /// Makes an edit that undo can take back.
    void edit(const std::function<void(Arrangement &)> &change);

    /// `beats` round the loop.
    static double wrap(double beats);
};

} // namespace perfecto::desk

#endif
