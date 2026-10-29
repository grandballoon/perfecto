#include "timeline_voices.h"

#include <algorithm>

namespace perfecto_godot {

namespace {

/// As the desk's chords are struck (`DeskVoices`): the level is the note's
/// own, spread a little from side to side, in a little of the room.
constexpr float velocity = 0.7f;
constexpr float spread = 0.3f;
constexpr float reverb = 0.16f;

} // namespace

TimelineVoices::TimelineVoices(godot::Ref<PerfectoStream> stream, std::map<std::string, int> sounds)
    : stream_(std::move(stream)), sounds_(std::move(sounds)) {}

void TimelineVoices::sound(const perfecto::desk::Track &track, const std::vector<int> &notes, const std::string &sound,
                           double level, double ahead) {
    silence(track, ahead);
    const auto found = sounds_.find(sound);
    const int number = found == sounds_.end() ? 0 : found->second;
    const int64_t frame = stream_->frame_ahead(ahead);
    const PerfectoStream::Playing playing{1, reverb, 0, float(std::clamp(level, 0.0, 1.0))};
    auto &ids = sounding_[track];
    for (size_t i = 0; i < notes.size(); ++i) {
        const float pan = notes.size() > 1 ? spread * (2 * float(i) / float(notes.size() - 1) - 1) : 0;
        stream_->start(++lastID_, notes[i], velocity, number, pan, playing, frame);
        ids.push_back(lastID_);
    }
}

void TimelineVoices::silence(const perfecto::desk::Track &track, double ahead) {
    const auto found = sounding_.find(track);
    if (found == sounding_.end()) return;
    const int64_t frame = stream_->frame_ahead(ahead);
    for (const int64_t id : found->second) stream_->note_off(id, frame);
    sounding_.erase(found);
}

void TimelineVoices::silenceAll() {
    for (const auto &[_, ids] : sounding_)
        for (const int64_t id : ids) stream_->note_off(id, -1);
    sounding_.clear();
}

} // namespace perfecto_godot
