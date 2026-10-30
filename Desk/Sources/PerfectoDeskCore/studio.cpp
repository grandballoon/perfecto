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
    const GamepadFrame previous = frame_ ? *frame_ : GamepadFrame{.time = frame.time};
    frame_ = frame;
    Drums::Step drummed = drums_.step(PadInput(frame, previous), reachable(), desk_.settings);
    const GamepadFrame drummedBefore = drummed_ ? *drummed_ : GamepadFrame{.time = frame.time};
    drummed_ = drummed.frame;
    Played played;
    auto taken = timeline_.take(PadInput(drummed.frame, drummedBefore), reachable(), desk_.settings);
    played.append(std::move(taken.out));
    const GamepadFrame takenBefore = taken_ ? *taken_ : GamepadFrame{.time = frame.time};
    taken_ = taken.frame;
    auto colored = colors_.step(PadInput(taken.frame, takenBefore), reachable(), desk_.faceChords(), desk_.settings);
    desk_.setFaceColors(std::move(colored.colors));
    played.append(std::move(colored.effects));
    played.append(settled(desk_.step(taken.frame)));
    played.append(std::move(drummed.effects));
    played.drums.insert(played.drums.end(), drummed.drums.begin(), drummed.drums.end());
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

Legend Studio::legend() const {
    return drums_.legend(timeline_.legend(colors_.legend(desk_.legend(), reachable(), desk_.settings), reachable()),
                         reachable());
}

// MARK: – What it shows

TimelineBar timelineBar(const Timeline &timeline, double time) {
    const Song &song = timeline.song();
    const auto playhead = timeline.playhead(time);
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
    const double from = playhead && !recording ? std::floor(std::max(*playhead, 0.0) / length) * length : 0;
    const double to = from + length;
    const auto shown = [&](double start, double end) { return start < to && end > from; };
    const auto covers = [&](double start, double end) { return playhead && start <= *playhead && *playhead < end; };

    TimelineBar view{from, to, Song::beatsPerBar, playhead, {}, {}, "", Tint::secondary, ""};
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
    view.controls = {
        {recording ? "■ Stop recording" : "● Record", "RT A", recording.has_value(), true, {Kind::record, 0, 0, {}}},
        {rolling ? "■ Stop" : "▶ Play", "RT X", rolling, !song.isEmpty() || rolling, {Kind::play, 0, 0, {}}},
        {selection || !chosenLayer || !chosenLayer->loop ? "⟲ Loop" : "⟲ End loop", "RT Y", false,
         selection || (chosenLayer && chosenLayer->loop), {Kind::loop, 0, 0, {}}},
        {"⌗ Quantize", "RT B", false, chosenLayer != nullptr, {Kind::quantize, 0, 0, {}}},
        {"✕ Delete", "RT RS ↓", false, selection, {Kind::erase, 0, 0, {}}},
        {"↶ Undo", "RT LS ←", false, timeline.canUndo(), {Kind::undo, 0, 0, {}}},
        {"↷ Redo", "RT LS →", false, timeline.canRedo(), {Kind::redo, 0, 0, {}}},
    };

    if (recording) {
        view.status = "● Recording layer " + std::to_string(song.layers.size()) + " · " + position(*playhead);
        view.statusTint = Tint::chord;
        view.hint = "Play: every chord is laid down as you go. RT A stops recording.";
    } else if (playhead) {
        view.status = "▶ Playing · " + position(*playhead);
        view.statusTint = Tint::near;
    } else if (song.isEmpty()) {
        view.status = "Nothing recorded";
        view.hint = "Hold RT and press A to record what you play.";
    } else {
        view.status = "Stopped · " + count(song.layers.size(), "layer", "layers");
    }
    if (!recording) {
        if (selection)
            view.hint = count(chosen.size(), "chord", "chords") +
                        " chosen: play a chord to write it in. RT with the right stick nudges, B quantizes, Y loops; "
                        "tap RT to let go.";
        else if (!song.isEmpty())
            view.hint = "Hold RT: ← → choose chords (LT stretches), ↑ ↓ the layer, X plays, A records another layer.";
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
