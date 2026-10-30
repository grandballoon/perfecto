#include "perfecto/desk/studio.hpp"

#include <algorithm>
#include <cmath>

namespace perfecto::desk {

namespace {

/// The shortest the bar shows: four bars.
constexpr double shortestShown = 4 * Song::beatsPerBar;

/// "bar 2 · beat 3"
std::string position(double beats) {
    const auto whole = static_cast<long>(std::floor(std::max(beats, 0.0)));
    return "bar " + std::to_string(whole / Song::beatsPerBar + 1) + " · beat " +
           std::to_string(whole % Song::beatsPerBar + 1);
}

std::string count(size_t n, const std::string &one, const std::string &many) {
    return std::to_string(n) + " " + (n == 1 ? one : many);
}

std::string chordName(const Part &part) {
    return std::visit([](const ChordPart &chord) { return chord.chord.name(); }, part);
}

} // namespace

Heard heard(const Desk &desk) {
    Heard heard;
    if (desk.layout() != LayoutKind::faceChords) return heard;
    const auto &line = desk.faceChords().line();
    if (line.isSounding() && line.chord()) heard.emplace(0, ChordPart{0, *line.chord(), line.notes()});
    return heard;
}

// MARK: – The studio

void Studio::Played::append(std::vector<DeskEffect> more) {
    effects.insert(effects.end(), std::make_move_iterator(more.begin()), std::make_move_iterator(more.end()));
}

void Studio::Played::append(Played more) {
    append(std::move(more.effects));
    playback.insert(playback.end(), std::make_move_iterator(more.playback.begin()),
                    std::make_move_iterator(more.playback.end()));
}

void Studio::Played::append(Timeline::Out out) {
    append(std::move(out.effects));
    playback.insert(playback.end(), std::make_move_iterator(out.playback.begin()),
                    std::make_move_iterator(out.playback.end()));
}

bool Studio::reachable() const { return desk_.layout() == LayoutKind::faceChords && !desk_.menu(); }

Studio::Played Studio::step(const GamepadFrame &frame) {
    const GamepadFrame previous = frame_ ? *frame_ : GamepadFrame{.time = frame.time};
    frame_ = frame;
    Played played;
    auto taken = timeline_.take(PadInput(frame, previous), reachable(), desk_.settings);
    played.append(std::move(taken.out));
    played.append(settled(desk_.step(taken.frame)));
    played.append(timeline_.hear(heard(desk_), frame.time));
    played.append(timeline_.advance(frame.time, desk_.settings));
    return played;
}

Studio::Played Studio::choose(LayoutKind layout) { return settled(desk_.choose(layout)); }

Studio::Played Studio::toggleMenu() { return settled(desk_.toggleMenu()); }

Studio::Played Studio::letGo() {
    Played played;
    played.append(desk_.letGo());
    played.append(timeline_.stop(time()));
    return played;
}

Studio::Played Studio::settled(std::vector<DeskEffect> effects) {
    Played played;
    played.append(std::move(effects));
    if (desk_.layout() != LayoutKind::faceChords) played.append(timeline_.stop(time()));
    return played;
}

Studio::Played Studio::perform(const Action &action) {
    const double now = time();
    const auto &settings = desk_.settings;
    Played played;
    switch (action.kind) {
    case Action::Kind::record: played.append(timeline_.record(now, settings)); break;
    case Action::Kind::play: played.append(timeline_.play(now, settings)); break;
    case Action::Kind::rewind: played.append(timeline_.rewind(now, settings)); break;
    case Action::Kind::loop: played.append(timeline_.loop()); break;
    case Action::Kind::quantize: played.append(timeline_.quantize(settings)); break;
    case Action::Kind::erase: played.append(timeline_.erase(now)); break;
    case Action::Kind::undo: played.append(timeline_.undo(now)); break;
    case Action::Kind::redo: played.append(timeline_.redo(now)); break;
    case Action::Kind::chooseLane: played.append(timeline_.chooseLayer(action.index)); break;
    case Action::Kind::muteLane: played.append(timeline_.mute(action.index, now)); break;
    case Action::Kind::selectEvent: played.append(timeline_.select(action.index, action.value, false)); break;
    case Action::Kind::stretchChoice: played.append(timeline_.select(action.index, action.value, true)); break;
    case Action::Kind::deselect: played.append(timeline_.deselect()); break;
    default: return settled(desk::perform(desk_, action));
    }
    return played;
}

Legend Studio::legend() const { return timeline_.legend(desk_.legend(), reachable()); }

// MARK: – What it shows

TimelineBar timelineBar(const Timeline &timeline, double time) {
    const Song &song = timeline.song();
    const auto playhead = timeline.playhead(time);
    // Shown where it plays, or where it paused.
    const auto head = playhead ? playhead : timeline.cue();
    const auto &recording = timeline.recording();
    const auto chosen = timeline.selected();
    const Layer *chosenLayer = timeline.layer();

    // As long as what was recorded, in whole bars, and four at least; while
    // a loop plays on past it, the page the playhead is on.
    double reach = 0;
    for (const Layer &layer : song.layers) {
        for (const Event &event : layer.events) reach = std::max(reach, event.end());
        if (layer.loop) reach = std::max(reach, layer.loop->to);
    }
    if (recording && playhead) reach = std::max(reach, *playhead);
    const double bar = Song::beatsPerBar;
    const double length = std::max(shortestShown, std::ceil(reach / bar) * bar);
    const double from = head && !recording ? std::floor(std::max(*head, 0.0) / length) * length : 0;
    const double to = from + length;
    const auto shown = [&](double start, double end) { return start < to && end > from; };
    const auto covers = [&](double start, double end) { return playhead && start <= *playhead && *playhead < end; };

    TimelineBar view{from, to, Song::beatsPerBar, head, playhead.has_value(), {}, {}, "", Tint::secondary, "", {}};
    for (size_t i = 0; i < song.layers.size(); ++i) {
        const Layer &layer = song.layers[i];
        const bool isRecording = recording && recording->layer == layer.id;
        TimelineBar::Lane lane{layer.id, std::to_string(i + 1), {}, std::nullopt, layer.isMuted,
                               chosenLayer && chosenLayer->id == layer.id, isRecording};
        if (layer.loop) lane.loop = std::pair(layer.loop->from, layer.loop->to);
        for (const Event &event : layer.events) {
            if (!shown(event.start, event.end())) continue;
            const bool leftOut = layer.loop && (event.end() <= layer.loop->from || event.start >= layer.loop->to);
            const bool heard = !isRecording && !layer.isMuted && !leftOut &&
                               covers(event.start, layer.loop ? std::min(event.end(), layer.loop->to) : event.end());
            lane.blocks.push_back({event.id, event.start, event.end(), chordName(event.part), channel(event.part),
                                   chosen.contains(event.id) && timeline.selection()->layer == layer.id, heard, false,
                                   leftOut});
        }
        if (layer.loop) {
            for (const Occurrence &echo : song.heard(layer, from, to)) {
                if (echo.start >= layer.loop->from && echo.start < layer.loop->to) continue;
                lane.blocks.push_back({echo.id, echo.start, echo.end, chordName(echo.part), echo.track.channel, false,
                                       !layer.isMuted && covers(echo.start, echo.end), true, false});
            }
        }
        if (isRecording && playhead)
            for (const auto &[voice, open] : recording->open)
                lane.blocks.push_back({0, open.first, std::max(*playhead, open.first), open.second.chord.name(), voice,
                                       false, true, false, false});
        view.lanes.push_back(lane);
    }

    const bool rolling = timeline.rolling().has_value();
    const bool selection = timeline.selection().has_value();
    using Kind = Action::Kind;
    const bool looping = chosenLayer && chosenLayer->loop;
    using Icon = TimelineBar::Icon;
    view.controls = {
        {Icon::rewind, "Back to start", "RT + LT + X", false, (head && *head > 0) && !recording,
         {Kind::rewind, 0, 0, {}}},
        {rolling ? Icon::pause : Icon::play, rolling ? "Pause" : "Play", "RT + X", false, !song.isEmpty() || rolling,
         {Kind::play, 0, 0, {}}},
        {recording ? Icon::stopRecording : Icon::record, recording ? "Stop recording" : "Record", "RT + A",
         recording.has_value(), true, {Kind::record, 0, 0, {}}},
        {Icon::none, selection || !looping ? "⟲ Loop selection" : "⟲ Stop looping", "RT + Y", false,
         selection || looping, {Kind::loop, 0, 0, {}}},
        {Icon::none, "⌗ Fix timing", "RT + B", false, chosenLayer != nullptr, {Kind::quantize, 0, 0, {}}},
        {Icon::none, "✕ Delete", "RT + R-stick ↓", false, selection, {Kind::erase, 0, 0, {}}},
        {Icon::none, "↶ Undo", "RT + L-stick ←", false, timeline.canUndo(), {Kind::undo, 0, 0, {}}},
        {Icon::none, "↷ Redo", "RT + L-stick →", false, timeline.canRedo(), {Kind::redo, 0, 0, {}}},
    };

    if (recording) {
        view.status = "● Recording track " + std::to_string(song.layers.size()) + " · " + position(*playhead);
        view.statusTint = Tint::chord;
        view.message = "Recording: play along, and every chord you play is captured.";
        view.tips = {{"RT + A", "Stop recording"}, {"RT + X", "Pause"}};
        return view;
    }
    if (playhead) {
        view.status = "Playing · " + position(*playhead);
        view.statusTint = Tint::near;
    } else if (head && !song.isEmpty()) {
        view.status = "Paused · " + position(*head);
    } else {
        view.status = song.isEmpty() ? "Nothing recorded yet" : "Stopped · " + count(song.layers.size(), "track", "tracks");
    }
    if (song.isEmpty()) {
        view.message = "Hold RT and press A to start recording, then play chords. Press RT + A again to stop.";
        view.tips = {{"RT + A", "Record"}};
    } else if (selection) {
        view.message = count(chosen.size(), "chord", "chords") +
                       " selected. Play a chord to replace " + (chosen.size() == 1 ? "it" : "them") +
                       ": the timing stays the same.";
        view.tips = {{"RT + LT + ← →", "Select more"},       {"RT + Y", "Loop selection"},
                     {"RT + B", "Fix timing"},                {"RT + R-stick ← →", "Move earlier / later"},
                     {"RT + R-stick ↓", "Delete"},            {"Tap RT", "Deselect"}};
    } else {
        view.message = "Hold RT to work with what you recorded.";
        view.tips = {{"RT + X", playhead ? "Pause" : "Play"}, {"RT + A", "Record a new track"},
                     {"RT + ← →", "Select a chord"},         {"RT + ↑ ↓", "Pick a track"},
                     {"RT + B", "Fix timing of the track"}};
        if (looping) view.tips.push_back({"RT + Y", "Stop looping"});
        if (head && *head > 0) view.tips.push_back({"RT + LT + X", "Back to start"});
    }
    return view;
}

Scene scene(const Studio &studio, bool keyboard) {
    Scene shown = scene(studio.desk(), keyboard);
    const auto frame = studio.frame() ? studio.frame()->shown() : GamepadFrame();
    shown.hand = hand(studio.legend(), frame, keyboard);
    if (studio.desk().layout() == LayoutKind::faceChords) shown.timeline = timelineBar(studio.timeline(), studio.time());
    return shown;
}

} // namespace perfecto::desk
