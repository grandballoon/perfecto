#include "perfecto/theory/naming.hpp"

#include "perfecto/theory/grid.hpp"

#include <cctype>

namespace perfecto::theory {

TriadBase triadBase(const Key &key, Degree degree) {
    const ScaleType scale = key.scale;
    const int root = offset(scale, degree);
    const int thirdInterval = semitones(scale, index(degree) + 2) - root;
    const int fifthInterval = semitones(scale, index(degree) + 4) - root;

    const bool isMinor = thirdInterval < 4;               // minor or augmented-4th third
    const bool isDim = isMinor && fifthInterval < 7;       // flat fifth confirms diminished
    return isDim ? TriadBase::dim : isMinor ? TriadBase::minor : TriadBase::major;
}

PitchClass chordRootPitchClass(const Key &key, Degree degree) {
    return pitchClass(raw(key.root) + offset(key.scale, degree));
}

std::string degreeNumeral(const Key &key, Degree degree) {
    static const char *numerals[] = {"I", "II", "III", "IV", "V", "VI", "VII"};
    std::string numeral = numerals[index(degree)];
    const TriadBase base = triadBase(key, degree);
    if (base == TriadBase::major) return numeral;
    for (char &c : numeral) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return base == TriadBase::dim ? numeral + "°" : numeral;
}

ChordShape chordShape(const Key &key, const ChordSpec &spec) {
    const TriadBase base = triadBase(key, spec.degree);
    const auto &color = spec.color.value();
    if (const auto *j = std::get_if<ChordColor::Joystick>(&color))
        return joystickOutcome(j->mode, j->direction).shape(base);
    if (const auto *g = std::get_if<ChordColor::Grid>(&color)) {
        const HeptatonicMode mode = g->mode.value_or(ChordGrid::ownMode(key, spec.degree));
        return {stackThirds(intervals(mode), g->height), tertianChordName(mode, g->height)};
    }
    if (const auto *m = std::get_if<ChordColor::Marked>(&color)) {
        const HeptatonicMode mode = m->mode.value_or(ChordGrid::ownMode(key, spec.degree));
        return {markedStack(intervals(mode), m->height, m->marks), markedChordName(mode, m->height, m->marks)};
    }
    if (const auto *b = std::get_if<ChordColor::Built>(&color)) return b->shape(base);
    const auto &tones = std::get<ChordColor::Tones>(color);
    return {tones.intervals(), tones.name()};
}

std::string chordQualityName(const Key &key, const ChordSpec &spec) { return chordShape(key, spec).name; }

std::string chordLabel(const Key &key, const ChordSpec &spec) {
    const PitchClass root = chordRootPitchClass(key, spec.degree);
    if (const auto *tones = std::get_if<ChordColor::Tones>(&spec.color.value())) {
        if (const auto slash = tones->slash()) {
            const PitchClass other = pitchClass(raw(root) + slash->root);
            return name(other) + (slash->quality.empty() ? "" : " " + slash->quality) + "/" + name(root);
        }
    }
    const std::string quality = chordQualityName(key, spec);
    return quality.empty() ? name(root) : name(root) + " " + quality;
}

std::string colorActionLabel(const ChordColor &color) {
    const auto &value = color.value();
    if (const auto *j = std::get_if<ChordColor::Joystick>(&value)) return joystickActionLabel(j->mode, j->direction);
    if (const auto *g = std::get_if<ChordColor::Grid>(&value)) {
        if (!g->mode) return displayName(g->height);
        return displayName(g->height) + " · " + displayName(*g->mode);
    }
    if (const auto *m = std::get_if<ChordColor::Marked>(&value))
        return colorActionLabel(ChordColor::grid(m->height, m->mode)) + " · marked";
    if (const auto *b = std::get_if<ChordColor::Built>(&value)) return b->legend();
    return std::get<ChordColor::Tones>(value).name();
}

std::string joystickActionLabel(JoystickMode mode, JoystickDirection direction) {
    return joystickOutcome(mode, direction).action;
}

} // namespace perfecto::theory
