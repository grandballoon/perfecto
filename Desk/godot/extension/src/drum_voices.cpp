#include "drum_voices.h"

#include <perfecto/drumkit/kit.hpp>

#include <algorithm>
#include <array>

using perfecto::desk::Drum;
namespace kit = perfecto::drumkit;

namespace perfecto_godot {

namespace {

/// A way of playing one of the kit's recordings: a sampled patch.
struct Patch {
    kit::Sample sample;
    /// Seconds in which it falls to 37%, once struck; and how quickly it
    /// stops when choked.
    float decay;
    float sustain;
    float release;
    /// How loud a full strike is.
    float level;
};

/// The patches, in the order of their sounds from the first: the kick and
/// toms, the snare, the closed hat, the open hat, the clap.
constexpr std::array<Patch, 5> patches = {{
    {kit::Sample::kick, 10, 1, 0.04f, 0.55f},
    {kit::Sample::snare, 10, 1, 0.04f, 0.42f},
    {kit::Sample::hat, 0.035f, 0, 0.02f, 0.30f},
    {kit::Sample::hat, 10, 1, 0.03f, 0.26f},
    {kit::Sample::clap, 10, 1, 0.04f, 0.38f},
}};

/// A drum: which patch, how far above the recording's own pitch it is
/// played (in semitones), where it sits left to right, and its share of the
/// room.
struct Voice {
    int patch;
    int pitch;
    float pan;
    float reverb;
};

Voice voice(Drum drum) {
    switch (drum) {
    case Drum::kick: return {0, 0, 0, 0.02f};
    case Drum::snare: return {1, 0, 0.04f, 0.14f};
    case Drum::closedHat: return {2, 0, 0.22f, 0.06f};
    case Drum::openHat: return {3, 0, 0.22f, 0.10f};
    case Drum::clap: return {4, 0, -0.06f, 0.18f};
    case Drum::lowTom: return {0, 7, -0.28f, 0.12f};
    case Drum::midTom: return {0, 11, -0.08f, 0.12f};
    case Drum::highTom: return {0, 15, 0.14f, 0.12f};
    }
    return {};
}

/// The pitch every recording is played at as it was made.
constexpr int root = 60;
/// The kit is made at this rate, and the kernel plays it at its own.
constexpr double kitRate = 48000;

/// Which capture holds `sample`: the kit takes all four, in its order.
int capture(kit::Sample sample) {
    return int(std::find(kit::allSamples.begin(), kit::allSamples.end(), sample) - kit::allSamples.begin());
}

PerfectoPatch sampled(const Patch &patch) {
    PerfectoPatch p{};
    p.sampled = true;
    p.capture = capture(patch.sample);
    p.root = float(root);
    p.attack = 0.0005f;
    p.decay = patch.decay;
    p.sustain = patch.sustain;
    p.release = patch.release;
    p.level = patch.level;
    return p;
}

} // namespace

DrumVoices::DrumVoices(godot::Ref<PerfectoStream> stream, int firstSound)
    : stream_(std::move(stream)), firstSound_(firstSound) {
    for (const kit::Sample sample : kit::allSamples)
        stream_->load_capture(capture(sample), kit::render(sample, kitRate), kitRate);
    for (size_t i = 0; i < patches.size(); ++i) stream_->set_patch(firstSound_ + int(i), sampled(patches[i]));
}

int DrumVoices::soundCount() { return int(patches.size()); }

void DrumVoices::hit(Drum drum, double level, double ahead) {
    const Voice v = voice(drum);
    const float strength = float(std::clamp(level, 0.0, 1.0));
    stream_->start(++lastID_, root + v.pitch, strength, firstSound_ + v.patch, v.pan,
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
