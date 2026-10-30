#include "perfecto/desk/music.hpp"

#include "perfecto/desk/arrangement.hpp"
#include "perfecto/desk/ring_pie.hpp"

#include <perfecto/theory/key_degree.hpp>
#include <perfecto/theory/naming.hpp>
#include <perfecto/theory/require.hpp>

#include <algorithm>
#include <cmath>

namespace perfecto::desk {

using namespace theory;

std::string name(LBLayer layer) {
    switch (layer) {
    case LBLayer::compass: return "Compass";
    case LBLayer::voices: return "Voices";
    }
    return {};
}

std::string name(FaceStick stick) {
    switch (stick) {
    case FaceStick::orchid: return "Orchid buttons";
    case FaceStick::perfectoDefault: return "Perfecto · default";
    case FaceStick::perfectoExtended: return "Perfecto · extended";
    case FaceStick::perfectoChromatic: return "Perfecto · chromatic";
    }
    return {};
}

std::string name(DeskOutput output) {
    switch (output) {
    case DeskOutput::synth: return "Synth";
    case DeskOutput::midi: return "MIDI";
    case DeskOutput::both: return "Synth + MIDI";
    }
    return {};
}

// DeskSettings

DeskSettings::DeskSettings()
    : ringArrangement(RingArrangement::home), ringOrder(RingOrder::brightness), ringFilter(RingFilter::all),
      grid(BeatGrid::sixteenth) {}

void DeskSettings::moveRingArrangement(int steps) {
    const int count = static_cast<int>(allRingArrangements.size());
    const int at = static_cast<int>(std::find(allRingArrangements.begin(), allRingArrangements.end(), ringArrangement) -
                                    allRingArrangements.begin());
    ringArrangement = allRingArrangements[static_cast<size_t>(((at + steps) % count + count) % count)];
}

void DeskSettings::moveOctave(int steps) {
    octave = std::min(octaves.upperBound, std::max(octaves.lowerBound, octave + steps));
}

void DeskSettings::roll(int steps) { inversion = Inversion{std::min(6, std::max(-6, inversion.steps + steps))}; }

void DeskSettings::moveKey(int fifths) {
    const int root = ((raw(key.root) + 7 * fifths) % 12 + 12) % 12;
    key = Key{pitchClass(root), key.scale};
}

void DeskSettings::moveScale(int steps) {
    const int count = static_cast<int>(scales.size());
    const auto found = std::find(scales.begin(), scales.end(), key.scale);
    const int at = found == scales.end() ? 0 : static_cast<int>(found - scales.begin());
    const int next = ((at + steps) % count + count) % count;
    key = Key{key.root, scales[static_cast<size_t>(next)]};
}

std::string DeskSettings::summary() const { return theory::name(key.root) + " " + displayName(key.scale); }

std::string DeskSettings::voicingName() const {
    const std::string roll = inversion.steps == 0  ? "root"
                             : inversion.steps > 0 ? "+" + std::to_string(inversion.steps)
                                                   : std::to_string(inversion.steps);
    return "oct " + std::to_string(octave) + " · " + roll;
}

// DeskChord

DeskChord::DeskChord(const Key &key, const ChordSpec &spec, std::optional<std::vector<int>> voicing)
    : key(key), spec(spec), voicing(std::move(voicing)) {}

DeskChord::DeskChord(const Key &key, Degree degree, const ChordColor &color) : DeskChord(key, ChordSpec{degree, color}) {}

DeskChord DeskChord::onRoot(PitchClass root, const ChordTones &tones, const Key &home,
                            std::optional<std::vector<int>> voicing) {
    const KeyDegree chord = KeyDegree::onRoot(root, home);
    return DeskChord(chord.key, ChordSpec{chord.degree, ChordColor::tones(tones)}, std::move(voicing));
}

PitchClass DeskChord::root() const { return chordRootPitchClass(key, spec.degree); }

ChordTones DeskChord::tones() const { return chordTones(key, spec); }

std::string DeskChord::name() const {
    const std::string label = chordLabel(key, spec);
    if (!voicing || voicing->empty()) return label;
    const int bass = ((voicing->front() % 12) + 12) % 12;
    if (bass == raw(root()) || label.find('/') != std::string::npos) return label;
    return label + "/" + theory::name(pitchClass(bass));
}

std::vector<int> DeskChord::notes(const DeskSettings &settings, int octaveShift, int roll,
                                  const std::optional<std::vector<int>> &previous) const {
    if (voicing) {
        std::vector<int> moved = *voicing;
        for (int &note : moved) note += 12 * octaveShift;
        return moved;
    }
    std::optional<Voicing> last;
    if (previous) last = Voicing(*previous);
    return computeVoicing(key, spec, settings.inversion.rolled(roll), settings.octave + octaveShift,
                          settings.voiceLeading, last)
        .notes();
}

ChordFit DeskChord::fit(const Key &home) const {
    const int rootClass = raw(root());
    std::vector<int> pitches;
    const ChordTones tones = this->tones();
    for (int tone : tones.pitchClasses()) pitches.push_back((tone + rootClass) % 12);
    if (!std::all_of(pitches.begin(), pitches.end(), [&](int p) { return home.has(p); })) return ChordFit::borrowed;
    // A tone a semitone over another is the clash jazz calls an avoid note.
    const bool clashes = std::any_of(pitches.begin(), pitches.end(), [&](int p) {
        return std::any_of(pitches.begin(), pitches.end(), [&](int q) { return (q + 1) % 12 == p; }) && p != rootClass;
    });
    return clashes ? ChordFit::tense : ChordFit::inKey;
}

// ArpeggioRate

double beats(ArpeggioRate rate) {
    switch (rate) {
    case ArpeggioRate::quarter: return 1;
    case ArpeggioRate::eighth: return 0.5;
    case ArpeggioRate::sixteenth: return 0.25;
    }
    return 1;
}

std::string name(ArpeggioRate rate) {
    switch (rate) {
    case ArpeggioRate::quarter: return "♩";
    case ArpeggioRate::eighth: return "♪";
    case ArpeggioRate::sixteenth: return "♬";
    }
    return {};
}

// ChordLine

std::optional<int> ChordLine::arpeggioNote() const {
    if (!arpeggio_ || !isSounding_ || notes_.empty() || arpeggioStep_ < 0) return std::nullopt;
    return notes_[static_cast<size_t>(arpeggioStep_) % notes_.size()];
}

std::vector<DeskEffect> ChordLine::strike(const DeskChord &chord, double level, double brightness,
                                          const DeskSettings &settings, double time) {
    chord_ = chord;
    level_ = level;
    brightness_ = brightness;
    notes_ = chord.notes(settings, octaveShift_, roll_,
                         isSounding_ ? std::optional<std::vector<int>>(notes_) : std::nullopt);
    isSounding_ = true;
    arpeggioStart_ = time;
    arpeggioStep_ = -1;
    if (!arpeggio_) return {sound(notes_, settings, false)};
    return advance(settings, time);
}

std::vector<DeskEffect> ChordLine::change(const DeskChord &chord, const DeskSettings &settings) {
    if (chord_ == chord) return {};
    chord_ = chord;
    return revoice(settings);
}

std::vector<DeskEffect> ChordLine::revoice(const DeskSettings &settings) {
    if (!isSounding_ || !chord_) return {};
    std::vector<int> next = chord_->notes(settings, octaveShift_, roll_, notes_);
    if (next == notes_) return {};
    notes_ = std::move(next);
    if (arpeggio_) return {};
    return {sound(notes_, settings, true)};
}

std::vector<DeskEffect> ChordLine::bend(int octaves, int roll, const DeskSettings &settings) {
    if (octaves == octaveShift_ && roll == roll_) return {};
    octaveShift_ = octaves;
    roll_ = roll;
    return revoice(settings);
}

std::vector<DeskEffect> ChordLine::shape(double level, double brightness) {
    if (!(std::fabs(level - level_) > 0.01 || std::fabs(brightness - brightness_) > 0.01)) return {};
    level_ = level;
    brightness_ = brightness;
    if (!isSounding_) return {};
    return {DeskEffect::shape(line, level, brightness, 0)};
}

std::vector<DeskEffect> ChordLine::release() {
    if (!isSounding_) return {};
    isSounding_ = false;
    arpeggioStep_ = -1;
    return {DeskEffect::silence(line)};
}

std::vector<DeskEffect> ChordLine::arpeggiate(std::optional<ArpeggioRate> rate, const DeskSettings &settings,
                                              double time) {
    if (rate == arpeggio_) return {};
    const bool wasOn = arpeggio_.has_value();
    arpeggio_ = rate;
    if (!isSounding_) return {};
    if (!rate) return {sound(notes_, settings, false)};
    if (!wasOn) {
        arpeggioStart_ = time;
        arpeggioStep_ = -1;
    } else {
        // A new rate carries on from the note sounding.
        arpeggioStart_ = time - static_cast<double>(arpeggioStep_) * 60 / settings.tempo * beats(*rate);
    }
    return advance(settings, time);
}

std::vector<DeskEffect> ChordLine::advance(const DeskSettings &settings, double time) {
    if (!arpeggio_ || !isSounding_ || notes_.empty()) return {};
    const int step =
        static_cast<int>(std::floor((time - arpeggioStart_) / (60 / settings.tempo * beats(*arpeggio_))));
    if (step == arpeggioStep_) return {};
    arpeggioStep_ = std::max(0, step);
    return {sound({notes_[static_cast<size_t>(arpeggioStep_) % notes_.size()]}, settings, false)};
}

DeskEffect ChordLine::sound(const std::vector<int> &notes, const DeskSettings &settings, bool tie) const {
    return DeskEffect::sound(line, notes, line == Line::chord ? settings.chordSound : settings.lineSound, level_,
                             brightness_, tie);
}

// DiatonicCycle, DegreePie

namespace DiatonicCycle {

Degree degree(int steps, Degree from) {
    const auto found = std::find(thirds.begin(), thirds.end(), from);
    PERFECTO_REQUIRE(found != thirds.end(), "every degree is on the cycle");
    const int at = static_cast<int>(found - thirds.begin());
    return thirds[static_cast<size_t>(((at + steps) % 7 + 7) % 7)];
}

} // namespace DiatonicCycle

namespace DegreePie {

const PieGate &gate() {
    static const PieGate pie = PieGate::even(7);
    return pie;
}

int sector(Degree degree) {
    return static_cast<int>(std::find(order.begin(), order.end(), degree) - order.begin());
}

} // namespace DegreePie

} // namespace perfecto::desk
