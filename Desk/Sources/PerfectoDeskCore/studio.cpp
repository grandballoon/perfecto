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
    drums.insert(drums.end(), std::make_move_iterator(more.drums.begin()), std::make_move_iterator(more.drums.end()));
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
    frame_ = frame;
    const FaceHands::Read hands = hands_.read(frame, reachable());
    const GamepadFrame handedBefore = handed_ ? *handed_ : GamepadFrame{.time = frame.time};
    handed_ = hands.frame;
    Drums::Step drummed = drums_.step(PadInput(hands.frame, handedBefore), reachable(), desk_.settings);
    const double chordLayer = hands_.chordLayer(drummed.frame.rightTrigger, hands.isTimeline);
    // In the timeline RB is its own, kept from the drums.
    if (hands.isTimeline && frame.isDown(PadButton::rb)) drummed.frame.buttons.insert(PadButton::rb);
    const GamepadFrame drummedBefore = drummed_ ? *drummed_ : GamepadFrame{.time = frame.time};
    drummed_ = drummed.frame;
    Played played;
    auto taken = timeline_.take(PadInput(drummed.frame, drummedBefore), hands.isTimeline, reachable(), desk_.settings);
    played.append(std::move(taken.out));
    if (!timeline_.isLayered()) hands_.leave();
    const GamepadFrame takenBefore = taken_ ? *taken_ : GamepadFrame{.time = frame.time};
    taken_ = taken.frame;
    auto colored = colors_.step(PadInput(taken.frame, takenBefore), reachable(), desk_.faceChords(), desk_.settings);
    desk_.setFaceColors(std::move(colored.colors));
    played.append(std::move(colored.effects));
    // Face Chords reads its second layer from LT, which RT plays here.
    GamepadFrame played_frame = taken.frame;
    if (reachable()) played_frame.leftTrigger = chordLayer;
    played.append(settled(desk_.step(played_frame)));
    played.append(std::move(drummed.effects));
    played.drums.insert(played.drums.end(), drummed.drums.begin(), drummed.drums.end());
    played.append(timeline_.write(heard(desk_), frame.time, desk_.settings));
    played.append(timeline_.hear(heard(desk_), frame.time));
    played.append(timeline_.advance(frame.time, desk_.settings));
    return played;
}

Studio::Played Studio::choose(LayoutKind layout) { return settled(desk_.choose(layout)); }

Studio::Played Studio::toggleMenu() { return settled(desk_.toggleMenu()); }

Studio::Played Studio::letGo() {
    drums_.stop();
    Played played;
    played.append(desk_.letGo());
    played.append(timeline_.stop(time()));
    return played;
}

Studio::Played Studio::settled(std::vector<DeskEffect> effects) {
    Played played;
    played.append(std::move(effects));
    if (desk_.layout() != LayoutKind::faceChords) {
        drums_.stop();
        played.append(timeline_.stop(time()));
    }
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
    case Action::Kind::write: played.append(timeline_.toggleWrite(now, settings)); break;
    case Action::Kind::saveSong: played.append(timeline_.save(settings)); break;
    case Action::Kind::choosePattern:
        if (action.index >= 0 && action.index < static_cast<int>(drumPatterns().size()))
            drums_.choosePattern(action.index - drums_.machine().pattern());
        break;
    case Action::Kind::chooseKit: played.drums = drums_.setKit(action.index, now); break;
    default: return settled(desk::perform(desk_, action));
    }
    // A click that starts recording or writing hands the buttons back too.
    if (!timeline_.isLayered()) hands_.leave();
    return played;
}

