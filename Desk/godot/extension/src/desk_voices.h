// The desk's lines of notes on the kernel: what each line sounds, by the
// kernel's note ids, struck, tied, shaped and let go as the desk's effects
// say (the Mac desk's `DeskAudio`).

#ifndef DESK_VOICES_H
#define DESK_VOICES_H

#include "perfecto_stream.h"

#include <perfecto/desk/music.hpp>

#include <godot_cpp/classes/ref.hpp>

#include <map>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace perfecto_godot {

class DeskVoices {
public:
    /// `sounds` gives each preset's id its number among the kernel's sounds.
    DeskVoices(godot::Ref<PerfectoStream> stream, std::map<std::string, int> sounds);

    /// Sounds `notes` on `line` in place of what it sounds; tied, a note
    /// sounding already is held over.
    void sound(perfecto::desk::Line line, const std::vector<int> &notes, const std::string &sound, double level,
               double brightness, bool tie);
    /// Glides what `line` sounds.
    void shape(perfecto::desk::Line line, double level, double brightness, double bend);
    void silence(perfecto::desk::Line line);
    void silenceAll();
    /// Plays `notes` in `sound` for a moment, to hear it while choosing it.
    void preview(const std::string &sound, const std::vector<int> &notes, double time);
    /// Ends a preview whose moment has passed.
    void tick(double time);
    /// The delay's echoes are a dotted eighth apart, as the phone's are.
    void setTempo(double bpm);

private:
    godot::Ref<PerfectoStream> stream_;
    std::map<std::string, int> sounds_;
    std::map<perfecto::desk::Line, std::vector<std::pair<int64_t, int>>> sounding_;
    std::vector<int64_t> previewing_;
    std::optional<double> previewEnd_;
    int64_t lastID_ = 0;

    int number(const std::string &sound) const;
    PerfectoStream::Playing playing(perfecto::desk::Line line, double level, double brightness, double bend) const;
    void endPreview();
};

} // namespace perfecto_godot

#endif
