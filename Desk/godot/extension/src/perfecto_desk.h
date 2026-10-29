// The desk in Godot: it holds the `Band` (the desk and the drums), gives it a
// frame from the controller and the keyboard each time it is stepped, and
// performs what it returns, its notes and drums on the kernel and MIDI and
// its rumbles on the controller's motors. Everything it decides is the core's; the scripts
// draw the scene it shows and hand over what is left to them (a notice, a
// file to save).
//
//     desk.gd ── step() ──→ PerfectoDesk ── frame ──→ perfecto::desk::Band
//        ↑                    │   ↑                          │
//        └── scene(), the     │   └──────── effects ─────────┘
//            effects left     ├─→ DeskVoices, DrumVoices → PerfectoStream (the kernel)
//                             ├─→ DeskMidi ("Perfecto Desk")
//                             └─→ Input (rumble)

#ifndef PERFECTO_DESK_H
#define PERFECTO_DESK_H

#include "desk_midi.h"
#include "desk_voices.h"
#include "drum_voices.h"
#include "perfecto_stream.h"

#include <perfecto/desk/band.hpp>
#include <perfecto/desk/scene.hpp>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include <map>
#include <memory>
#include <optional>
#include <vector>

namespace perfecto_godot {

class PerfectoDesk : public godot::RefCounted {
    GDCLASS(PerfectoDesk, godot::RefCounted)

public:
    PerfectoDesk();
    ~PerfectoDesk() override;

    /// Plays on `stream`, whose sounds are `presets` in order (each with
    /// its id, name and category, as `presets.json` has them), and the
    /// drums on the sounds after them. Before the stream plays: the drums'
    /// recordings are loaded into the kernel.
    void setup(const godot::Ref<PerfectoStream> &stream, const godot::Array &presets);

    /// One frame: the controller and, if `keyboard`, the keyboard, read now.
    /// Returns what is left to the scripts: notices, rumbles to show and
    /// files to save, each a Dictionary with its `kind`.
    godot::Array step(bool keyboard);

    /// Does what the mouse chose (an `Action`, as `actionOf` reads it).
    godot::Array perform(const godot::Dictionary &action);

    /// What the screen shows now, and whether it differs from the last asked for.
    godot::Dictionary scene();
    bool scene_changed() const;

    /// The notes each line is sounding: {"chord": [...], "melody": [...]}.
    godot::Dictionary sounding() const;

    /// What plays: a controller's name, or "Keyboard".
    godot::String input_name() const;
    bool has_controller() const { return device_.has_value(); }
    bool midi_ready() const { return midi_ && midi_->isReady(); }

    /// Lets go of everything: the app is quitting.
    void let_go();

    /// Plays Face Chords' face buttons by two layers, without LT and with it:
    /// each a joypad button (A to Y) to a degree's index (0 is I).
    void set_face_map(const godot::Dictionary &plain, const godot::Dictionary &layered);

protected:
    static void _bind_methods();

private:
    std::optional<perfecto::desk::Band> band_;
    godot::Ref<PerfectoStream> stream_;
    std::unique_ptr<DeskVoices> voices_;
    std::unique_ptr<DrumVoices> drums_;
    std::unique_ptr<DeskMidi> midi_;
    std::map<perfecto::desk::Line, std::vector<int>> sounding_;
    std::optional<int> device_;
    /// The second knock of a refusal, due at this time.
    std::optional<double> knock_;
    int blockMax_ = 0;
    std::optional<perfecto::desk::Scene> shown_;

    double now() const;
    perfecto::desk::GamepadFrame frame(double time, bool keyboard);
    godot::Array play(const perfecto::desk::Band::Played &played, double time);
    void drum(const perfecto::desk::DrumEffect &effect, double time);
    void settingsChanged(const perfecto::desk::DeskSettings &before);
    void rumble(perfecto::desk::Rumble kind, double time);
    void followRenders();
};

} // namespace perfecto_godot

#endif
