#include "desk_voices.h"

#include <algorithm>

using perfecto::desk::Line;

namespace perfecto_godot {

namespace {

/// How hard every note is struck: the strike's level is the note's own,
/// which a change glides.
constexpr float velocity = 0.7f;
/// How far a chord's lowest and highest notes sit to either side.
constexpr float spread = 0.3f;
/// How long a preview sounds.
constexpr double previewTime = 0.7;
/// Notes are struck a lead ahead, so each is as late as every other.
constexpr int64_t lead = -1;

/// Each line's share of the room: a little, so the desk sounds like a
/// place without an effects page to set it.
float reverb(Line line) { return line == Line::chord ? 0.16f : 0.22f; }

float unit(double value) { return float(std::clamp(value, 0.0, 1.0)); }

} // namespace

DeskVoices::DeskVoices(godot::Ref<PerfectoStream> stream, std::map<std::string, int> sounds)
    : stream_(std::move(stream)), sounds_(std::move(sounds)) {
    stream_->set_mix(0.8f, 2.6f, 0.02f, 5200, 0.47f, 0.35f);
}

int DeskVoices::number(const std::string &sound) const {
    const auto found = sounds_.find(sound);
    return found == sounds_.end() ? 0 : found->second;
}

PerfectoStream::Playing DeskVoices::playing(Line line, double level, double brightness, double bend) const {
    return {unit(brightness), reverb(line), float(bend), unit(level)};
}

void DeskVoices::sound(Line line, const std::vector<int> &notes, const std::string &sound, double level,
                       double brightness, bool tie) {
    auto &sounding = sounding_[line];
    std::vector<std::pair<int64_t, int>> held;
    if (tie)
        for (const auto &note : sounding)
            if (std::find(notes.begin(), notes.end(), note.second) != notes.end()) held.push_back(note);
    for (const auto &note : sounding)
        if (std::find(held.begin(), held.end(), note) == held.end()) stream_->note_off(note.first, lead);
    auto next = held;
    for (size_t i = 0; i < notes.size(); ++i) {
        const int note = notes[i];
        if (std::any_of(held.begin(), held.end(), [&](const auto &h) { return h.second == note; })) continue;
        const float pan = notes.size() > 1 ? spread * (2 * float(i) / float(notes.size() - 1) - 1) : 0;
        stream_->start(++lastID_, note, velocity, number(sound), pan, playing(line, level, brightness, 0), lead);
        next.emplace_back(lastID_, note);
    }
    sounding = next;
}

void DeskVoices::shape(Line line, double level, double brightness, double bend) {
    for (const auto &note : sounding_[line]) stream_->change(note.first, playing(line, level, brightness, bend), lead);
}

void DeskVoices::silence(Line line) {
    for (const auto &note : sounding_[line]) stream_->note_off(note.first, lead);
    sounding_[line].clear();
}

void DeskVoices::silenceAll() {
    for (const Line line : perfecto::desk::allLines) silence(line);
}

void DeskVoices::preview(const std::string &sound, const std::vector<int> &notes, double time) {
    endPreview();
    for (const int note : notes) {
        stream_->start(++lastID_, note, velocity, number(sound), 0, playing(Line::chord, 0.8, 1, 0), lead);
        previewing_.push_back(lastID_);
    }
    previewEnd_ = time + previewTime;
}

void DeskVoices::tick(double time) {
    if (previewEnd_ && time >= *previewEnd_) endPreview();
}

void DeskVoices::endPreview() {
    for (const int64_t id : previewing_) stream_->note_off(id, lead);
    previewing_.clear();
    previewEnd_.reset();
}

void DeskVoices::setTempo(double bpm) { stream_->set_delay_time(float(60 / bpm * 0.75)); }

} // namespace perfecto_godot
