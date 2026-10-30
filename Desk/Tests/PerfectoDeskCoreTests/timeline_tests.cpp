// The timeline, played as the hands play it: Face Chords and the timeline
// together (`Studio`), at 60 bpm, so a beat is a second.

#include <doctest.h>

#include "perfecto/desk/studio.hpp"
#include "rig.hpp"

#include <algorithm>
#include <functional>
#include <vector>

using namespace perfecto::desk;
using namespace perfecto::desk::testing;
using namespace perfecto::theory;

namespace {

const std::vector<int> I = {60, 64, 67}, IV = {65, 69, 72}, V = {67, 71, 74}, viiDim = {71, 74, 77};

DeskSettings slow() {
    DeskSettings settings;
    settings.tempo = 60;
    return settings;
}

/// Steps a studio through frames, keeping the frame before.
struct StudioRig {
    Studio studio{Desk(SoundCatalog({}), slow(), LayoutKind::faceChords)};
    GamepadFrame last = GamepadFrame{.time = 0};

    Studio::Played at(double time, const std::function<void(GamepadFrame &)> &change = {}) {
        GamepadFrame frame = last;
        frame.time = time;
        if (change) change(frame);
        last = frame;
        return studio.step(frame);
    }

    /// Holds `buttons` alone, RT pulled or not.
    Studio::Played hold(double time, std::set<PadButton> buttons, bool rt = false, double lt = 0) {
        return at(time, [&](GamepadFrame &f) {
            f.buttons = std::move(buttons);
            f.rightTrigger = rt ? 1 : 0;
            f.leftTrigger = lt;
        });
    }

    const Timeline &timeline() const { return studio.timeline(); }
    const Song &song() const { return timeline().song(); }
};

/// Plays I for a beat and IV for one, legato, half a beat after `time` (60
/// bpm), then stops recording: a first take, so it starts at the song's start.
void playTwo(StudioRig &rig, double time) {
    rig.hold(time + 0.1, {});
    rig.hold(time + 0.5, {PadButton::a});  // I, half a beat in
    rig.hold(time + 1.5, {PadButton::b});  // IV, legato
    rig.hold(time + 2.5, {});
    rig.hold(time + 3, {PadButton::a}, true);  // stop recording
    rig.hold(time + 3.1, {});
}

void recordTwo(StudioRig &rig, double time) {
    rig.hold(time, {PadButton::a}, true);  // record
    playTwo(rig, time);
}

std::vector<std::pair<double, double>> times(const Layer &layer) {
    std::vector<std::pair<double, double>> out;
    for (const Event &e : layer.events) out.emplace_back(e.start, e.end());
    return out;
}

using Times = std::vector<std::pair<double, double>>;

std::vector<std::vector<int>> notes(const Layer &layer) {
    std::vector<std::vector<int>> out;
    for (const Event &e : layer.events) out.push_back(std::get<ChordPart>(e.part).notes);
    return out;
}

/// What plays back, as (time, notes) for a sound and (time, {}) for a silence.
std::vector<std::pair<double, std::vector<int>>> cues(const std::vector<TimelineEffect> &playback) {
    std::vector<std::pair<double, std::vector<int>>> out;
    for (const auto &effect : playback) {
        if (const auto *sound = std::get_if<TimelineEffect::Sound>(&effect.value()))
            out.emplace_back(sound->time, sound->notes);
        if (const auto *silence = std::get_if<TimelineEffect::Silence>(&effect.value())) out.emplace_back(silence->time, std::vector<int>{});
    }
    return out;
}

using Cues = std::vector<std::pair<double, std::vector<int>>>;

bool hushes(const std::vector<TimelineEffect> &playback) {
    return std::find(playback.begin(), playback.end(), TimelineEffect::hush()) != playback.end();
}

} // namespace

