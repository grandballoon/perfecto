#include "drum_voices.h"

#include <perfecto/drumkit/kit.hpp>

#include <godot_cpp/variant/utility_functions.hpp>

#include <algorithm>

using perfecto::desk::Drum;
namespace kit = perfecto::drumkit;

namespace perfecto_godot {

namespace {

/// The kit's recording of `drum`: the same drums, in the same order.
kit::Piece piece(Drum drum) {
    switch (drum) {
    case Drum::kick: return kit::Piece::kick;
    case Drum::snare: return kit::Piece::snare;
    case Drum::closedHat: return kit::Piece::closedHat;
    case Drum::openHat: return kit::Piece::openHat;
    case Drum::clap: return kit::Piece::clap;
    case Drum::lowTom: return kit::Piece::lowTom;
    case Drum::midTom: return kit::Piece::midTom;
    case Drum::highTom: return kit::Piece::highTom;
    }
    return kit::Piece::kick;
}

/// A drum: how loud a full strike is, where it sits left to right, and its
/// share of the room.
struct Voice {
    float level;
    float pan;
    float reverb;
};

Voice voice(Drum drum) {
    switch (drum) {
    case Drum::kick: return {0.55f, 0, 0.02f};
    case Drum::snare: return {0.42f, 0.04f, 0.14f};
    case Drum::closedHat: return {0.30f, 0.22f, 0.06f};
    case Drum::openHat: return {0.26f, 0.22f, 0.10f};
    case Drum::clap: return {0.38f, -0.06f, 0.18f};
    case Drum::lowTom: return {0.45f, -0.28f, 0.12f};
    case Drum::midTom: return {0.45f, -0.08f, 0.12f};
    case Drum::highTom: return {0.45f, 0.14f, 0.12f};
    }
    return {};
}

/// The pitch every recording is played at as it was made.
constexpr int root = 60;
/// The kits are made at this rate, and the kernel plays them at its own.
constexpr double kitRate = 48000;

constexpr int pieceCount = int(kit::allPieces.size());

/// Which loaded sample, and which of the drums' sounds, holds `piece` of the
/// kit numbered `kit`: the kits one after another, each in its pieces'
/// order.
int slot(int kit, kit::Piece piece) { return kit * pieceCount + int(piece); }

PerfectoPatch sampled(int sample, float level) {
    PerfectoPatch p{};
    p.sampled = true;
    p.loaded = true;
    p.capture = sample;
    p.root = float(root);
    // Each recording has its own decay: the patch only plays it, and ends
    // it quickly when choked.
    p.attack = 0.0005f;
    p.decay = 10;
    p.sustain = 1;
    p.release = 0.03f;
    p.level = level;
    return p;
}

} // namespace

DrumVoices::DrumVoices(godot::Ref<PerfectoStream> stream, int firstSound)
    : stream_(std::move(stream)), firstSound_(firstSound) {
    const int needed = int(kit::kits().size()) * pieceCount;
    if (needed > stream_->sample_count() || firstSound_ + needed > stream_->sound_count()) {
        godot::UtilityFunctions::push_error("The drum kits need more of the kernel's samples or sounds than it has.");
        return;
    }
    for (int k = 0; k < int(kit::kits().size()); ++k)
        for (const Drum drum : perfecto::desk::allDrums) {
            const int s = slot(k, piece(drum));
            stream_->load_sample(s, kit::render(kit::kits()[size_t(k)], piece(drum), kitRate), kitRate);
            stream_->set_patch(firstSound_ + s, sampled(s, voice(drum).level));
        }
}

std::vector<std::string> DrumVoices::kits() {
    std::vector<std::string> names;
    for (const auto &each : kit::kits()) names.push_back(each.name);
    return names;
}

void DrumVoices::hit(Drum drum, int kit, double level, double ahead) {
    if (kit < 0 || kit >= int(kit::kits().size())) return;
    const Voice v = voice(drum);
    const float strength = float(std::clamp(level, 0.0, 1.0));
    stream_->start(++lastID_, root, strength, firstSound_ + slot(kit, piece(drum)), v.pan,
                   PerfectoStream::Playing{1, v.reverb, 0, 1}, stream_->frame_ahead(ahead));
    // A recording ends by itself; only the last few of a drum can still be
    // choked, so no more are kept.
    auto &ids = sounding_[drum];
    ids.push_back(lastID_);
    if (ids.size() > 4) ids.erase(ids.begin());
}

void DrumVoices::choke(Drum drum, double ahead) {
    auto &ids = sounding_[drum];
    const int64_t frame = stream_->frame_ahead(ahead);
    for (const int64_t id : ids) stream_->note_off(id, frame);
    ids.clear();
}

} // namespace perfecto_godot
