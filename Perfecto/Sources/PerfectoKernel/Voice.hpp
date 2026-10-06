// One note's sound. This is the skeleton's voice: a sine with a short
// attack and release, enough to prove notes start, end and overlap on the
// right frames. The real sources, filters and envelopes replace its insides.

#ifndef PERFECTO_VOICE_HPP
#define PERFECTO_VOICE_HPP

#include <cstdint>

namespace perfecto {

struct Voice {
    enum class Stage : uint8_t {
        /// Silent and free to take a note.
        free,
        /// Sounding a note that has not been ended.
        held,
        /// Dying away after its note ended.
        released,
        /// Being faded out fast to make way for `waiting`.
        stolen,
    };

    /// A note taking over a voice, started once the voice has faded out.
    struct Waiting {
        uint64_t id = 0;
        int32_t note = 0;
        float velocity = 0;
    };

    Stage stage = Stage::free;
    uint64_t id = 0;
    /// When the voice last started a note, as a count of notes started.
    uint64_t startedAt = 0;
    Waiting waiting;

    /// Where the sine is in its cycle, 0..<1, and how far it moves a frame.
    double phase = 0;
    double phaseStep = 0;
    /// The voice's loudness now, the loudness it is heading for, and how
    /// far it moves towards it each frame.
    float level = 0;
    float target = 0;
    float levelStep = 0;
};

}

#endif
