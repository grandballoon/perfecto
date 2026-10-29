#include "perfecto/theory/chord_tones.hpp"

#include <algorithm>
#include <map>
#include <set>

namespace perfecto::theory {

namespace {

bool startsWith(const std::string &s, const std::string &prefix) { return s.rfind(prefix, 0) == 0; }

bool endsWith(const std::string &s, const std::string &suffix) {
    return s.size() >= suffix.size() && s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
}

bool contains(const std::string &s, const std::string &part) { return s.find(part) != std::string::npos; }

/// The string with the first `target` replaced, or as it is.
std::string replacingFirst(const std::string &s, char target, const std::string &replacement) {
    const auto i = s.find(target);
    if (i == std::string::npos) return s;
    return s.substr(0, i) + replacement + s.substr(i + 1);
}

} // namespace

ChordTones::ChordTones(const std::vector<int> &pitchClasses) {
    std::set<int> unique = {0};
    for (int p : pitchClasses) unique.insert((p % 12 + 12) % 12);
    pitchClasses_.assign(unique.begin(), unique.end());
}

bool ChordTones::has(int pitchClass) const {
    return std::binary_search(pitchClasses_.begin(), pitchClasses_.end(), pitchClass);
}

std::vector<int> ChordTones::intervals() const {
    const bool third = has(3) || has(4), seventh = has(10) || has(11);
    std::vector<int> out;
    for (int p : pitchClasses_) {
        const bool isTension = ((p == 1 || p == 2) && third) || (p == 3 && has(4)) || (p == 5 && third) ||
                               (p == 6 && has(7)) || (p == 8 && has(7) && seventh) || (p == 9 && seventh);
        out.push_back(isTension ? p + 12 : p);
    }
    std::sort(out.begin(), out.end());
    return out;
}

std::string ChordTones::name() const {
    std::set<int> used = {0};
    const std::optional<int> third = has(4) ? std::optional(4) : has(3) ? std::optional(3) : std::nullopt;
    if (third) used.insert(*third);
    std::optional<std::string> sus;
    if (!third) {
        if (has(5)) {
            sus = "sus4";
            used.insert(5);
        } else if (has(2)) {
            sus = "sus2";
            used.insert(2);
        }
    }
    std::optional<int> fifth;
    if (has(7)) fifth = 7;
    else if (has(6) && third != 4) fifth = 6;
    else if (has(8) && third == 4) fifth = 8;
    else if (has(6) && third == 4 && !has(10) && !has(11)) fifth = 6;
    if (fifth) used.insert(*fifth);
    const bool dim = third == 3 && fifth == 6;
    const std::optional<int> seventh = has(11)             ? std::optional(11)
                                       : has(10)           ? std::optional(10)
                                       : (dim && has(9)) ? std::optional(9)
                                                         : std::nullopt;
    if (seventh) used.insert(*seventh);
    // A chord with both 7ths has the major one as its 7th.
    const bool bothSevenths = has(10) && has(11);
    if (bothSevenths) used.insert(10);
    const bool six = !seventh && has(9);
    if (six) used.insert(9);
    std::vector<int> tensions;
    for (int t : {1, 2, 3, 5, 6, 8, 9})
        if (has(t) && !used.count(t)) tensions.push_back(t);

    std::string name;
    if (dim) {
        if (seventh == 10) name = "min7♭5";
        else if (seventh == 9) name = "dim7";
        else if (seventh == 11) name = "dim(maj7)";
        else name = "dim";
    } else if (third == 4 && fifth == 8 && !seventh) {
        name = "aug";
    } else {
        const std::string minor = third == 3 ? "min" : "";
        if (seventh == 11) name = third == 3 ? "min(maj7)" : "maj7";
        else if (seventh == 10) name = minor + "7";
        else name = six ? minor + "6" : (third == 3 ? "min" : "maj");
        if (fifth == 8) name += "♯5";
    }
    // A natural 9th over a 7th is the 9th chord; over a 6th, the 6/9.
    const auto nine = std::find(tensions.begin(), tensions.end(), 2);
    if (seventh && name != "dim7" && nine != tensions.end()) {
        name = replacingFirst(name, '7', "9");
        tensions.erase(nine);
    }
    if (six) {
        const auto sixNine = std::find(tensions.begin(), tensions.end(), 2);
        if (sixNine != tensions.end()) {
            name += "/9";
            tensions.erase(sixNine);
        }
    }
    if (sus) name = (name == "maj" ? "" : name) + *sus;
    if (!third && !sus && fifth == 7 && pitchClasses_.size() == 2) return "5";

    static const std::map<int, std::string> tensionName = {{1, "♭9"}, {2, "9"},   {3, "♯9"}, {5, "11"},
                                                           {6, "♯11"}, {8, "♭13"}, {9, "13"}};
    // Over no 7th every tension is added; over one, a natural 9th, 11th or
    // 13th is the chord's own number and an altered one joins it.
    std::vector<std::string> marks;
    for (int t : tensions) marks.push_back((seventh ? "" : "add") + tensionName.at(t));
    if (bothSevenths) marks.insert(marks.begin(), "add♭7");
    if (fifth == 6 && !dim) marks.insert(marks.begin(), "♭5");
    if (!fifth && (third || sus)) marks.push_back("no5");
    if (!third && !sus) marks.insert(marks.begin(), "no3");

    // One alteration joins the name (7♭9, add9); a natural tension over a
    // 7th, a tone left out, or more than one go in brackets.
    if (marks.size() == 1) {
        const std::string &mark = marks.front();
        const bool natural = mark == "9" || mark == "11" || mark == "13";
        if (!startsWith(mark, "no") && mark != "♭5" && mark != "add♭7" && !(seventh && natural)) {
            const std::string base = name == "maj" ? "" : name;
            const bool joins = base.empty() || startsWith(mark, "♭") || startsWith(mark, "♯");
            return base + (joins ? "" : " ") + mark;
        }
    }
    if (marks.empty()) return name;
    std::string out = name + "(";
    for (std::size_t i = 0; i < marks.size(); ++i) out += (i ? ", " : "") + marks[i];
    return out + ")";
}

std::optional<ChordTones::Slash> ChordTones::slash() const {
    const std::string own = name();
    if (!(pitchClasses_.size() == 3 || pitchClasses_.size() == 4) ||
        !(contains(own, "(") || endsWith(own, "♯5") || contains(own, "♭13")))
        return std::nullopt;
    static const std::vector<std::pair<std::vector<int>, std::string>> plain = {
        {{0, 4, 7}, ""}, {{0, 3, 7}, "min"}, {{0, 4, 7, 10}, "7"}, {{0, 3, 7, 10}, "min7"}, {{0, 4, 7, 11}, "maj7"},
    };
    for (int root : pitchClasses_) {
        if (root == 0) continue;
        std::vector<int> shifted;
        for (int p : pitchClasses_) shifted.push_back((p - root + 12) % 12);
        std::sort(shifted.begin(), shifted.end());
        for (const auto &[tones, quality] : plain)
            if (tones == shifted) return Slash{root, quality};
    }
    return std::nullopt;
}

} // namespace perfecto::theory
