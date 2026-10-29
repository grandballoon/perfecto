// The timeline: a bar along the top of Face Chords that records what is
// played, layer over layer, plays it back, and edits it.
//
// RT held is the timeline's hand, as RB is the drums' and LT the chords'
// second layer; it leaves R3 and LB to the second voice and L3 and RB to the
// drums. A button pressed while RT is held is the timeline's until it is let
// go, so it never reaches the chords:
//
// - A records a new layer, from the selection's start or the song's, with
//   every other layer playing along; again stops recording.
// - X plays from the same place, and stops.
// - ← and → choose the chord before or after; with LT held too, they
//   stretch the choice over several.
// - ↑ and ↓ choose the layer.
// - Y loops the chosen span: the layer repeats it for as long as the song
//   plays, in step with where it was recorded. With nothing chosen it ends
//   the layer's loop.
// - B quantizes the chosen chords (the whole layer, with none) to the grid.
// - The right stick nudges the chosen chords a 32nd of a beat earlier or
//   later (left, right; held, again and again), by a line of the grid with
//   LT; up mutes the layer, down deletes the chosen chords.
// - The left stick undoes (left) and redoes (right).
// - RT tapped alone lets go of the choice.
//
// With chords chosen, a chord played is written into them, each at its own
// time: the progression changes and its rhythm does not.
//
// Times are in beats, at the desk's tempo, so a song recorded at one tempo
// plays at another. What plays back is worked out a little ahead
// (`lookahead`) and stamped with the moment it sounds, so the shell places
// it on its exact frame however unevenly the desk is stepped.
//
// It has no Swift original: the timeline is the Godot desk's alone, played
// beside the desk (`Studio`) and not inside it, so the desk the parity test
// plays is unchanged.

#ifndef PERFECTO_DESK_TIMELINE_HPP
#define PERFECTO_DESK_TIMELINE_HPP

#include "perfecto/desk/gates.hpp"
#include "perfecto/desk/music.hpp"
#include "perfecto/desk/pad.hpp"
#include "perfecto/desk/song.hpp"

#include <map>
#include <optional>
#include <set>
#include <string>
#include <type_traits>
#include <variant>
#include <vector>

namespace perfecto::desk {

/// What the timeline asks the shell to sound. A time is on the frames'
/// clock, and may be a little ahead of the frame that asked; one already
/// past is as soon as can be.
class TimelineEffect {
public:
    /// Sound `notes` on `track` in `sound` at `time`, in place of what it
    /// sounds.
    struct Sound {
        Track track;
        std::vector<int> notes;
        std::string sound;
        double level;
        double time;
        bool operator==(const Sound &) const = default;
    };
    /// Let go of what `track` sounds, at `time`.
    struct Silence {
        Track track;
        double time;
        bool operator==(const Silence &) const = default;
    };
    /// Let go of everything the timeline sounds, now.
    struct Hush {
        bool operator==(const Hush &) const = default;
    };

    using Value = std::variant<Sound, Silence, Hush>;

    template <class Alternative>
        requires std::is_constructible_v<Value, Alternative>
    TimelineEffect(Alternative alternative) : value_(std::move(alternative)) {}

    static TimelineEffect sound(Track track, std::vector<int> notes, std::string sound, double level, double time) {
        return Sound{track, std::move(notes), std::move(sound), level, time};
    }
    static TimelineEffect silence(Track track, double time) { return Silence{track, time}; }
    static TimelineEffect hush() { return Hush{}; }

    const Value &value() const { return value_; }

    bool operator==(const TimelineEffect &) const = default;

private:
    Value value_;
};

/// What each voice of chords is sounding now, by voice.
using Heard = std::map<int, ChordPart>;

class Timeline {
public:
    /// The chords chosen: those from `anchor` to `head` in `layer`.
    struct Selection {
        int layer;
        int anchor;
        int head;
        bool operator==(const Selection &) const = default;
    };

    /// The song playing: at `time` it was at `beat`, going at `tempo`; what
    /// starts before `given` has been handed to the shell, and `heard` is
    /// where it was at the last frame.
    struct Rolling {
        double time;
        double beat;
        double tempo;
        double given;
        double heard;
        bool operator==(const Rolling &) const = default;
    };

    /// A layer being recorded: what each voice is sounding since when, and
    /// whether the take is the song's first, which starts where it was
    /// first played.
    struct Recording {
        int layer;
        bool trims;
        std::map<int, std::pair<double, ChordPart>> open;
        bool operator==(const Recording &) const = default;
    };

    /// What the timeline did: what to sound, and what to feel and show.
    struct Out {
        std::vector<TimelineEffect> playback;
        std::vector<DeskEffect> effects;
        bool operator==(const Out &) const = default;

        void append(Out more);
    };