Legend Studio::legend() const {
    Legend base = desk_.legend();
    if (reachable()) {
        // The chords' second layer is on RT.
        const auto layer = base.find(PadControl::leftTrigger());
        if (layer != base.end()) base[PadControl::rightTrigger()] = layer->second;
    }
    Legend legend = drums_.legend(timeline_.legend(colors_.legend(std::move(base), reachable(), desk_.settings), reachable()),
                                  reachable());
    if (!reachable()) return legend;
    const auto back = PadControl::button(PadButton::back);
    if (hands_.isTimeline()) {
        legend[back] = "Back to playing";
        legend[PadControl::button(PadButton::lb)] = "Deselect";
        legend[PadControl::button(PadButton::rb)] = "Save as MIDI";
    } else if (!drums_.isLayered()) {
        legend[back] = "Edit the timeline";
    }
    return legend;
}

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
    const auto &writing = timeline.writing();
    if (writing) reach = std::max(reach, writing->cursor + 1);
    const double bar = Song::beatsPerBar;
    const double length = std::max(shortestShown, std::ceil(reach / bar) * bar);
    const auto page = writing ? std::optional(writing->cursor) : head;
    const double from = page && !recording ? std::floor(std::max(*page, 0.0) / length) * length : 0;
    const double to = from + length;
    const auto shown = [&](double start, double end) { return start < to && end > from; };
    const auto covers = [&](double start, double end) { return playhead && start <= *playhead && *playhead < end; };

    TimelineBar view{from, to, Song::beatsPerBar, head, playhead.has_value(), {}, {}, "", Tint::secondary, "", {}};
    // The buttons are the timeline's only in it, so only then are they shown.
    const bool editing = timeline.isLayered();
    view.isEditing = editing;
    const auto keys = [&](const char *shown) { return std::string(editing ? shown : ""); };
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
        if (writing && chosenLayer && chosenLayer->id == layer.id)
            for (const auto &[voice, open] : writing->open)
                lane.blocks.push_back({0, writing->cursor,
                                       writing->cursor + std::max((time - open.first) * writing->tempo / 60, 0.0),
                                       open.second.chord.name(), voice, false, true, false, false});
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
        {Icon::rewind, "Back to start", keys("LT + X"), false, (head && *head > 0) && !recording,
         {Kind::rewind, 0, 0, {}}},
        {rolling ? Icon::pause : Icon::play, rolling ? "Pause" : "Play", keys("X"), false, !song.isEmpty() || rolling,
         {Kind::play, 0, 0, {}}},
        {recording ? Icon::stopRecording : Icon::record, recording ? "Stop recording" : "Record", keys("A"),
         recording.has_value(), true, {Kind::record, 0, 0, {}}},
        {Icon::none, "Write", keys("R3"), writing.has_value(), !recording, {Kind::write, 0, 0, {}}},
        {Icon::none, selection || !looping ? "⟲ Loop selection" : "⟲ Stop looping", keys("Y"), false,
         selection || looping, {Kind::loop, 0, 0, {}}},
        {Icon::none, "⌗ Fix timing", keys("B"), false, chosenLayer != nullptr, {Kind::quantize, 0, 0, {}}},
        {Icon::none, "✕ Delete", keys("R-stick ↓"), false, selection, {Kind::erase, 0, 0, {}}},
        {Icon::none, "↶ Undo", keys("L-stick ←"), false, timeline.canUndo(), {Kind::undo, 0, 0, {}}},
        {Icon::none, "↷ Redo", keys("L-stick →"), false, timeline.canRedo(), {Kind::redo, 0, 0, {}}},
        {Icon::none, "Save MIDI", keys("RB"), false, !song.isEmpty(), {Kind::saveSong, 0, 0, {}}},
    };

    const TimelineBar::Tip toPlaying{"Back", "Back to playing"}, toEditing{"Back", "Edit timeline"};
    if (recording) {
        view.status = "● Recording track " + std::to_string(song.layers.size()) + " · " + position(*playhead);
        view.statusTint = Tint::chord;
        view.message = "Recording: play along, and every chord you play is captured.";
        if (editing) view.tips = {{"A", "Stop recording"}, {"X", "Pause"}, toPlaying};
        else view.tips = {{"Back, then A", "Stop recording"}};
        return view;
    }
    if (writing) {
        view.cursor = writing->cursor;
        view.status = "Writing · " + position(writing->cursor);
        view.statusTint = Tint::chord;
        view.message = "Hold a chord to write it at the cursor, for as long as you hold it. Nothing has to play.";
        if (editing)
            view.tips = {{"← →", "Move cursor"}, {"LT + ← →", "By a bar"}, {"L-stick ←", "Undo"},
                         {"X", "Play from cursor"}, {"R3", "Done"}, {"Back", "Write chords"}};
        else
            view.tips = {{"← →", "Move cursor"}, {"LT + ← →", "By a bar"}, {"R3", "Done"}, {"Back", "Undo, play and more"}};
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
    if (selection)
        view.message = count(chosen.size(), "chord", "chords") +
                       " selected. Play a chord to replace " + (chosen.size() == 1 ? "it" : "them") +
                       ": the timing stays the same.";
    if (!editing) {
        if (song.isEmpty()) view.message = "Press Back to edit the timeline, then A to record.";
        else if (!selection) view.message = "Press Back to work with what you recorded.";
        view.tips = {toEditing};
    } else if (song.isEmpty()) {
        view.message = "Press A to record, or R3 to write chords without playing.";
        view.tips = {{"A", "Record"}, {"R3", "Write chords without playing"}, toPlaying};
    } else if (selection) {
        view.message = count(chosen.size(), "chord", "chords") + " selected. Press Back, then play a chord to replace " +
                       (chosen.size() == 1 ? "it" : "them") + ": the timing stays the same.";
        view.tips = {{"LT + ← →", "Select more"},       {"Y", "Loop selection"},
                     {"B", "Fix timing"},               {"R-stick ← →", "Move earlier / later"},
                     {"L-stick ↑ ↓", "Longer / shorter"},
                     {"R-stick ↓", "Delete"},           {"LB", "Deselect"}, toPlaying};
    } else {
        view.message = "Every button works the timeline. Press Back to play chords.";
        view.tips = {{"X", playhead ? "Pause" : "Play"}, {"A", "Record a new track"},
                     {"← →", "Select a chord"},          {"↑ ↓", "Pick a track"},
                     {"B", "Fix timing of the track"},
                     {"R3", "Write"},                    {"RB", "Save MIDI"}};
        if (looping) view.tips.push_back({"Y", "Stop looping"});
        if (head && *head > 0) view.tips.push_back({"LT + X", "Back to start"});
        view.tips.push_back(toPlaying);
    }
    return view;
}

Scene scene(const Studio &studio, bool keyboard) {
    // The hand is shown as it is, before the drums and the timeline took their share.
    const auto frame = studio.frame() ? studio.frame()->shown() : GamepadFrame();
    Scene shown =
        scene(studio.desk(), studio.legend(), frame, keyboard, &studio.drums(), &studio.colors(), studio.time());
    if (studio.desk().layout() == LayoutKind::faceChords) shown.timeline = timelineBar(studio.timeline(), studio.time());
    return shown;
}

} // namespace perfecto::desk
