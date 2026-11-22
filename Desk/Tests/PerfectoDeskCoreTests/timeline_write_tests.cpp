// What the timeline took over from the arranger, played as the hands play it
// at 60 bpm, so a beat is a second: chords written at a cursor with nothing
// playing, lengths changed directly, and the song saved as a MIDI file.

#include <doctest.h>

#include "perfecto/desk/studio.hpp"

#include <algorithm>
#include <functional>
#include <variant>

using namespace perfecto::desk;
using namespace perfecto::theory;

namespace {

using Times = std::vector<std::pair<double, double>>;

const Key cMajor{PitchClass::C, ScaleType::major};

DeskSettings slow() {
    DeskSettings settings;
    settings.tempo = 60;
    return settings;
}

struct Rig {
    Studio studio{Desk(SoundCatalog({}), slow(), LayoutKind::faceChords)};
    GamepadFrame last = GamepadFrame{.time = 0};

    Studio::Played at(double time, const std::function<void(GamepadFrame &)> &change = {}) {
        GamepadFrame frame = last;
        frame.time = time;
        if (change) change(frame);
        last = frame;
        return studio.step(frame);
    }

    /// Presses and lets go of Back just before `time` if the hands are not
    /// where `layer` says, with what is held still held.
    void inTimeline(double time, bool layer) {
        if (studio.isTimeline() == layer) return;
        GamepadFrame down = last;
        down.time = time - 0.002;
        down.buttons.insert(PadButton::back);
        studio.step(down);
        last = down;
        last.time = time - 0.001;
        last.buttons.erase(PadButton::back);
        studio.step(last);
    }

    Studio::Played hold(double time, std::set<PadButton> buttons, bool layer = false, double lt = 0, Stick left = Stick::rest()) {
        inTimeline(time, layer);
        return at(time, [&](GamepadFrame &f) {
            f.buttons = std::move(buttons);
            f.leftTrigger = lt;
            f.left = left;
        });
    }

    const Timeline &timeline() const { return studio.timeline(); }

    Times times() const {
        Times out;
        if (const Layer *layer = timeline().layer())
            for (const Event &event : layer->events) out.emplace_back(event.start, event.end());
        return out;
    }

    /// Into Write mode, with every button let go.
    void enterWrite(double time) {
        hold(time, {PadButton::r3}, true);
        hold(time + 0.1, {});
    }

    /// I for two beats, then IV for one without letting go.
    void writeTwo(double time) {
        enterWrite(time);
        hold(time + 1, {PadButton::a});
        hold(time + 3, {PadButton::b});
        hold(time + 4, {});
    }
};

ChordPart part(Degree degree, std::vector<int> notes) { return ChordPart{0, DeskChord(cMajor, degree), std::move(notes)}; }

Event event(int id, double start, double length, Degree degree = Degree::I) {
    return Event{id, start, length, part(degree, {60, 64, 67})};
}

bool saved(const Studio::Played &played) {
    return std::any_of(played.effects.begin(), played.effects.end(), [](const DeskEffect &effect) {
        return std::holds_alternative<DeskEffect::SaveMIDI>(effect.value());
    });
}

} // namespace

