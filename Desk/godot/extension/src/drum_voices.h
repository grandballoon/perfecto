// The drums on the kernel: the kit rendered into its four captures, a
// sampled patch for each way a recording is played, and each hit struck on
// the kernel's frame for the moment the desk's core gave it.
//
// What each drum is made of (which recording, how high, where it sits and
// how much of the room it has) is a table here; when it sounds is the
// core's.

#ifndef DRUM_VOICES_H
#define DRUM_VOICES_H

#include "perfecto_stream.h"

#include <perfecto/desk/drums.hpp>

#include <godot_cpp/classes/ref.hpp>

#include <map>
#include <vector>

namespace perfecto_godot {

class DrumVoices {
public:
    /// Renders the kit into `stream`'s captures and gives its patches the
    /// sounds from `firstSound` on. While nothing renders: before the
    /// stream plays.
    DrumVoices(godot::Ref<PerfectoStream> stream, int firstSound);

    /// How many sounds the kit's patches take.
    static int soundCount();

    /// Strikes `drum`, `level` hard, `ahead` seconds from now.
    void hit(perfecto::desk::Drum drum, double level, double ahead);
    /// Stops what `drum` sounds, `ahead` seconds from now.
    void choke(perfecto::desk::Drum drum, double ahead);

private:
    godot::Ref<PerfectoStream> stream_;
    int firstSound_;
    /// The notes each drum has struck that may still sound, by their ids.
    std::map<perfecto::desk::Drum, std::vector<int64_t>> sounding_;
    /// Drum notes' ids, far from the desk's lines' (`DeskVoices`).
    int64_t lastID_ = int64_t(1) << 40;
};

} // namespace perfecto_godot

#endif
