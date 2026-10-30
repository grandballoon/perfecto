// The drums on the kernel: every kit rendered into the kernel's loaded
// samples, a sampled patch for each drum of each, and each hit struck on the
// kernel's frame for the moment the desk's core gave it, in the kit it says.
//
// Every kit is loaded at once, before the stream plays, so choosing one is
// instant and never touches the kernel while it renders. What each drum is
// made of (which recording, how loud, where it sits and how much of the
// room it has) is a table here; when it sounds, and in which kit, is the
// core's.

#ifndef DRUM_VOICES_H
#define DRUM_VOICES_H

#include "perfecto_stream.h"

#include <perfecto/desk/drums.hpp>

#include <godot_cpp/classes/ref.hpp>

#include <map>
#include <string>
#include <vector>

namespace perfecto_godot {

class DrumVoices {
public:
    /// Renders every kit into `stream`'s loaded samples and gives their
    /// patches the sounds from `firstSound` on. While nothing renders:
    /// before the stream plays.
    DrumVoices(godot::Ref<PerfectoStream> stream, int firstSound);

    /// The kits' names, in the order the core numbers them.
    static std::vector<std::string> kits();

    /// Strikes `drum` of the kit numbered `kit`, `level` hard, `ahead`
    /// seconds from now.
    void hit(perfecto::desk::Drum drum, int kit, double level, double ahead);
    /// Stops what `drum` sounds, in any kit, `ahead` seconds from now.
    void choke(perfecto::desk::Drum drum, double ahead);

private:
    godot::Ref<PerfectoStream> stream_;
    int firstSound_;
    /// The notes each drum has struck that may still sound, by their ids.
    std::map<perfecto::desk::Drum, std::vector<int64_t>> sounding_;
    /// Drum notes' ids, far from the desk's lines' (`DeskVoices`) and the
    /// timeline's tracks' (`TimelineVoices`, from 1 << 40).
    int64_t lastID_ = int64_t(1) << 41;
};

} // namespace perfecto_godot

#endif
