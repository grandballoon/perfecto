#include "perfecto/desk/timeline.hpp"

#include "perfecto/desk/beat_grid.hpp"

#include <algorithm>
#include <cmath>
#include <queue>
#include <tuple>

namespace perfecto::desk {

namespace {

/// LT past halfway: stretching and nudging by the grid.
bool stretches(const GamepadFrame &frame) { return frame.leftTrigger >= 0.5; }

/// The way `stick` is pushed, as a d-pad's direction: chosen when it leans
/// well out along one axis, and kept until it comes back near the middle.
std::optional<PadButton> pushed(const Stick &stick, std::optional<PadButton> last) {
    const double radius = stick.radius();
    if (radius < 0.35) return std::nullopt;
    if (last) return last;
    if (radius < 0.6) return std::nullopt;
    if (std::abs(stick.x) > std::abs(stick.y)) return stick.x > 0 ? PadButton::right : PadButton::left;
    return stick.y > 0 ? PadButton::up : PadButton::down;
}

bool isFace(PadButton button) {
    return button == PadButton::a || button == PadButton::b || button == PadButton::x || button == PadButton::y;
}

/// What the timeline takes besides the face buttons and the arrows.
bool isTool(PadButton button) {
    return button == PadButton::r3 || button == PadButton::lb || button == PadButton::rb;
}

bool isArrow(PadButton button) {
    return button == PadButton::up || button == PadButton::down || button == PadButton::left ||
           button == PadButton::right;
}

Timeline::Out felt(Rumble rumble) { return {{}, {DeskEffect::rumble(rumble)}}; }
Timeline::Out refused(std::string reason) { return {{}, {DeskEffect::refuse(std::move(reason))}}; }

} // namespace

void Timeline::Out::append(Out more) {
    playback.insert(playback.end(), std::make_move_iterator(more.playback.begin()),
                    std::make_move_iterator(more.playback.end()));
    effects.insert(effects.end(), std::make_move_iterator(more.effects.begin()), std::make_move_iterator(more.effects.end()));
}

// MARK: – What it is

const Layer *Timeline::layer() const { return song_.layer(layer_); }

std::set<int> Timeline::selected() const {
    if (!selection_) return {};
    const Layer *layer = song_.layer(selection_->layer);
    return layer ? layer->between(selection_->anchor, selection_->head) : std::set<int>{};
}

std::optional<double> Timeline::playhead(double time) const {
    return rolling_ ? std::optional(beatAt(time)) : std::nullopt;
}

double Timeline::grid(const DeskSettings &settings) { return step(settings.grid).value_or(0.25); }

double Timeline::beatAt(double time) const {
    return rolling_->beat + (time - rolling_->time) * rolling_->tempo / 60;
}

double Timeline::timeAt(double beat) const {
    return rolling_->time + (beat - rolling_->beat) * 60 / rolling_->tempo;
}

double Timeline::startBeat() const {
    const Layer *layer = selection_ ? song_.layer(selection_->layer) : nullptr;
    const auto span = layer ? layer->span(selected()) : std::nullopt;
    return span ? span->from : cue_.value_or(0);
}

void Timeline::edit(Song next, Edit kind) {
    if (next == song_) return;
    // A run of one small edit is one undo.
    if (kind == Edit::other || kind != lastEdit_) {
        undo_.push_back(song_);
        if (undo_.size() > memory) undo_.erase(undo_.begin());
    }
    redo_.clear();
    song_ = std::move(next);
    lastEdit_ = kind;
}

void Timeline::edit(const Layer &layer, Edit kind) {
    Song next = song_;
    if (Layer *found = next.layer(layer.id)) *found = layer;
    // A layer left with nothing is gone, but the one being recorded.
    std::erase_if(next.layers, [&](const Layer &l) {
        return l.events.empty() && !(recording_ && recording_->layer == l.id);
    });
    edit(std::move(next), kind);
}

// MARK: – The hands

Timeline::Taken Timeline::take(const PadInput &input, bool isEditing, bool reachable, const DeskSettings &settings) {
    Taken taken{{}, input.frame};
    if (!reachable) {
        isLayered_ = claimsLT_ = false;
        claimed_.clear();
        rightPush_ = leftPush_ = std::nullopt;
        return taken;
    }
    isLayered_ = isEditing;

    if (isLayered_) {
        for (const PadButton button : input.edges.pressed) {
            if (!isFace(button) && !isArrow(button) && !isTool(button)) continue;
            claimed_.insert(button);
            taken.out.append(act(button, input, settings));
            // Recording or writing has begun: the rest is the chords'.
            if (!isLayered_) break;
        }
        if (isLayered_ && stretches(input.frame) && !stretches(input.previous)) claimsLT_ = true;
    } else if (writing_) {
        for (const PadButton button : input.edges.pressed) {
            if (button != PadButton::left && button != PadButton::right && button != PadButton::r3) continue;
            claimed_.insert(button);
            taken.out.append(act(button, input, settings));
        }
    }

    if (isLayered_) {

        const auto right = pushed(input.frame.right, rightPush_);
        if (right && right != rightPush_) {
            switch (*right) {
            case PadButton::left:
            case PadButton::right:
                taken.out.append(nudge((*right == PadButton::right ? 1 : -1) *
                                       (stretches(input.frame) ? grid(settings) : fine)));
                repeatAt_ = input.time() + repeatDelay;
                break;
            case PadButton::up:
                if (layer_) taken.out.append(mute(layer_, input.time()));
                break;
            default: taken.out.append(erase(input.time())); break;
            }
        } else if (selection_ && right && (*right == PadButton::left || *right == PadButton::right) &&
                   input.time() >= repeatAt_) {
            taken.out.append(nudge((*right == PadButton::right ? 1 : -1) * (stretches(input.frame) ? grid(settings) : fine)));
            repeatAt_ += repeatEvery;
        }
        rightPush_ = right;

        const auto left = pushed(input.frame.left, leftPush_);
        const auto longer = [&](PadButton way) {
            return resize((way == PadButton::up ? 1 : -1) * (stretches(input.frame) ? grid(settings) : fine));
        };
        if (left && left != leftPush_) {
            if (*left == PadButton::left) taken.out.append(undo(input.time()));
            if (*left == PadButton::right) taken.out.append(redo(input.time()));
            if (*left == PadButton::up || *left == PadButton::down) {
                taken.out.append(longer(*left));
                resizeAt_ = input.time() + repeatDelay;
            }
        } else if (selection_ && left && (*left == PadButton::up || *left == PadButton::down) &&
                   input.time() >= resizeAt_) {
            taken.out.append(longer(*left));
            resizeAt_ += repeatEvery;
        }
        leftPush_ = left;
    } else {
        rightPush_ = leftPush_ = std::nullopt;
    }

    for (const PadButton button : input.edges.released) claimed_.erase(button);
    if (input.frame.leftTrigger < 0.45) claimsLT_ = false;

    // The desk is handed the frame without what the timeline holds; the
    // chords' layer reaches it by LT (`Studio`).
    for (const PadButton button : claimed_) taken.frame.buttons.erase(button);
    taken.frame.rightTrigger = 0;
    if (claimsLT_) taken.frame.leftTrigger = 0;
    if (isLayered_) taken.frame.right = taken.frame.left = Stick::rest();
    return taken;
}

Timeline::Out Timeline::act(PadButton button, const PadInput &input, const DeskSettings &settings) {
    const double time = input.time();
    switch (button) {
    case PadButton::a: return record(time, settings);
    case PadButton::x: return stretches(input.frame) ? rewind(time, settings) : play(time, settings);
    case PadButton::y: return loop();
    case PadButton::b: return quantize(settings);
    case PadButton::left:
        if (writing_) return moveCursor(-(stretches(input.frame) ? Song::beatsPerBar : move(settings.grid)), settings);
        return moveSelection(-1, stretches(input.frame));
    case PadButton::right:
        if (writing_) return moveCursor(stretches(input.frame) ? Song::beatsPerBar : move(settings.grid), settings);
        return moveSelection(1, stretches(input.frame));
    case PadButton::r3: return toggleWrite(time, settings);
    case PadButton::lb: return deselect();
    case PadButton::rb: return save(settings);
    case PadButton::up: return moveLayer(-1);
    case PadButton::down: return moveLayer(1);
    default: return {};
    }
}

Timeline::Out Timeline::hear(const Heard &heard, double time) {
    Out out;
    if (recording_) {
        const double beat = beatAt(time);
        auto &open = recording_->open;
        Layer *layer = song_.layer(recording_->layer);
        std::set<int> voices;
        for (const auto &[voice, _] : open) voices.insert(voice);
        for (const auto &[voice, _] : heard) voices.insert(voice);
        for (const int voice : voices) {
            const auto was = open.find(voice);
            const auto now = heard.find(voice);
            if (was != open.end() && (now == heard.end() || now->second != was->second.second)) {
                const auto &[start, part] = was->second;
                if (beat - start > 0 && layer) layer->events.push_back({song_.next++, start, beat - start, part});
                open.erase(was);
            }
            if (now != heard.end() && !open.contains(voice)) open.emplace(voice, std::pair(beat, now->second));
        }
    } else if (const Layer *layer = selection_ ? song_.layer(selection_->layer) : nullptr) {
        // A chord struck while chords are chosen is written into them.
        for (const auto &[voice, part] : heard) {
            const auto before = heard_.find(voice);
            if (before != heard_.end() && before->second == part) continue;
            const Layer next = rechorded(*layer, selected(), part);
            if (next == *layer) continue;
            edit(next);
            out.append(felt(Rumble::bump));
        }
    }
    heard_ = heard;
    return out;
}

Timeline::Out Timeline::write(const Heard &heard, double time, const DeskSettings &settings) {
    Out out;
    if (!writing_) return out;
    writing_->tempo = settings.tempo;
    auto &open = writing_->open;
    const auto degree = [](const ChordPart &part) { return part.chord.spec.degree; };
    std::set<int> voices;
    for (const auto &[voice, _] : open) voices.insert(voice);
    for (const auto &[voice, _] : heard) voices.insert(voice);
    for (const int voice : voices) {
        const auto was = open.find(voice);
        const auto now = heard.find(voice);
        const bool wasOpen = was != open.end();
        if (wasOpen) {
            // A chord colored as it is held is one chord, in its last color.
            if (now != heard.end() && degree(now->second) == degree(was->second.second)) {
                was->second.second = now->second;
                continue;
            }
            out.append(place(voice, time, settings));
        }
        if (now == heard.end()) continue;
        // What was already held when Write mode began is not written.
        const auto before = heard_.find(voice);
        if (wasOpen || before == heard_.end() || degree(before->second) != degree(now->second))
            open.emplace(voice, std::pair(time, now->second));
    }
    return out;
}

Timeline::Out Timeline::place(int voice, double time, const DeskSettings &settings) {
    const auto found = writing_->open.find(voice);
    const auto [struck, part] = found->second;
    writing_->open.erase(found);
    const double held = (time - struck) * settings.tempo / 60;
    const double beats = desk::length(settings.grid, held);
    const double start = writing_->cursor;
    Song next = song_;
    if (!next.layer(layer_)) {
        next.layers.push_back({next.next++, {}, std::nullopt, false});
        layer_ = next.layers.back().id;
    }
    const int id = next.next++;
    Layer *layer = next.layer(layer_);
    *layer = written(*layer, id, start, beats, part);
    edit(std::move(next));
    writing_->cursor = start + beats;
    return felt(Rumble::bump);
}

Timeline::Out Timeline::toggleWrite(double time, const DeskSettings &settings) {
    if (recording_) return refused("Stop recording first");
    if (writing_) {
        Out out = write({}, time, settings);
        writing_.reset();
        out.append(felt(Rumble::bump));
        return out;
    }
    Out out;
    if (rolling_) out.append(pause(time));
    const Layer *chosen = layer();
    const auto span = chosen && selection_ ? chosen->span(selected()) : std::nullopt;
    double cursor = 0;
    if (span) cursor = span->to;
    else if (cue_) cursor = *cue_;
    else if (chosen)
        for (const Event &event : chosen->events) cursor = std::max(cursor, event.end());
    selection_.reset();
    writing_ = Writing{std::max(nearest(settings.grid, cursor), 0.0), settings.tempo, {}};
    isLayered_ = false;
    out.append(felt(Rumble::bump));
    return out;
}

Timeline::Out Timeline::moveCursor(double beats, const DeskSettings &settings) {
    if (!writing_) return {};
    const double next = std::max(nearest(settings.grid, writing_->cursor + beats), 0.0);
    if (next == writing_->cursor) return felt(Rumble::refuse);
    writing_->cursor = next;
    return felt(Rumble::tick);
}

Timeline::Out Timeline::save(const DeskSettings &settings) const {
    const auto file = midiFile(song_, settings);
    if (!file) return refused("Nothing to save yet");
    return {{}, {DeskEffect::saveMIDI(file->encoded(), "Perfecto Desk " + settings.summary())}};
}

Timeline::Out Timeline::advance(double time, const DeskSettings &settings) {
    Out out;
    if (!rolling_) return out;
    if (rolling_->tempo != settings.tempo) {
        rolling_->beat = beatAt(time);
        rolling_->time = time;
        rolling_->tempo = settings.tempo;
    }
    const double now = beatAt(time);
    // While recording, a tick is felt on each bar.
    if (recording_ && std::floor(now / Song::beatsPerBar) > std::floor(rolling_->heard / Song::beatsPerBar))
        out.append(felt(Rumble::tick));
    rolling_->heard = now;
    if (!recording_ && !song_.isEndless() && now >= song_.end().value_or(0)) {
        out.append(stop(time));
        return out;
    }
    const double to = beatAt(time + lookahead);
    out.append(schedule(rolling_->given, to, false, settings));
    rolling_->given = to;
    return out;
}

Timeline::Out Timeline::schedule(double from, double to, bool entering, const DeskSettings &settings) {
    Out out;
    const auto skip = recording_ ? std::optional(recording_->layer) : std::nullopt;
    const auto onsets = song_.onsets(from, to, skip, entering);
    // What is due, in time, a release before a start at the same moment: a
    // start's own release is due in turn if it ends before `to`.
    using Due = std::tuple<double, int, Track, size_t>;
    std::priority_queue<Due, std::vector<Due>, std::greater<>> due;
    for (const auto &[track, end] : sounding_)
        if (end < to) due.push({end, 0, track, 0});
    for (size_t i = 0; i < onsets.size(); ++i) due.push({onsets[i].start, 1, onsets[i].track, i});
    while (!due.empty()) {
        const auto [beat, kind, track, index] = due.top();
        due.pop();
        if (kind == 0) {
            const auto found = sounding_.find(track);
            if (found == sounding_.end() || found->second != beat) continue;
            sounding_.erase(found);
            out.playback.push_back(TimelineEffect::silence(track, timeAt(beat)));
            continue;
        }
        const auto &onset = onsets[index];
        const auto &part = std::get<ChordPart>(onset.part);
        out.playback.push_back(TimelineEffect::sound(track, part.notes,
                                                     part.voice == 0 ? settings.chordSound : settings.lineSound, level,
                                                     timeAt(beat)));
        sounding_[track] = onset.end;
        if (onset.end < to) due.push({onset.end, 0, track, 0});
    }
    return out;
}

// MARK: – What the controls do

Timeline::Out Timeline::roll(double time, double beat, const DeskSettings &settings) {
    rolling_ = Rolling{time, beat, settings.tempo, beat, beat};
    const double to = beatAt(time + lookahead);
    Out out = schedule(beat, to, true, settings);
    rolling_->given = to;
    return out;
}

Timeline::Out Timeline::record(double time, const DeskSettings &settings) {
    if (recording_) {
        Out out = finishRecording(time);
        out.append(felt(Rumble::bump));
        return out;
    }
    if (writing_) {
        cue_ = writing_->cursor;
        writing_.reset();
    }
    if (static_cast<int>(song_.layers.size()) >= Song::most)
        return refused("Eight tracks is the most: delete one to record another");
    const double from = song_.isEmpty() ? 0 : startBeat();
    const bool trims = song_.isEmpty() && !rolling_;
    Song next = song_;
    next.layers.push_back({next.next++, {}, std::nullopt, false});
    const int id = next.layers.back().id;
    edit(std::move(next));
    recording_ = Recording{id, trims, {}};
    isLayered_ = false;
    layer_ = id;
    selection_.reset();
    Out out = felt(Rumble::bump);
    if (!rolling_) out.append(roll(time, from, settings));
    return out;
}

Timeline::Out Timeline::finishRecording(double time) {
    // What is held as it stops ends there.
    const Heard held = heard_;
    hear({}, time);
    heard_ = held;
    const int id = recording_->layer;
    const bool trims = recording_->trims;
    recording_.reset();
    Layer *layer = song_.layer(id);
    if (!layer) return {};
    if (layer->events.empty()) {
        // Nothing was played: the take was never made.
        std::erase_if(song_.layers, [&](const Layer &l) { return l.id == id; });
        if (!undo_.empty()) undo_.pop_back();
        layer_ = song_.layers.empty() ? 0 : song_.layers.back().id;
        return {};
    }
    std::sort(layer->events.begin(), layer->events.end(),
              [](const Event &a, const Event &b) { return a.start != b.start ? a.start < b.start : a.id < b.id; });
    if (trims && rolling_) {
        // The first take starts where it was first played.
        const double by = -layer->events.front().start;
        *layer = shifted(*layer, by);
        rolling_->beat += by;
        rolling_->given += by;
        rolling_->heard += by;
    }
    return {};
}

Timeline::Out Timeline::play(double time, const DeskSettings &settings) {
    if (rolling_) return pause(time);
    if (writing_) {
        cue_ = writing_->cursor;
        writing_.reset();
    }
    if (song_.isEmpty()) return refused("Nothing recorded yet: press Back, then A");
    // Paused at the end, it plays from the start again.
    if (cue_ && !song_.isEndless() && *cue_ >= song_.end().value_or(0)) cue_.reset();
    Out out = felt(Rumble::bump);
    out.append(roll(time, startBeat(), settings));
    return out;
}

Timeline::Out Timeline::pause(double time) {
    if (!rolling_) return {};
    Out out;
    if (recording_) out.append(finishRecording(time));
    cue_ = std::max(beatAt(time), 0.0);
    out.append(halt());
    out.append(felt(Rumble::bump));
    return out;
}

Timeline::Out Timeline::rewind(double time, const DeskSettings &settings) {
    if (recording_) return refused("Stop recording first");
    if (writing_) writing_->cursor = 0;
    cue_.reset();
    Out out = felt(Rumble::tick);
    if (rolling_) {
        out.append(halt());
        out.append(roll(time, 0, settings));
    }
    return out;
}

Timeline::Out Timeline::stop(double time) {
    writing_.reset();
    cue_.reset();
    if (!rolling_) return {};
    Out out;
    if (recording_) out.append(finishRecording(time));
    out.append(halt());
    return out;
}

Timeline::Out Timeline::halt() {
    rolling_.reset();
    sounding_.clear();
    return {{TimelineEffect::hush()}, {}};
}

Timeline::Out Timeline::loop() {
    const Layer *chosen = layer();
    if (!chosen) return refused("Nothing recorded yet: press Back, then A");
    if (recording_ && recording_->layer == chosen->id) return refused("Stop recording first");
    if (selection_) {
        edit(looped(*chosen, selected()));
        selection_.reset();
        return felt(Rumble::bump);
    }
    if (chosen->loop) {
        Layer next = *chosen;
        next.loop.reset();
        edit(next);
        return felt(Rumble::bump);
    }
    return refused("Select chords to loop first: press Back, then ← or →");
}

Timeline::Out Timeline::quantize(const DeskSettings &settings) {
    const Layer *chosen = layer();
    if (!chosen) return refused("Nothing recorded yet: press Back, then A");
    if (recording_ && recording_->layer == chosen->id) return refused("Stop recording first");
    std::set<int> ids = selected();
    if (ids.empty())
        for (const Event &event : chosen->events) ids.insert(event.id);
    edit(quantized(*chosen, ids, grid(settings)));
    // Anything quantized away is no longer chosen.
    if (selection_ && selected().empty()) selection_.reset();
    return felt(Rumble::bump);
}

Timeline::Out Timeline::erase(double time) {
    const Layer *chosen = layer();
    if (!chosen || !selection_) return refused("Select chords to delete first: press Back, then ← or →");
    edit(erased(*chosen, selected()));
    selection_.reset();
    Out out = settle(time);
    out.append(felt(Rumble::bump));
    return out;
}

Timeline::Out Timeline::mute(int id, double time) {
    const Layer *found = song_.layer(id);
    if (!found) return {};
    Layer next = *found;
    next.isMuted = !next.isMuted;
    edit(next);
    Out out = settle(time);
    out.append(felt(Rumble::tick));
    return out;
}

Timeline::Out Timeline::moveLayer(int steps) {
    if (song_.layers.empty()) return {};
    const auto at = std::find_if(song_.layers.begin(), song_.layers.end(), [&](const Layer &l) { return l.id == layer_; });
    const int count = static_cast<int>(song_.layers.size());
    const int index = at == song_.layers.end() ? 0 : static_cast<int>(at - song_.layers.begin());
    const int next = std::clamp(index + steps, 0, count - 1);
    if (next == index && at != song_.layers.end()) return {};
    return chooseLayer(song_.layers[static_cast<size_t>(next)].id);
}

Timeline::Out Timeline::chooseLayer(int id) {
    if (!song_.layer(id)) return {};
    layer_ = id;
    if (selection_ && selection_->layer != id) selection_.reset();
    return felt(Rumble::tick);
}

Timeline::Out Timeline::moveSelection(int steps, bool stretch) {
    const Layer *chosen = layer();
    if (!chosen || chosen->events.empty()) return {};
    const auto &events = chosen->events;
    const int count = static_cast<int>(events.size());
    if (!selection_ || selection_->layer != chosen->id) {
        const int id = events[steps > 0 ? 0 : static_cast<size_t>(count - 1)].id;
        selection_ = Selection{chosen->id, id, id};
        return felt(Rumble::tick);
    }
    const auto head = std::find_if(events.begin(), events.end(), [&](const Event &e) { return e.id == selection_->head; });
    const int index = static_cast<int>(head - events.begin());
    const int next = std::clamp(index + steps, 0, count - 1);
    const int id = events[static_cast<size_t>(next)].id;
    const Selection before = *selection_;
    if (stretch) selection_->head = id;
    else selection_ = Selection{chosen->id, id, id};
    return *selection_ == before ? Out{} : felt(Rumble::tick);
}

Timeline::Out Timeline::select(int layer, int id, bool stretch) {
    const Layer *found = song_.layer(layer);
    if (!found || found->between(id, id).empty()) return {};
    writing_.reset();
    layer_ = layer;
    if (stretch && selection_ && selection_->layer == layer) selection_->head = id;
    else selection_ = Selection{layer, id, id};
    return felt(Rumble::tick);
}

Timeline::Out Timeline::deselect() {
    if (!selection_) return {};
    selection_.reset();
    return felt(Rumble::tick);
}

Timeline::Out Timeline::nudge(double beats) {
    const Layer *chosen = selection_ ? song_.layer(selection_->layer) : nullptr;
    if (!chosen) return refused("Select chords to move first: press Back, then ← or →");
    const Layer next = nudged(*chosen, selected(), beats);
    if (next == *chosen) return felt(Rumble::refuse);
    edit(next, Edit::nudge);
    return felt(Rumble::tick);
}

Timeline::Out Timeline::resize(double beats) {
    const Layer *chosen = selection_ ? song_.layer(selection_->layer) : nullptr;
    if (!chosen) return refused("Select chords to change their length: press Back, then ← or →");
    const Layer next = resized(*chosen, selected(), beats);
    if (next == *chosen) return felt(Rumble::refuse);
    edit(next, Edit::resize);
    return felt(Rumble::tick);
}

Timeline::Out Timeline::undo(double time) {
    if (recording_) return refused("Stop recording first");
    if (undo_.empty()) return refused("Nothing to undo");
    redo_.push_back(song_);
    song_ = undo_.back();
    undo_.pop_back();
    lastEdit_ = Edit::other;
    Out out = settle(time);
    out.append(felt(Rumble::bump));
    return out;
}

Timeline::Out Timeline::redo(double time) {
    if (recording_) return refused("Stop recording first");
    if (redo_.empty()) return refused("Nothing to redo");
    undo_.push_back(song_);
    song_ = redo_.back();
    redo_.pop_back();
    lastEdit_ = Edit::other;
    Out out = settle(time);
    out.append(felt(Rumble::bump));
    return out;
}

Timeline::Out Timeline::settle(double time) {
    Out out;
    for (auto track = sounding_.begin(); track != sounding_.end();) {
        const Layer *layer = song_.layer(track->first.layer);
        if (layer && !layer->isMuted) {
            ++track;
            continue;
        }
        out.playback.push_back(TimelineEffect::silence(track->first, time));
        track = sounding_.erase(track);
    }
    if (selection_ && selected().empty()) selection_.reset();
    if (!song_.layer(layer_)) layer_ = song_.layers.empty() ? 0 : song_.layers.back().id;
    if (song_.isEmpty()) cue_.reset();
    return out;
}

// MARK: – The legend

Legend Timeline::legend(Legend legend, bool reachable) const {
    if (!reachable) return legend;
    const auto button = [](PadButton b) { return PadControl::button(b); };
    if (!isLayered_) {
        if (selection_)
            for (const PadButton face : {PadButton::a, PadButton::b, PadButton::x, PadButton::y}) {
                const auto found = legend.find(button(face));
                if (found != legend.end()) found->second = "Replace selected: " + found->second;
            }
        if (writing_)
            for (const PadButton face : {PadButton::a, PadButton::b, PadButton::x, PadButton::y}) {
                const auto found = legend.find(button(face));
                if (found != legend.end()) found->second = "Write: " + found->second;
            }
        if (writing_) {
            legend[button(PadButton::left)] = "Cursor back";
            legend[button(PadButton::right)] = "Cursor on";
            legend[button(PadButton::r3)] = "Leave Write mode";
        }
        return legend;
    }
    const Layer *chosen = layer();
    legend[button(PadButton::a)] = recording_ ? "Stop recording" : "Record a new track";
    legend[button(PadButton::x)] = rolling_ ? "Pause" : "Play";
    legend[button(PadButton::y)] = selection_ ? "Loop selection" : chosen && chosen->loop ? "Stop looping" : "Loop (select first)";
    legend[button(PadButton::b)] = selection_ ? "Fix timing of selection" : "Fix timing of track";
    legend[button(PadButton::left)] = writing_ ? "Cursor back" : "Select previous chord";
    legend[button(PadButton::right)] = writing_ ? "Cursor on" : "Select next chord";
    legend[button(PadButton::r3)] = writing_ ? "Leave Write mode" : "Write mode";
    legend[button(PadButton::up)] = "Track above";
    legend[button(PadButton::down)] = "Track below";
    legend[PadControl::leftTrigger()] = writing_ ? "Cursor by a bar · with X, back to start"
                                                  : "Select more · a grid step · with X, back to start";
    legend[PadControl::rightStick()] = "← → move earlier / later · ↑ mute track · ↓ delete";
    legend[PadControl::leftStick()] = "← undo · → redo · ↑ longer · ↓ shorter";
    return legend;
}

} // namespace perfecto::desk
