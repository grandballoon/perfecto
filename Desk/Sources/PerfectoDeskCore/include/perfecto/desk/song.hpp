// The timeline's song: what was recorded, as values with their edits. A song
// is layers laid over one another, each a recording of events in beats; a
// layer can loop a span of itself, which then repeats for as long as the
// song plays, in step with where it was recorded. Every edit is a pure
// function of a layer and the events chosen, so the timeline only decides
// when to make them.
//
// An event is what one part played from one moment to another. The parts so
// far are the voices of chords (the first, and the second to come); a drum's
// hit is to be another alternative of `Part`, with a channel of its own, and
// nothing else here changes for it.
//
// It has no Swift original: the timeline is the Godot desk's alone (see
// `timeline.hpp`).

#ifndef PERFECTO_DESK_SONG_HPP
#define PERFECTO_DESK_SONG_HPP

#include "perfecto/desk/music.hpp"

#include <compare>
#include <optional>
#include <set>
#include <variant>
#include <vector>

namespace perfecto::desk {

/// A chord a voice played, and the notes it sounded them on.
struct ChordPart {
    /// 0 the first voice, 1 the second.
    int voice = 0;
    DeskChord chord;
    std::vector<int> notes;

    bool operator==(const ChordPart &) const = default;
};

/// What an event plays.
using Part = std::variant<ChordPart>;

/// The channel `part` plays on in its layer: one sound at a time on each,
/// so an event on a channel ends where the next on it starts at the latest.
int channel(const Part &part);

/// Something played: a part from `start` for `length` beats.
struct Event {
    /// Which it is, through every edit: unique in the song.
    int id;
    double start;
    double length;
    Part part;

    bool operator==(const Event &) const = default;

    double end() const { return start + length; }
};

/// From one beat to another.
struct Span {
    double from;
    double to;

    bool operator==(const Span &) const = default;

    double length() const { return to - from; }
};

/// One recording: its events in order of their starts, and the span it
/// loops, if it does.
struct Layer {
    /// Which it is, through every edit: unique in the song.
    int id;
    std::vector<Event> events;
    std::optional<Span> loop;
    bool isMuted = false;

    bool operator==(const Layer &) const = default;

    /// The events in `ids`, in order.
    std::vector<Event> chosen(const std::set<int> &ids) const;

    /// The ids of the events from `a` to `b` (either way round), in order;
    /// none if either is not here.
    std::set<int> between(int a, int b) const;

    /// From the first of `ids`' starts to the last of their ends.
    std::optional<Span> span(const std::set<int> &ids) const;
};

/// Where a sound plays: a layer, and a channel in it.
struct Track {
    int layer;
    int channel;

    bool operator==(const Track &) const = default;
    auto operator<=>(const Track &) const = default;
};

/// An event as heard at a place in the song: a loop's repetitions are each
/// one, cut to the loop.
struct Occurrence {
    double start;
    double end;
    Track track;
    /// The event it is of.
    int id;
    Part part;

    bool operator==(const Occurrence &) const = default;
};

/// Layers of recordings, heard together.
struct Song {
    static constexpr int beatsPerBar = 4;
    /// The most layers there can be.
    static constexpr int most = 8;

    std::vector<Layer> layers;
    /// The next id an event or a layer is given.
    int next = 1;

    bool operator==(const Song &) const = default;

    bool isEmpty() const;

    /// The layer with `id`, if there is one.
    const Layer *layer(int id) const;
    Layer *layer(int id);

    /// Where the song ends: the last end of what is heard that does not
    /// loop; none if it has nothing of that.
    std::optional<double> end() const;

    /// Whether it plays until it is stopped: a layer heard loops.
    bool isEndless() const;

    /// What `layer` sounds over [from, to): each occurrence that sounds in
    /// it, from its start to its end, however far either is outside it.
    std::vector<Occurrence> heard(const Layer &layer, double from, double to) const;

    /// What starts in [from, to) in every layer heard but `skip`, in order;
    /// with `entering`, also what is already sounding at `from`, as starting
    /// there.
    std::vector<Occurrence> onsets(double from, double to, std::optional<int> skip = std::nullopt,
                                   bool entering = false) const;
};

// The edits. Each keeps the events in order and never lets two on a channel
// overlap; an event that runs into the next on its channel (as a chord
// changed without letting go does) still does after it, so a progression
// played legato stays legato.

/// The shortest an edit leaves an event, in beats.
inline constexpr double shortestEvent = 1.0 / 32;

/// `ids` moved `beats` later (earlier, below 0), as far as the events
/// around them let them go: they never pass the one before on their channel
/// or the one after, nor the song's start.
Layer nudged(const Layer &layer, const std::set<int> &ids, double beats);

/// How far `nudged` would move `ids` for `beats`.
double nudgeReach(const Layer &layer, const std::set<int> &ids, double beats);

/// `ids` on the nearest lines of a grid `step` beats apart, their starts and
/// their ends; one that comes to no length is gone.
Layer quantized(const Layer &layer, const std::set<int> &ids, double step);

/// The events of `ids` on `part`'s channel play `part` from now, each at its
/// own time.
Layer rechorded(const Layer &layer, const std::set<int> &ids, const ChordPart &part);

/// The layer loops `ids`' span, its ends on the nearest beats and a beat
/// long at least.
Layer looped(const Layer &layer, const std::set<int> &ids);

/// Without the events of `ids`.
Layer erased(const Layer &layer, const std::set<int> &ids);

/// The events `beats` later.
Layer shifted(const Layer &layer, double beats);

} // namespace perfecto::desk

#endif
