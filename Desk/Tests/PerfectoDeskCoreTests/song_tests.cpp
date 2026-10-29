// The timeline's song: layers of events, loops, and the edits.

#include <doctest.h>

#include "perfecto/desk/song.hpp"

#include <vector>

using namespace perfecto::desk;
using namespace perfecto::theory;

namespace {

const Key c = {PitchClass::C, ScaleType::major};

ChordPart part(Degree degree, int voice = 0) {
    const DeskChord chord(c, degree);
    return {voice, chord, chord.notes(DeskSettings())};
}

Event event(int id, double start, double length, Degree degree = Degree::I, int voice = 0) {
    return {id, start, length, part(degree, voice)};
}

/// The events' starts and ends, in order.
std::vector<std::pair<double, double>> times(const Layer &layer) {
    std::vector<std::pair<double, double>> out;
    for (const Event &e : layer.events) out.emplace_back(e.start, e.end());
    return out;
}

using Times = std::vector<std::pair<double, double>>;

/// I IV V vi, a beat each, legato.
Layer legato() { return {1, {event(2, 0, 1), event(3, 1, 1, Degree::IV), event(4, 2, 1, Degree::V), event(5, 3, 1, Degree::vi)}}; }

} // namespace

TEST_SUITE("Song") {

TEST_CASE("a choice runs from one event to another, either way round") {
    const Layer layer = legato();
    CHECK(layer.between(3, 5) == std::set<int>{3, 4, 5});
    CHECK(layer.between(5, 3) == std::set<int>{3, 4, 5});
    CHECK(layer.between(4, 4) == std::set<int>{4});
    CHECK(layer.between(4, 99).empty());
    CHECK(layer.span({3, 4}) == Span{1, 3});
}

TEST_CASE("a nudge moves a chord's start and keeps the progression legato") {
    const Layer layer = nudged(legato(), {3}, 0.25);
    // IV starts later: I is held on until it does, and IV still ends where V starts.
    CHECK(times(layer) == Times{{0, 1.25}, {1.25, 2}, {2, 3}, {3, 4}});
    CHECK(times(nudged(legato(), {3}, -0.25)) == Times{{0, 0.75}, {0.75, 2}, {2, 3}, {3, 4}});
}

TEST_CASE("chords nudged together move together") {
    CHECK(times(nudged(legato(), {3, 4}, 0.5)) == Times{{0, 1.5}, {1.5, 2.5}, {2.5, 3}, {3, 4}});
}

TEST_CASE("a nudge never passes the chord before or after, nor the start") {
    CHECK(nudgeReach(legato(), {3}, 5) == doctest::Approx(1 - shortestEvent));
    CHECK(nudgeReach(legato(), {3}, -5) == doctest::Approx(-(1 - shortestEvent)));
    CHECK(nudgeReach(legato(), {2}, -1) == 0);
    CHECK(times(nudged(legato(), {3}, 5)) == Times{{0, 2 - shortestEvent}, {2 - shortestEvent, 2}, {2, 3}, {3, 4}});
}

TEST_CASE("a chord let go of before the next keeps its length when nudged, and is cut short by the next") {
    const Layer staccato{1, {event(2, 0, 0.5), event(3, 1, 0.5, Degree::IV)}};
    CHECK(times(nudged(staccato, {2}, 0.25)) == Times{{0.25, 0.75}, {1, 1.5}});
    CHECK(times(nudged(staccato, {2}, 0.75)) == Times{{0.75, 1}, {1, 1.5}});
}

TEST_CASE("each voice is its own channel: a nudge on one leaves the other alone") {
    const Layer two{1, {event(2, 0, 1), event(3, 0, 2, Degree::V, 1), event(4, 1, 1, Degree::IV)}};
    const Layer moved = nudged(two, {4}, -0.5);
    CHECK(times(moved) == Times{{0, 0.5}, {0, 2}, {0.5, 1.5}});
}

TEST_CASE("quantize puts starts and ends on the grid, and keeps legato") {
    const Layer loose{1, {event(2, 0.1, 0.9), event(3, 1.0, 1.15, Degree::IV), event(4, 2.15, 0.6, Degree::V)}};
    CHECK(times(quantized(loose, {2, 3, 4}, 0.5)) == Times{{0, 1}, {1, 2}, {2, 3}});
    // Only what is chosen moves.
    CHECK(times(quantized(loose, {4}, 0.5)) == Times{{0.1, 1}, {1, 2}, {2, 3}});
}

TEST_CASE("a chord quantized onto the next is gone") {
    const Layer grace{1, {event(2, 0.9, 0.05), event(3, 0.95, 1, Degree::IV)}};
    const Layer done = quantized(grace, {2, 3}, 1);
    REQUIRE(done.events.size() == 1);
    CHECK(done.events[0].id == 3);
    CHECK(times(done) == Times{{1, 2}});
}

TEST_CASE("rechording keeps every chord's time") {
    const Layer layer = rechorded(legato(), {3, 4}, part(Degree::ii));
    CHECK(times(layer) == times(legato()));
    CHECK(layer.events[1].part == Part{part(Degree::ii)});
    CHECK(layer.events[2].part == Part{part(Degree::ii)});
    CHECK(layer.events[0].part == legato().events[0].part);
    // Another voice's chords are not this one's.
    CHECK(rechorded(legato(), {3}, part(Degree::ii, 1)) == legato());
}

TEST_CASE("a loop is the choice's span, on whole beats") {
    const Layer loose{1, {event(2, 0.1, 0.9), event(3, 1.0, 1.15, Degree::IV)}};
    CHECK(looped(loose, {2, 3}).loop == Span{0, 2});
    CHECK(looped(loose, {2}).loop == Span{0, 1});
    CHECK(looped(Layer{1, {event(2, 0.2, 0.2)}}, {2}).loop == Span{0, 1});
}

TEST_CASE("a loop repeats either way from where it was recorded, cut to its span") {
    Layer layer = legato();
    layer.loop = Span{1, 3};
    Song song{{layer}, 9};
    std::vector<std::tuple<double, double, int>> heard;
    for (const auto &o : song.heard(layer, 0, 7)) heard.emplace_back(o.start, o.end, o.id);
    CHECK(heard == std::vector<std::tuple<double, double, int>>{
                       {0, 1, 4}, {1, 2, 3}, {2, 3, 4}, {3, 4, 3}, {4, 5, 4}, {5, 6, 3}, {6, 7, 4}});
    CHECK(song.isEndless());
    CHECK(song.end() == std::nullopt);
}

TEST_CASE("onsets are what starts in a window, what sounds at its start too when entering") {
    Song song{{legato(), Layer{6, {event(7, 0.5, 2, Degree::V)}}}, 8};
    const auto onsets = song.onsets(0.5, 2);
    REQUIRE(onsets.size() == 2);
    CHECK(onsets[0].id == 7);
    CHECK(onsets[0].track == Track{6, 0});
    CHECK(onsets[1].id == 3);
    const auto entering = song.onsets(0.5, 2, std::nullopt, true);
    REQUIRE(entering.size() == 3);
    CHECK(entering[0].id == 2);
    CHECK(entering[0].start == 0.5);
    CHECK(song.onsets(0.5, 2, 6).size() == 1);
}

TEST_CASE("a muted layer is not heard, and the song ends with what is") {
    Layer quiet{6, {event(7, 0, 10)}};
    quiet.isMuted = true;
    Song song{{legato(), quiet}, 8};
    CHECK(song.end() == 4);
    CHECK(song.onsets(0, 1).size() == 1);
}

TEST_CASE("erasing and shifting") {
    CHECK(times(erased(legato(), {3, 4})) == Times{{0, 1}, {3, 4}});
    Layer layer = legato();
    layer.loop = Span{1, 2};
    const Layer later = shifted(layer, 2);
    CHECK(times(later) == Times{{2, 3}, {3, 4}, {4, 5}, {5, 6}});
    CHECK(later.loop == Span{3, 4});
}

}
