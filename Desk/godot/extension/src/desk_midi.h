// The desk's notes as MIDI, from a virtual source called "Perfecto Desk"
// that a DAW on the same machine lists among its inputs (the Mac desk's
// `DeskMIDI`).
//
// The chords are on channel 1 and the line on channel 2, so a DAW can give
// each its own instrument; the drums are on channel 10, as General MIDI has
// them, each hit stamped with the moment it sounds. A note's velocity is how hard it was struck, and
// what is played on a held note goes out as controllers: its level as
// expression (CC 11), its brightness as CC 74, and a slide as pitch bend
// over ±24 semitones (set by RPN 0 when the source is made).
//
// The messages are worked out here on every platform; only sending them is
// the platform's (CoreMIDI on the Mac; none elsewhere yet).

#ifndef DESK_MIDI_H
#define DESK_MIDI_H

#include <perfecto/desk/music.hpp>

#include <array>
#include <cstdint>
#include <map>
#include <memory>
#include <string>
#include <vector>

namespace perfecto_godot {

class DeskMidi {
public:
    explicit DeskMidi(const std::string &name = "Perfecto Desk");
    ~DeskMidi();
    DeskMidi(const DeskMidi &) = delete;
    DeskMidi &operator=(const DeskMidi &) = delete;

    /// Whether the source was made: a DAW can hear it.
    bool isReady() const;

    void sound(perfecto::desk::Line line, const std::vector<int> &notes, double level, double brightness, bool tie);
    void shape(perfecto::desk::Line line, double level, double brightness, double bend);
    void silence(perfecto::desk::Line line);
    void silenceAll();
    /// Strikes the drum `note` (General MIDI's), `level` hard, `ahead`
    /// seconds from now, and lets it go a moment after.
    void hit(int note, double level, double ahead);

    static constexpr uint8_t bendRange = 24;

private:
    struct Sent {
        uint8_t level;
        uint8_t brightness;
        uint16_t bend;
    };

    struct Port;
    std::unique_ptr<Port> port_;
    std::map<perfecto::desk::Line, std::vector<int>> sounding_;
    /// The level each line's notes were struck at: what is played after is
    /// expression relative to it.
    std::map<perfecto::desk::Line, double> struck_;
    /// What was last sent to each line's controllers, so nothing is sent twice.
    std::map<perfecto::desk::Line, Sent> sent_;

    /// Sends `messages` now, or `ahead` seconds from now.
    void send(const std::vector<std::array<uint8_t, 3>> &messages, double ahead = 0);
};

} // namespace perfecto_godot

#endif
