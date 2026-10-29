// Ported from Tests/MusicTheoryCoreTests/ToneMarksTests.swift.

#include <doctest.h>

#include "perfecto/theory/chord_color.hpp"
#include "perfecto/theory/naming.hpp"
#include "perfecto/theory/tone_marks.hpp"
#include "perfecto/theory/voicing.hpp"

#include <algorithm>
#include <optional>
#include <set>
#include <string>
#include <utility>
#include <vector>

using namespace perfecto::theory;

namespace {

using V = std::vector<int>;
using Strings = std::vector<std::string>;

const Key cMajor{PitchClass::C, ScaleType::major};
const V dorian = intervals(HeptatonicMode::dorian);
const V ionian = intervals(HeptatonicMode::ionian);
const V mixolydian = intervals(HeptatonicMode::mixolydian);
const V lydian = intervals(HeptatonicMode::lydian);

ToneMarks marks(const std::vector<std::pair<ChordTone, int>> &moves = {}, const std::vector<ChordTone> &skips = {}) {
    ToneMarks marks;
    for (const auto &[tone, offset] : moves) marks.toggleMove(tone, offset);
    for (ChordTone tone : skips) marks.toggleSkip(tone);
    return marks;
}

using enum ChordTone;

} // namespace

TEST_SUITE("ToneMarks") {

// MARK: – No marks

TEST_CASE("no marks is the stack itself") {
    for (HeptatonicMode mode : allHeptatonicModes) {
        for (StackHeight height : allStackHeights) {
            CHECK(markedStack(intervals(mode), height, ToneMarks{}) == stackThirds(intervals(mode), height));
            CHECK(markedChordName(mode, height, ToneMarks{}) == tertianChordName(mode, height));
        }
    }
}

TEST_CASE("no marks is the grid color") {
    CHECK(ChordColor::tertian(StackHeight::seventh, HeptatonicMode::mixolydian, ToneMarks{}) ==
          ChordColor::grid(StackHeight::seventh, HeptatonicMode::mixolydian));
    CHECK(ChordColor::tertian(StackHeight::seventh, HeptatonicMode::mixolydian, marks({{fifth, 1}})) ==
          ChordColor::marked(StackHeight::seventh, HeptatonicMode::mixolydian, marks({{fifth, 1}})));
}

// MARK: – The joystick's colors, by marks

TEST_CASE("sus chords move the third") {
    CHECK(markedStack(ionian, StackHeight::triad, marks({{third, 1}})) == V{0, 5, 7});     // sus4
    CHECK(markedStack(dorian, StackHeight::triad, marks({{third, -1}})) == V{0, 2, 7});    // sus2
    CHECK(markedStack(mixolydian, StackHeight::seventh, marks({{third, 1}})) == V{0, 5, 7, 10}); // 7sus4
}

TEST_CASE("add chords leave out the seventh") {
    CHECK(markedStack(ionian, StackHeight::ninth, marks({}, {seventh})) == V{0, 4, 7, 14});  // add9
    CHECK(markedStack(ionian, StackHeight::ninth, marks({{seventh, -1}})) == V{0, 4, 7, 10, 14});       // maj9 with ♭7: 9
}

TEST_CASE("altered dominants") {
    CHECK(markedStack(mixolydian, StackHeight::ninth, marks({{ninth, -1}})) == V{0, 4, 7, 10, 13});          // 7♭9
    CHECK(markedStack(mixolydian, StackHeight::ninth, marks({{ninth, 1}})) == V{0, 4, 7, 10, 15});           // 7♯9
    CHECK(markedStack(mixolydian, StackHeight::ninth, marks({{fifth, 1}, {ninth, 1}})) == V{0, 4, 8, 10, 15}); // 7alt
    CHECK(markedStack(ionian, StackHeight::triad, marks({{fifth, 1}})) == V{0, 4, 8});                       // aug
    CHECK(markedStack(dorian, StackHeight::seventh, marks({{seventh, 1}})) == V{0, 3, 7, 11});               // m(maj7)
}

TEST_CASE("sixths lower the seventh") {
    CHECK(markedStack(mixolydian, StackHeight::seventh, marks({{seventh, -1}})) == V{0, 4, 7, 9});       // 6
    CHECK(markedStack(mixolydian, StackHeight::ninth, marks({{seventh, -1}})) == V{0, 4, 7, 9, 14});     // 6/9
}

TEST_CASE("a dropped tone is brought back") {
    CHECK(droppedTones(ionian, StackHeight::eleventh) == std::set<ChordTone>{third});
    CHECK(droppedTones(ionian, StackHeight::thirteenth) == std::set<ChordTone>{eleventh});
    CHECK(droppedTones(dorian, StackHeight::eleventh).empty());
    const ToneMarks add11 = marks({}, {third, seventh, ninth});
    CHECK(markedStack(ionian, StackHeight::eleventh, add11) == V{0, 4, 7, 17});
    CHECK(markNames(ionian, StackHeight::eleventh, add11) == Strings{"add 3", "no 7", "no 9"});
    CHECK(markedStack(lydian, StackHeight::eleventh, marks({}, {ninth})) == V{0, 4, 7, 11, 18});       // maj7♯11
}

// MARK: – Moves that cannot be made

TEST_CASE("a move onto another tone is not made") {
    // Ionian's 7th raised would be the root; Lydian's 11th raised its 5th.
    CHECK(markedStack(ionian, StackHeight::seventh, marks({{seventh, 1}})) == V{0, 4, 7, 11});
    CHECK(markedStack(lydian, StackHeight::eleventh, marks({{eleventh, 1}})) == V{0, 4, 7, 11, 14, 18});
    // Dorian's 3rd raised frees its pitch class for the 9th raised: tones
    // move from the 3rd up, so both moves are made.
    const ToneMarks both = marks({{third, 1}, {ninth, 1}});
    CHECK(markedStack(dorian, StackHeight::ninth, both) == V{0, 4, 7, 10, 15});
}

TEST_CASE("a mark twice takes it off") {
    ToneMarks marks;
    marks.toggleMove(fifth, 1);
    marks.toggleMove(fifth, 1);
    CHECK(marks.isEmpty());
    marks.toggleMove(fifth, 1);
    marks.toggleMove(fifth, -1);
    CHECK(marks.move(fifth) == -1);
    marks.toggleSkip(ninth);
    marks.toggleSkip(ninth);
    CHECK((marks.move(fifth) == -1 && !marks.skips(ninth)));
}

TEST_CASE("a mark set is whatever it is set to") {
    ToneMarks marks;
    marks.setMove(ninth, 1);
    marks.setMove(ninth, -1);
    CHECK(marks.move(ninth) == -1);
    marks.setMove(ninth, 0);
    marks.setSkip(seventh, true);
    marks.setSkip(seventh, true);
    CHECK(marks.skips(seventh));
    marks.setSkip(seventh, false);
    CHECK(marks.isEmpty());
}

// MARK: – Names

TEST_CASE("names add the marks in brackets") {
    CHECK(markedChordName(HeptatonicMode::mixolydian, StackHeight::ninth, marks({{fifth, 1}, {ninth, 1}})) == "9(♯5, ♯9)");
    CHECK(markedChordName(HeptatonicMode::ionian, StackHeight::triad, marks({{third, 1}})) == "maj(sus4)");
    CHECK(markedChordName(HeptatonicMode::mixolydian, StackHeight::seventh, marks({{seventh, -1}})) == "7(6)");
    CHECK(chordLabel(cMajor, ChordSpec{Degree::V, ChordColor::marked(StackHeight::ninth, std::nullopt, marks({{ninth, -1}}))}) == "G 9(♭9)");
}

TEST_CASE("the marked color plays its notes") {
    const ChordSpec spec{Degree::V, ChordColor::marked(StackHeight::ninth, std::nullopt, marks({{fifth, 1}, {ninth, 1}}))};
    CHECK(computeVoicing(cMajor, spec, Inversion::root(), 4, false, std::nullopt).notes() == V{67, 71, 75, 77, 82});
}

// MARK: – Options

TEST_CASE("options say what each tone can do") {
    using Opt = std::optional<std::string>;
    const auto options = toneMarkOptions(ionian, StackHeight::seventh, ToneMarks{});
    auto optionFor = [](const std::vector<ToneMarkOption> &list, ChordTone tone) {
        return *std::find_if(list.begin(), list.end(), [&](const ToneMarkOption &o) { return o.tone == tone; });
    };
    const auto thirdOption = optionFor(options, third);
    CHECK((thirdOption.up == Opt("sus4") && thirdOption.down == Opt("♭3")));
    const auto seventhOption = optionFor(options, seventh);
    CHECK((seventhOption.up == Opt() && seventhOption.down == Opt("♭7")));
    const auto ninthOption = optionFor(options, ninth);
    CHECK((!ninthOption.isInStack && ninthOption.up == Opt()));

    const auto eleventhOption = optionFor(toneMarkOptions(ionian, StackHeight::eleventh, ToneMarks{}), third);
    CHECK((eleventhOption.isDroppedByStack && eleventhOption.isLeftOut && eleventhOption.up == Opt()));
}

}