    /// What the hands did, and the frame left for the desk.
    struct Taken {
        Out out;
        GamepadFrame frame;
        bool operator==(const Taken &) const = default;
    };

    /// How far ahead playback is given, in seconds: more than the longest
    /// frame the desk is stepped at, so nothing is ever found late.
    static constexpr double lookahead = 0.05;
    /// A nudge, in beats.
    static constexpr double fine = 1.0 / 32;
    /// How long the right stick is held before a nudge repeats, and how
    /// often it then does.
    static constexpr double repeatDelay = 0.35;
    static constexpr double repeatEvery = 0.08;
    /// How loud what plays back is: as Face Chords strikes.
    static constexpr double level = 0.8;
    /// The most edits that can be undone.
    static constexpr size_t memory = 100;

    bool operator==(const Timeline &) const = default;

    const Song &song() const { return song_; }
    /// The layer chosen, if there is one.
    const Layer *layer() const;
    const std::optional<Selection> &selection() const { return selection_; }
    /// The ids of the chords chosen.
    std::set<int> selected() const;
    const std::optional<Rolling> &rolling() const { return rolling_; }
    const std::optional<Recording> &recording() const { return recording_; }
    /// Where the song is at `time`, while it plays.
    std::optional<double> playhead(double time) const;
    /// Whether RT holds the timeline.
    bool isLayered() const { return isLayered_; }
    bool canUndo() const { return !undo_.empty() && !recording_; }
    bool canRedo() const { return !redo_.empty() && !recording_; }
    /// The grid's step in beats: a sixteenth with none.
    static double grid(const DeskSettings &settings);

    // The hands.

    /// One frame of the controller. `reachable` says whether the hands can
    /// play the timeline now (Face Chords, the menu closed).
    Taken take(const PadInput &input, bool reachable, const DeskSettings &settings);

    /// What the desk sounds at `time`: recorded, or with chords chosen,
    /// written into them.
    Out hear(const Heard &heard, double time);

    /// What plays back from the last given up to `time` and the lookahead.
    Out advance(double time, const DeskSettings &settings);

    // What the controls do, and the mouse.

    /// Starts recording a new layer, or stops.
    Out record(double time, const DeskSettings &settings);
    /// Plays from the selection's start or the song's, or stops.
    Out play(double time, const DeskSettings &settings);
    /// Stops playing and recording.
    Out stop(double time);
    Out loop();
    Out quantize(const DeskSettings &settings);
    Out erase(double time);
    /// Mutes the layer `id`, or lets it be heard again.
    Out mute(int id, double time);
    /// Chooses the layer `steps` down (up, below 0).
    Out moveLayer(int steps);
    /// Chooses the layer `id`.
    Out chooseLayer(int id);
    /// Chooses the chord `steps` after the one chosen (before, below 0), or
    /// stretches the choice to it.
    Out moveSelection(int steps, bool stretch);
    /// Chooses the event `id` in the layer `layer`, or stretches the choice to it.
    Out select(int layer, int id, bool stretch);
    Out deselect();
    Out nudge(double beats);
    Out undo(double time);
    Out redo(double time);

    /// What the timeline's controls do now, over `legend`.
    Legend legend(Legend legend, bool reachable) const;

private:
    enum class Edit { other, nudge };

    Song song_;
    int layer_ = 0;
    std::optional<Selection> selection_;
    std::optional<Rolling> rolling_;
    std::optional<Recording> recording_;
    /// What each track is sounding until.
    std::map<Track, double> sounding_;
    /// What the desk sounded at the last frame.
    Heard heard_;
    std::vector<Song> undo_;
    std::vector<Song> redo_;
    Edit lastEdit_ = Edit::other;

    bool isLayered_ = false;
    /// Whether RT, since it was pulled, has done nothing: let go, it lets
    /// go of the choice.
    bool isClean_ = false;
    std::set<PadButton> claimed_;
    bool claimsLT_ = false;
    std::optional<PadButton> rightPush_;
    std::optional<PadButton> leftPush_;
    double repeatAt_ = 0;

    double beatAt(double time) const;
    double timeAt(double beat) const;
    double startBeat() const;
    /// Makes `next` the song, remembering this one to undo.
    void edit(Song next, Edit kind = Edit::other);
    /// `layer`, changed, as the song's layer of its id.
    void edit(const Layer &layer, Edit kind = Edit::other);
    Out roll(double time, double beat, const DeskSettings &settings);
    Out schedule(double from, double to, bool entering, const DeskSettings &settings);
    Out finishRecording(double time);
    /// Lets go of what tracks no longer heard sound, and of a choice of
    /// what is gone.
    Out settle(double time);
    Out act(PadButton button, const PadInput &input, const DeskSettings &settings);
};

} // namespace perfecto::desk

#endif