TEST_SUITE("Timeline: writing") {

TEST_CASE("Write mode places chords one after another, as long as each is held, with nothing playing") {
    Rig rig;
    rig.hold(0.5, {});
    rig.writeTwo(1);
    CHECK(rig.times() == Times{{0, 2}, {2, 3}});
    CHECK_FALSE(rig.timeline().rolling().has_value());
    CHECK(rig.timeline().writing()->cursor == 3);
}

TEST_CASE("a held length is snapped to the grid") {
    Rig rig;
    rig.hold(0.5, {});
    rig.enterWrite(1);
    rig.hold(2, {PadButton::a});
    rig.hold(2.6, {});
    CHECK(rig.times() == Times{{0, 0.75}});
}

TEST_CASE("a chord colored while it is held is one chord") {
    Rig rig;
    rig.hold(0.5, {});
    rig.enterWrite(1);
    rig.hold(2, {PadButton::a});
    rig.hold(2.5, {PadButton::a}, false, 0, Stick{0, 1});
    rig.hold(3, {});
    CHECK(rig.times() == Times{{0, 1}});
}

TEST_CASE("what was held on entering Write mode is not written") {
    Rig rig;
    rig.hold(0.5, {PadButton::a});
    rig.hold(1, {PadButton::a, PadButton::r3}, true);
    rig.hold(1.1, {PadButton::a});
    rig.hold(2, {});
    CHECK(rig.times().empty());
}

TEST_CASE("the cursor moves by the grid or a bar, and a chord written over another replaces it") {
    Rig rig;
    rig.hold(0.5, {});
    rig.writeTwo(1);
    rig.hold(6, {PadButton::left}, true, 1);
    CHECK(rig.timeline().writing()->cursor == 0);
    rig.hold(6.1, {PadButton::right}, true);
    CHECK(rig.timeline().writing()->cursor == 0.25);
    rig.hold(6.2, {});
    rig.hold(7, {PadButton::x});
    rig.hold(8, {});
    CHECK(rig.times() == Times{{0, 0.25}, {0.25, 1.25}, {2, 3}});
}

TEST_CASE("playing leaves Write mode, from the cursor") {
    Rig rig;
    rig.hold(0.5, {});
    rig.writeTwo(1);
    rig.hold(6, {PadButton::left}, true);
    rig.hold(6.1, {});
    rig.hold(7, {PadButton::x}, true);
    CHECK_FALSE(rig.timeline().writing().has_value());
    CHECK(rig.timeline().playhead(7) == doctest::Approx(2.75));
}

TEST_CASE("each write is one undo") {
    Rig rig;
    rig.hold(0.5, {});
    rig.writeTwo(1);
    rig.hold(6, {}, true, 0, Stick{-1, 0});
    CHECK(rig.times() == Times{{0, 2}});
}

TEST_CASE("the left stick makes the selection longer and shorter, as far as the next chord") {
    Rig rig;
    rig.hold(0.5, {});
    rig.writeTwo(1);
    rig.hold(6, {PadButton::r3}, true);
    rig.hold(6.1, {}, true);
    rig.hold(6.2, {PadButton::left}, true);
    rig.hold(6.3, {PadButton::left}, true, 0);
    rig.hold(6.4, {}, true);
    rig.hold(6.5, {}, true, 1);
    REQUIRE(rig.timeline().selection().has_value());
    rig.hold(6.6, {}, true, 1, Stick{0, -1});
    CHECK(rig.times() == Times{{0, 2}, {2, 2.75}});
    rig.hold(6.7, {}, true, 1);
    rig.hold(6.8, {}, true, 1, Stick{0, 1});
    CHECK(rig.times() == Times{{0, 2}, {2, 3}});
}

TEST_CASE("written gives way on its channel and keeps the order") {
    const Layer layer{1, {event(1, 0, 4), event(2, 4, 2), event(3, 6, 2)}, std::nullopt, false};
    const Layer next = written(layer, 9, 2, 3, part(Degree::V, {67, 71, 74}));
    REQUIRE(next.events.size() == 3);
    CHECK(next.events[0].end() == 2);
    CHECK(next.events[1].id == 9);
    CHECK(next.events[2].id == 3);
}

TEST_CASE("resized stops at the next chord, and keeps a chord from vanishing") {
    const Layer layer{1, {event(1, 0, 1), event(2, 2, 1)}, std::nullopt, false};
    CHECK(resized(layer, {1}, 5).events[0].length == 2);
    CHECK(resized(layer, {1}, -5).events[0].length == shortestEvent);
    CHECK(resized(layer, {2}, 5).events[1].length == 6);
}

TEST_CASE("RB in the timeline saves the song, and Menu is the menu") {
    Rig rig;
    rig.hold(0.5, {});
    CHECK_FALSE(saved(rig.hold(1, {PadButton::rb}, true)));
    rig.hold(1.1, {});
    rig.writeTwo(2);
    CHECK(saved(rig.hold(7, {PadButton::rb}, true)));
    CHECK_FALSE(rig.studio.desk().menu().has_value());
    rig.hold(7.1, {}, true);
    rig.hold(7.2, {PadButton::start}, true);
    CHECK(rig.studio.desk().menu().has_value());
}

TEST_CASE("Write mode hands the chords back, and keeps its cursor on the d-pad and R3") {
    Rig rig;
    rig.hold(0.5, {});
    rig.writeTwo(1);
    CHECK_FALSE(rig.studio.isTimeline());
    rig.hold(6, {PadButton::left});
    CHECK(rig.timeline().writing()->cursor == 2.75);
    rig.hold(6.1, {});
    rig.hold(6.2, {PadButton::r3});
    CHECK_FALSE(rig.timeline().writing().has_value());
}

TEST_CASE("the MIDI file has a track to each layer heard, its loops repeated to the song's end") {
    Song song;
    song.layers.push_back({1, {event(1, 0, 8)}, std::nullopt, false});
    song.layers.push_back({2, {event(2, 0, 1)}, Span{0, 2}, false});
    song.layers.push_back({3, {event(3, 0, 1)}, std::nullopt, true});
    const auto file = midiFile(song, slow());
    REQUIRE(file.has_value());
    REQUIRE(file->tracks.size() == 3);
    const auto &looped = file->tracks[2].events;
    const auto ons = std::count_if(looped.begin(), looped.end(), [](const MidiEvent &midi) {
        return std::holds_alternative<MidiEvent::NoteOn>(midi.kind);
    });
    CHECK(ons == 4 * 3);
    CHECK(file->tracks[0].length == 8 * 480);
}

TEST_CASE("a song with nothing heard has no MIDI file") {
    CHECK_FALSE(midiFile(Song{}, slow()).has_value());
    Song muted;
    muted.layers.push_back({1, {event(1, 0, 1)}, std::nullopt, true});
    CHECK_FALSE(midiFile(muted, slow()).has_value());
}

}
