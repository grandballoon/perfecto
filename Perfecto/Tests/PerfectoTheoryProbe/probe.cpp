#include "perfecto_theory_probe.h"

#include "perfecto/theory/chord_wire.hpp"
#include "perfecto/theory/color_ring.hpp"
#include "perfecto/theory/color_steps.hpp"
#include "perfecto/theory/grid.hpp"
#include "perfecto/theory/key_degree.hpp"
#include "perfecto/theory/midi_file.hpp"
#include "perfecto/theory/naming.hpp"
#include "perfecto/theory/step_compass.hpp"
#include "perfecto/theory/voicing.hpp"

#include <algorithm>
#include <cstring>

using namespace perfecto::theory;

namespace {

Key key(int root, int scale) { return {pitchClass(root), allScaleTypes[scale]}; }

std::optional<HeptatonicMode> mode(int index) {
    if (index < 0) return std::nullopt;
    return allHeptatonicModes[index];
}

std::vector<int> pitchClasses(int mask) {
    std::vector<int> out;
    for (int pc = 0; pc < 12; ++pc)
        if (mask & (1 << pc)) out.push_back(pc);
    return out;
}

int mask(const std::vector<int> &pcs) {
    int out = 0;
    for (int pc : pcs) out |= 1 << pc;
    return out;
}

ChordColor color(const ptp_color &c) {
    switch (c.kind) {
    case PTP_JOYSTICK: return ChordColor::joystick(allJoystickModes[c.a], allJoystickDirections[c.b]);
    case PTP_GRID: return ChordColor::grid(allStackHeights[c.a], mode(c.b));
    case PTP_MARKED: {
        ToneMarks marks;
        for (int i = 0; i < 6; ++i) {
            marks.setMove(allChordTones[i], c.moves[i]);
            marks.setSkip(allChordTones[i], (c.skips >> i) & 1);
        }
        return ChordColor::marked(allStackHeights[c.a], mode(c.b), marks);
    }
    case PTP_BUILT: {
        std::set<ChordExtension> extensions;
        for (int i = 0; i < 4; ++i)
            if ((c.b >> i) & 1) extensions.insert(allChordExtensions[i]);
        return ChordColor::built(
            ChordBuild(c.a < 0 ? std::nullopt : std::optional<ChordType>(allChordTypes[c.a]), extensions));
    }
    default: return ChordColor::tones(ChordTones(pitchClasses(c.tones)));
    }
}

ChordSpec spec(int degree, const ptp_color *c) { return {allDegrees[degree], color(*c)}; }

void write(const std::string &text, char *out, int capacity) {
    const size_t n = std::min(text.size(), static_cast<size_t>(capacity - 1));
    std::memcpy(out, text.data(), n);
    out[n] = '\0';
}

} // namespace

int ptp_voicing(int root, int scale, int degree, const ptp_color *c, int inversion, int octave, int voiceLeading,
                const int *previous, int previousCount, int *notes) {
    std::optional<Voicing> prior;
    if (previous) prior = Voicing(std::vector<int>(previous, previous + previousCount));
    const Voicing v = computeVoicing(key(root, scale), spec(degree, c), Inversion{inversion}, octave,
                                     voiceLeading != 0, prior);
    std::copy(v.notes().begin(), v.notes().end(), notes);
    return static_cast<int>(v.notes().size());
}

void ptp_chord_label(int root, int scale, int degree, const ptp_color *c, char *out, int capacity) {
    write(chordLabel(key(root, scale), spec(degree, c)), out, capacity);
}

void ptp_color_action_label(const ptp_color *c, char *out, int capacity) {
    write(colorActionLabel(color(*c)), out, capacity);
}

void ptp_degree_numeral(int root, int scale, int degree, char *out, int capacity) {
    write(degreeNumeral(key(root, scale), allDegrees[degree]), out, capacity);
}

