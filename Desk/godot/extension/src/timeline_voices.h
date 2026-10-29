// What the timeline plays back, on the kernel: each track's notes, by the
// kernel's note ids, struck and let go on the frame each effect is stamped
// for (`TimelineEffect`), so playback is as steady as the song it plays.

#ifndef TIMELINE_VOICES_H
#define TIMELINE_VOICES_H

#include "perfecto_stream.h"

#include <perfecto/desk/song.hpp>

#include <godot_cpp/classes/ref.hpp>

#include <map>
#include <string>
#include <utility>
#include <vector>

namespace perfecto_godot {

class TimelineVoices {
public:
    /// `sounds` gives each preset's id its number among the kernel's sounds.
    TimelineVoices(godot::Ref<PerfectoStream> stream, std::map<std::string, int> sounds);

    /// Sounds `notes` on `track` in place of what it sounds, `ahead`
    /// seconds from now.
    void sound(const perfecto::desk::Track &track, const std::vector<int> &notes, const std::string &sound,
               double level, double ahead);
    /// Lets go of what `track` sounds, `ahead` seconds from now.
    void silence(const perfecto::desk::Track &track, double ahead);
    void silenceAll();

private:
    godot::Ref<PerfectoStream> stream_;
    std::map<std::string, int> sounds_;
    std::map<perfecto::desk::Track, std::vector<int64_t>> sounding_;
    /// Above the desk's own ids and below the drums' (`DrumVoices`), so they
    /// never meet.
    int64_t lastID_ = int64_t(1) << 40;
};

} // namespace perfecto_godot

#endif
