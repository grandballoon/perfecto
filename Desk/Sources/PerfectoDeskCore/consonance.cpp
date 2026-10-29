#include "perfecto/desk/consonance.hpp"

#include "perfecto/desk/music.hpp"
#include "perfecto/desk/voice_leading.hpp"

#include <algorithm>
#include <iterator>

namespace perfecto::desk {

using namespace theory;

std::string name(GuardMode mode) {
    switch (mode) {
    case GuardMode::off: return "Off";
    case GuardMode::always: return "Always";
    case GuardMode::sounding: return "With what's sounding";
    case GuardMode::run: return "With the run";
    }
    return {};
}

std::set<int> ConsonanceGuard::pool() const {
    std::set<int> all;
    for (const auto &chord : recent_) all.insert(chord.begin(), chord.end());
    return all;
}

void ConsonanceGuard::hear(const std::vector<DeskEffect> &effects) {
    for (const DeskEffect &effect : effects) {
        const auto &value = effect.value();
        if (const auto *sound = std::get_if<DeskEffect::Sound>(&value)) {
            if (sound->line == Line::chord && sound->notes.size() >= 2) {
                std::set<int> pitches;
                for (int note : sound->notes) pitches.insert(((note % 12) + 12) % 12);
                chord_ = pitches;
                if (recent_.empty() || recent_.back() != pitches) {
                    recent_.push_back(pitches);
                    if (static_cast<int>(recent_.size()) > window) recent_.erase(recent_.begin());
                }
            } else if (sound->line == Line::melody) {
                if (sound->notes.empty()) note_ = std::nullopt;
                else note_ = ((sound->notes.front() % 12) + 12) % 12;
            }
        } else if (const auto *silence = std::get_if<DeskEffect::Silence>(&value)) {
            if (silence->line == Line::chord) chord_ = std::nullopt;
            else note_ = std::nullopt;
        }
    }
}

namespace {

std::set<int> with(std::set<int> pitches, int pitch) {
    pitches.insert(pitch);
    return pitches;
}

bool disjoint(const std::set<int> &a, const std::set<int> &b) {
    return std::none_of(a.begin(), a.end(), [&](int p) { return b.contains(p); });
}

} // namespace

std::optional<std::string> ConsonanceGuard::refusal(const DeskChord &chord, const Key &key) const {
    if (mode == GuardMode::off) return std::nullopt;
    const std::set<int> pitches = chord.pitchClasses();
    if (!VoiceLeading::isConsonant(pitches)) return chord.name() + " is not consonant";
    if (inKey && !std::all_of(pitches.begin(), pitches.end(), [&](int p) { return key.has(p); }))
        return chord.name() + " is outside the key";
    switch (mode) {
    case GuardMode::off:
    case GuardMode::always: return std::nullopt;
    case GuardMode::sounding:
        if (chord_ && *chord_ != pitches && disjoint(*chord_, pitches))
            return chord.name() + " shares no note with what is sounding";
        if (note_ && !pitches.contains(*note_) && !VoiceLeading::isConsonant(with(pitches, *note_)))
            return chord.name() + " clashes with the line's note";
        return std::nullopt;
    case GuardMode::run: {
        const std::set<int> pool = this->pool();
        std::vector<int> outside;
        std::set_difference(pitches.begin(), pitches.end(), pool.begin(), pool.end(), std::back_inserter(outside));
        if (!pool.empty() && outside.size() > 1) return chord.name() + " is outside the run";
        return std::nullopt;
    }
    }
    return std::nullopt;
}

std::optional<std::string> ConsonanceGuard::refusalOfNote(int note, const Key &key) const {
    if (mode == GuardMode::off) return std::nullopt;
    const int pitch = ((note % 12) + 12) % 12;
    const std::string name = theory::name(pitchClass(pitch));
    if (!(key.has(note) || (!inKey && mode != GuardMode::always))) return name + " is outside the key";
    switch (mode) {
    case GuardMode::off:
    case GuardMode::always: return std::nullopt;
    case GuardMode::sounding:
        if (chord_ && !chord_->contains(pitch) && !VoiceLeading::isConsonant(with(*chord_, pitch)))
            return name + " clashes with the chord";
        return std::nullopt;
    case GuardMode::run: {
        const std::set<int> pool = this->pool();
        if (!pool.empty() && !pool.contains(pitch)) return name + " is outside the run";
        return std::nullopt;
    }
    }
    return std::nullopt;
}

bool ConsonanceGuard::allows(const DeskChord &chord, const Key &key) const { return !refusal(chord, key); }

bool ConsonanceGuard::allowsNote(int note, const Key &key) const { return !refusalOfNote(note, key); }

// DeskSettings, from Consonance.swift.

bool DeskSettings::playable(const DeskChord &chord) const { return consonance.allows(chord, key); }

void DeskSettings::moveGuard(int steps) {
    const int count = static_cast<int>(allGuardModes.size());
    const int at = static_cast<int>(std::find(allGuardModes.begin(), allGuardModes.end(), consonance.mode) -
                                    allGuardModes.begin());
    consonance.mode = allGuardModes[static_cast<size_t>(((at + steps) % count + count) % count)];
}

} // namespace perfecto::desk
