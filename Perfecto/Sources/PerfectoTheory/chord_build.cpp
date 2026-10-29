#include "perfecto/theory/chord_build.hpp"

#include <algorithm>
#include <vector>

namespace perfecto::theory {

namespace {

/// The triad under the extensions.
enum class Triad { diminished, minor, major, suspended };

std::vector<int> intervals(Triad t) {
    switch (t) {
    case Triad::diminished: return {0, 3, 6};
    case Triad::minor: return {0, 3, 7};
    case Triad::major: return {0, 4, 7};
    case Triad::suspended: return {0, 5, 7};
    }
    return {};
}

std::string name(Triad t) {
    switch (t) {
    case Triad::diminished: return "dim";
    case Triad::minor: return "min";
    case Triad::major: return "maj";
    case Triad::suspended: return "sus4";
    }
    return "";
}

/// With a sixth and no seventh.
std::string sixthName(Triad t) {
    switch (t) {
    case Triad::diminished: return "dim7";
    case Triad::minor: return "min6";
    case Triad::major: return "6";
    case Triad::suspended: return "6sus4";
    }
    return "";
}

/// With the major seventh, or the minor one.
std::string seventhName(Triad t, bool major) {
    switch (t) {
    case Triad::diminished: return major ? "dim(maj7)" : "min7♭5";
    case Triad::minor: return major ? "min(maj7)" : "min7";
    case Triad::major: return major ? "maj7" : "7";
    case Triad::suspended: return major ? "maj7sus4" : "7sus4";
    }
    return "";
}

/// "maj9", "min6/9", "7sus4(13)": the chord's quality as the app names the
/// joystick's.
std::string chordName(Triad triad, bool sixth, std::optional<int> seventh, bool ninth) {
    if (!seventh) {
        if (!sixth && !ninth) return name(triad);
        if (!sixth && ninth) return triad == Triad::major ? "add9" : name(triad) + " add9";
        if (sixth && !ninth) return sixthName(triad);
        return triad == Triad::diminished ? "dim7 add9" : sixthName(triad) + "/9";
    }
    std::string out = seventhName(triad, *seventh == 11);
    // A ninth over a seventh names the chord by its ninth.
    if (ninth) {
        const auto i = out.find('7');
        if (i != std::string::npos) out[i] = '9';
    }
    if (sixth) out += "(13)";
    return out;
}

} // namespace

std::string mark(ChordType t) {
    switch (t) {
    case ChordType::note: return "Note";
    case ChordType::diminished: return "Dim";
    case ChordType::minor: return "Min";
    case ChordType::major: return "Maj";
    case ChordType::suspended: return "Sus";
    }
    return "";
}

std::string mark(ChordExtension e) {
    switch (e) {
    case ChordExtension::sixth: return "6";
    case ChordExtension::minorSeventh: return "m7";
    case ChordExtension::majorSeventh: return "M7";
    case ChordExtension::ninth: return "9";
    }
    return "";
}

ChordBuild::ChordBuild(std::optional<ChordType> type, std::set<ChordExtension> extensions)
    : type_(type), extensions_(type == ChordType::note ? std::set<ChordExtension>{} : std::move(extensions)) {}

std::string ChordBuild::legend() const {
    std::vector<std::string> parts;
    if (type_) parts.push_back(mark(*type_));
    std::string added;
    for (ChordExtension e : allChordExtensions)
        if (extensions_.count(e)) added += (added.empty() ? "" : " ") + mark(e);
    if (!added.empty()) parts.push_back(added);
    if (parts.empty()) return "Base";
    std::string out;
    for (std::size_t i = 0; i < parts.size(); ++i) out += (i ? " · " : "") + parts[i];
    return out;
}

ChordShape ChordBuild::shape(TriadBase base) const {
    Triad triad;
    if (type_) {
        switch (*type_) {
        // A note is its root, and its name is its root's.
        case ChordType::note: return {{0}, ""};
        case ChordType::diminished: triad = Triad::diminished; break;
        case ChordType::minor: triad = Triad::minor; break;
        case ChordType::major: triad = Triad::major; break;
        case ChordType::suspended: triad = Triad::suspended; break;
        }
    } else {
        triad = base == TriadBase::major ? Triad::major : base == TriadBase::minor ? Triad::minor : Triad::diminished;
    }
    const std::optional<int> seventh = extensions_.count(ChordExtension::majorSeventh)   ? std::optional(11)
                                       : extensions_.count(ChordExtension::minorSeventh) ? std::optional(10)
                                                                                         : std::nullopt;
    const bool sixth = extensions_.count(ChordExtension::sixth) > 0;
    const bool ninth = extensions_.count(ChordExtension::ninth) > 0;

    std::vector<int> notes = intervals(triad);
    if (sixth) notes.push_back(seventh ? 21 : 9);
    if (seventh) notes.push_back(*seventh);
    if (ninth) notes.push_back(14);
    std::sort(notes.begin(), notes.end());
    return {notes, chordName(triad, sixth, seventh, ninth)};
}

} // namespace perfecto::theory