TEST_SUITE("Timeline") {

TEST_CASE("RT + A records what is played, the first take from its first chord") {
    StudioRig rig;
    const auto started = rig.hold(10, {PadButton::a}, true);
    // A was the timeline's: it struck nothing.
    CHECK(sounded(started.effects).empty());
    REQUIRE(rig.timeline().recording());
    playTwo(rig, 10);
    CHECK_FALSE(rig.timeline().recording());
    REQUIRE(rig.song().layers.size() == 1);
    const Layer &take = rig.song().layers[0];
    CHECK(times(take) == Times{{0, 1}, {1, 2}});
    CHECK(notes(take) == std::vector<std::vector<int>>{I, IV});
    // The take is chosen, and stopping it at its end stops the song.
    CHECK(rig.timeline().layer() == &take);
    CHECK_FALSE(rig.timeline().rolling());
}

TEST_CASE("a take with nothing played is not kept") {
    StudioRig rig;
    rig.hold(1, {PadButton::a}, true);
    rig.hold(1.1, {});
    rig.hold(2, {PadButton::a}, true);
    CHECK(rig.song().layers.empty());
    CHECK_FALSE(rig.timeline().canUndo());
}

TEST_CASE("RT + X plays it back, each chord stamped with when it sounds") {
    StudioRig rig;
    recordTwo(rig, 10);
    auto played = rig.hold(20, {PadButton::x}, true);
    CHECK(cues(played.playback) == Cues{{20, I}});
    // Nothing is due until the lookahead reaches the next chord.
    CHECK(cues(rig.hold(20.5, {}).playback).empty());
    played = rig.at(20.96);
    CHECK(cues(played.playback) == Cues{{21, {}}, {21, IV}});
    played = rig.at(21.96);
    CHECK(cues(played.playback) == Cues{{22, {}}});
    // At the song's end it stops.
    played = rig.at(22.01);
    CHECK(hushes(played.playback));
    CHECK_FALSE(rig.timeline().rolling());
}

TEST_CASE("RT + X pauses where it is, and plays on from there") {
    StudioRig rig;
    recordTwo(rig, 10);
    rig.hold(20, {PadButton::x}, true);
    rig.hold(20.1, {}, true);
    const auto paused = rig.hold(20.5, {PadButton::x}, true);
    CHECK(hushes(paused.playback));
    CHECK_FALSE(rig.timeline().rolling());
    REQUIRE(rig.timeline().cue());
    CHECK(*rig.timeline().cue() == doctest::Approx(0.5));
    auto bar = timelineBar(rig.timeline(), 25);
    CHECK(bar.status == "Paused · bar 1 · beat 1");
    CHECK(bar.playhead == doctest::Approx(0.5));
    CHECK_FALSE(bar.isPlaying);
    CHECK(bar.controls[1].icon == TimelineBar::Icon::play);
    // Played again, I goes on from half way through it.
    rig.hold(29.9, {}, true);
    const auto resumed = rig.hold(30, {PadButton::x}, true);
    CHECK(cues(resumed.playback) == Cues{{30, I}});
    CHECK(timelineBar(rig.timeline(), 30).controls[1].icon == TimelineBar::Icon::pause);
    CHECK(cues(rig.at(30.46).playback) == Cues{{30.5, {}}, {30.5, IV}});
}

TEST_CASE("RT + LT + X goes back to the start, and plays on from there if it plays") {
    StudioRig rig;
    recordTwo(rig, 10);
    rig.hold(20, {PadButton::x}, true);
    rig.hold(20.1, {}, true);
    const auto back = rig.hold(21.5, {PadButton::x}, true, 1);
    CHECK(hushes(back.playback));
    CHECK(cues(back.playback) == Cues{{21.5, I}});
    CHECK(rig.timeline().playhead(21.5) == 0);
    // Paused and taken back, it is at the start.
    rig.hold(21.6, {}, true);
    rig.hold(21.7, {PadButton::x}, true);
    REQUIRE(rig.timeline().cue());
    rig.hold(21.8, {}, true, 1);
    rig.hold(21.9, {PadButton::x}, true, 1);
    CHECK_FALSE(rig.timeline().cue());
    CHECK_FALSE(rig.timeline().rolling());
}

TEST_CASE("paused past the end, it plays from the start again") {
    StudioRig rig;
    recordTwo(rig, 10);
    rig.hold(20, {PadButton::x}, true);
    rig.hold(20.1, {}, true);
    rig.hold(21.5, {PadButton::x}, true);  // paused in IV
    rig.hold(21.6, {}, true);
    rig.hold(21.7, {PadButton::left}, true);  // IV, the last chord
    rig.at(21.8, [](GamepadFrame &f) { f.right = lean(180); });  // deleted: the song now ends at 1
    rig.at(21.9, [](GamepadFrame &f) { f.right = Stick::rest(); });
    REQUIRE(rig.song().end() == 1);
    REQUIRE(rig.timeline().cue() == 1.5);
    const auto played = rig.hold(22, {PadButton::x}, true);
    CHECK(cues(played.playback) == Cues{{22, I}});
}

TEST_CASE("a change of tempo is heard from where the song is") {
    StudioRig rig;
    recordTwo(rig, 10);
    rig.hold(20, {PadButton::x}, true);
    rig.hold(20.5, {});
    Timeline timeline = rig.timeline();
    DeskSettings settings = slow();
    settings.tempo = 120;
    // Changed at beat 0.6, the next chord is 0.4 beats on, now a fifth of a second.
    CHECK(cues(timeline.advance(20.6, settings).playback).empty());
    const auto due = cues(timeline.advance(20.76, settings).playback);
    REQUIRE(due.size() == 2);
    CHECK(due[1].first == doctest::Approx(20.8));
    CHECK(due[1].second == IV);
}

TEST_CASE("chords chosen take the chord played, each keeping its time") {
    StudioRig rig;
    recordTwo(rig, 10);
    rig.hold(20, {PadButton::right}, true);  // the first chord
    CHECK(rig.timeline().selected() == std::set<int>{rig.song().layers[0].events[0].id});
    rig.hold(20.1, {});  // RT let go after choosing: the choice stays
    REQUIRE(rig.timeline().selection());
    const auto played = rig.hold(21, {PadButton::y});  // vii° is heard, and written
    CHECK(sounded(played.effects) == std::vector<std::vector<int>>{viiDim});
    CHECK(times(rig.song().layers[0]) == Times{{0, 1}, {1, 2}});
    CHECK(notes(rig.song().layers[0]) == std::vector<std::vector<int>>{viiDim, IV});
    // Undone with the left stick, under RT.
    rig.hold(22, {}, true);
    rig.at(22.1, [](GamepadFrame &f) { f.left = lean(270); });
    CHECK(notes(rig.song().layers[0]) == std::vector<std::vector<int>>{I, IV});
}

TEST_CASE("RT tapped alone lets go of the choice") {
    StudioRig rig;
    recordTwo(rig, 10);
    rig.hold(20, {PadButton::right}, true);
    rig.hold(20.1, {});
    REQUIRE(rig.timeline().selection());
    rig.hold(21, {}, true);
    rig.hold(21.1, {});
    CHECK_FALSE(rig.timeline().selection());
}

TEST_CASE("LT stretches the choice, and Y loops it") {
    StudioRig rig;
    recordTwo(rig, 10);
    rig.hold(20, {PadButton::right}, true);
    rig.hold(20.1, {}, true);
    rig.hold(20.2, {PadButton::right}, true, 1);
    CHECK(rig.timeline().selected().size() == 2);
    // LT was pulled for the timeline: no chord changed under it.
    rig.hold(20.3, {PadButton::y}, true, 1);
    CHECK(rig.song().layers[0].loop == Span{0, 2});
    CHECK_FALSE(rig.timeline().selection());
    CHECK(rig.song().isEndless());
    // Played, it goes round.
    rig.hold(30, {PadButton::x}, true);
    rig.hold(30.5, {});
    rig.at(30.96);
    const auto round = rig.at(31.96);
    CHECK(cues(round.playback) == Cues{{32, {}}, {32, I}});
    CHECK(rig.timeline().rolling());
}

TEST_CASE("the right stick nudges the choice, and repeats while held") {
    StudioRig rig;
    recordTwo(rig, 10);
    rig.hold(20, {PadButton::right}, true);  // I
    rig.hold(20.05, {}, true);
    rig.hold(20.1, {PadButton::right}, true);  // IV
    rig.at(20.2, [](GamepadFrame &f) { f.right = lean(90); });
    CHECK(times(rig.song().layers[0]) == Times{{0, 1 + Timeline::fine}, {1 + Timeline::fine, 2 + Timeline::fine}});
    rig.at(20.5);  // not yet
    CHECK(rig.song().layers[0].events[1].start == 1 + Timeline::fine);
    rig.at(20.56);  // after the delay, again
    CHECK(rig.song().layers[0].events[1].start == 1 + 2 * Timeline::fine);
    // A run of nudges is one undo.
    rig.at(20.7, [](GamepadFrame &f) { f.right = Stick::rest(); });
    rig.at(20.8, [](GamepadFrame &f) { f.left = lean(270); });
    CHECK(times(rig.song().layers[0]) == Times{{0, 1}, {1, 2}});
}

TEST_CASE("B quantizes the layer to the grid") {
    StudioRig rig;
    rig.hold(10, {PadButton::a}, true);
    rig.hold(10.1, {});
    rig.hold(10.5, {PadButton::a});
    rig.hold(11.6, {PadButton::b});  // IV a tenth late
    rig.hold(12.5, {});
    rig.hold(13, {PadButton::a}, true);
    rig.hold(13.1, {});
    CHECK(rig.song().layers[0].events[1].start == doctest::Approx(1.1));
    rig.hold(14, {PadButton::b}, true);
    CHECK(times(rig.song().layers[0]) == Times{{0, 1}, {1, 2}});
}

TEST_CASE("a second take is recorded over the first, which plays along") {
    StudioRig rig;
    recordTwo(rig, 10);
    const auto started = rig.hold(20, {PadButton::a}, true);
    CHECK(cues(started.playback) == Cues{{20, I}});
    rig.hold(20.1, {});
    rig.hold(20.5, {PadButton::x});
    rig.hold(21.5, {});
    rig.hold(22.5, {PadButton::a}, true);
    REQUIRE(rig.song().layers.size() == 2);
    // Not trimmed: it is where it was played against the first.
    CHECK(times(rig.song().layers[1]) == Times{{0.5, 1.5}});
    CHECK(rig.timeline().layer()->id == rig.song().layers[1].id);
    // ↑ chooses the layer above.
    rig.hold(23, {PadButton::up}, true);
    CHECK(rig.timeline().layer()->id == rig.song().layers[0].id);
}

TEST_CASE("muting a layer lets go of what it sounds") {
    StudioRig rig;
    recordTwo(rig, 10);
    rig.hold(20, {PadButton::x}, true);
    const auto muted = rig.at(20.2, [](GamepadFrame &f) { f.right = lean(0); });
    CHECK(rig.song().layers[0].isMuted);
    CHECK(cues(muted.playback) == Cues{{20.2, {}}});
}

TEST_CASE("leaving Face Chords stops the timeline") {
    StudioRig rig;
    recordTwo(rig, 10);
    rig.hold(20, {PadButton::x}, true);
    const auto left = rig.studio.choose(LayoutKind::twinRings);
    CHECK(hushes(left.playback));
    CHECK_FALSE(rig.timeline().rolling());
}

TEST_CASE("RT is the timeline's only in Face Chords") {
    StudioRig rig;
    rig.studio.choose(LayoutKind::twinRings);
    rig.hold(1, {PadButton::a}, true);
    CHECK_FALSE(rig.timeline().recording());
}

TEST_CASE("the legend says what RT does, and what it holds while held") {
    StudioRig rig;
    CHECK(rig.studio.legend().at(PadControl::rightTrigger()) == "Hold for the timeline");
    rig.hold(1, {}, true);
    const auto legend = rig.studio.legend();
    CHECK(legend.at(PadControl::button(PadButton::a)) == "Record a new track");
    CHECK(legend.at(PadControl::button(PadButton::x)) == "Play");
}

TEST_CASE("the bar shows the lanes, the choice and the playhead") {
    StudioRig rig;
    recordTwo(rig, 10);
    rig.hold(20, {PadButton::right}, true);
    rig.hold(20.1, {PadButton::x}, true);
    const auto bar = timelineBar(rig.timeline(), 20.6);
    CHECK(bar.from == 0);
    CHECK(bar.to == 16);
    REQUIRE(bar.lanes.size() == 1);
    REQUIRE(bar.lanes[0].blocks.size() == 2);
    CHECK(bar.lanes[0].blocks[0].isChosen);
    CHECK(bar.lanes[0].blocks[0].isHeard);
    CHECK(bar.lanes[0].blocks[0].name == "C maj");
    CHECK(bar.playhead == doctest::Approx(0.5));
    CHECK(bar.status == "Playing · bar 1 · beat 1");
    CHECK(bar.isPlaying);
    // With a chord selected, the bar says what can be done to it.
    CHECK(bar.message == "1 chord selected. Play a chord to replace it: the timing stays the same.");
    CHECK(bar.tips.front() == TimelineBar::Tip{"RT + LT + ← →", "Select more"});
}

TEST_CASE("the bar says how to begin, and what to do while recording and after") {
    StudioRig rig;
    auto bar = timelineBar(rig.timeline(), 0);
    CHECK(bar.status == "Nothing recorded yet");
    CHECK(bar.tips == std::vector<TimelineBar::Tip>{{"RT + A", "Record"}});
    rig.hold(10, {PadButton::a}, true);
    bar = timelineBar(rig.timeline(), 10);
    CHECK(bar.status == "● Recording track 1 · bar 1 · beat 1");
    CHECK(bar.tips.front() == TimelineBar::Tip{"RT + A", "Stop recording"});
    playTwo(rig, 10);
    bar = timelineBar(rig.timeline(), 20);
    CHECK(bar.status == "Stopped · 1 track");
    CHECK(bar.tips.front() == TimelineBar::Tip{"RT + X", "Play"});
    // No word the average player has to look up.
    for (const auto &tip : bar.tips) CHECK(tip.text.find("uantiz") == std::string::npos);
}

}