int ptp_chord_tones(int toneMask, char *name, int nameCapacity, int *slashRoot, char *slashQuality,
                    int qualityCapacity) {
    const ChordTones tones(pitchClasses(toneMask));
    write(tones.name(), name, nameCapacity);
    const auto slash = tones.slash();
    if (!slash) return 0;
    *slashRoot = slash->root;
    write(slash->quality, slashQuality, qualityCapacity);
    return 1;
}

int ptp_step(int root, int scale, int degree, int toneMask, int ranking, int kind, int rank, int *madeMask,
             int *from, int *to, int *fit, char *editName, int capacity) {
    const auto step = StepCompass::step(CompassPlace(allColorStepKinds[kind], rank),
                                        ChordTones(pitchClasses(toneMask)), key(root, scale), allDegrees[degree],
                                        ranking == 0 ? ColorStepRanking::theory : ColorStepRanking::common);
    if (!step) return 0;
    *madeMask = mask(step->tones.pitchClasses());
    *from = step->from.value_or(-1);
    *to = step->to.value_or(-1);
    *fit = static_cast<int>(step->fit);
    write(step->editName(), editName, capacity);
    return 1;
}

int ptp_walk(int root, int scale, int degree, int ranking, const int *places, int count) {
    std::vector<CompassPlace> walk;
    for (int i = 0; i < count; ++i) walk.emplace_back(allColorStepKinds[places[i] / 2], places[i] % 2 + 1);
    return mask(StepCompass::walk(walk, key(root, scale), allDegrees[degree],
                                  ranking == 0 ? ColorStepRanking::theory : ColorStepRanking::common)
                    .pitchClasses());
}

void ptp_key_degree(int root, int scale, int note, int *keyRoot, int *keyScale, int *degree) {
    const KeyDegree kd = KeyDegree::onRoot(pitchClass(note), key(root, scale));
    *keyRoot = raw(kd.key.root);
    *keyScale = static_cast<int>(std::find(allScaleTypes.begin(), allScaleTypes.end(), kd.key.scale) -
                                 allScaleTypes.begin());
    *degree = index(kd.degree);
}

int ptp_color_steps(const int *a, int aCount, const int *b, int bCount) {
    return colorSteps(std::vector<int>(a, a + aCount), std::vector<int>(b, b + bCount));
}

int ptp_grid_rows(int root, int scale, int degree, int *modes) {
    const auto rows = ChordGrid::rows(key(root, scale), allDegrees[degree]);
    for (size_t i = 0; i < rows.size(); ++i) modes[i] = static_cast<int>(rows[i]);
    return static_cast<int>(rows.size());
}

int ptp_ring_turn(int arrangement, int root, int scale, int degree) {
    return ColorRing::turn(arrangement == 0 ? ColorRingArrangement::fixed : ColorRingArrangement::home,
                           key(root, scale), allDegrees[degree]);
}

int ptp_chord_wire(int root, int scale, int degree, int mode, int direction, int inversion, int octave,
                   int voiceLeading, const int *notes, int count, int bass, uint8_t *out) {
    const ChordAnnouncement announcement{
        key(root, scale),
        allDegrees[degree],
        allJoystickModes[mode],
        allJoystickDirections[direction],
        Inversion{inversion},
        octave,
        voiceLeading != 0,
        Voicing(std::vector<int>(notes, notes + count), bass < 0 ? std::nullopt : std::optional<int>(bass)),
    };
    const auto bytes = ChordWire::encodeChord(announcement);
    std::copy(bytes.begin(), bytes.end(), out);
    return static_cast<int>(bytes.size());
}

int ptp_stated(int inversion, int octave, int root, int scale, int degree, const ptp_color *c,
               int *statedInversion, int *statedOctave) {
    const auto stated = ChordWire::stated(Inversion{inversion}, octave, key(root, scale), spec(degree, c));
    if (!stated) return 0;
    *statedInversion = stated->inversion.steps;
    *statedOctave = stated->octave;
    return 1;
}

void ptp_midi_key_signature(int root, int scale, int *sharps, int *isMinor) {
    const MidiKeySignature signature = midiKeySignature(key(root, scale));
    *sharps = signature.sharps;
    *isMinor = signature.isMinor ? 1 : 0;
}
