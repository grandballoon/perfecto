// Ported from Tests/MusicTheoryCoreTests/StepCompassTests.swift.

#include <doctest.h>

#include "perfecto/theory/color_steps.hpp"
#include "perfecto/theory/naming.hpp"
#include "perfecto/theory/step_compass.hpp"
#include "perfecto/theory/voicing.hpp"

#include <algorithm>
#include <optional>
#include <string>
#include <vector>

using namespace perfecto::theory;

namespace {

const Key cMajor{PitchClass::C, ScaleType::major};
const Key cMinor{PitchClass::C, ScaleType::naturalMinor};

std::string label(const ChordTones &tones, Degree degree, const Key &key = cMajor) {
    return chordLabel(key, ChordSpec{degree, ChordColor::tones(tones)});
}

std::optional<std::string> place(const CompassPlace &place, Degree degree,
                                 const std::optional<ChordTones> &tones = std::nullopt,
                                 ColorStepRanking ranking = ColorStepRanking::theory,
                                 const Key &key = cMajor) {
    const ChordTones from = tones ? *tones : StepCompass::base(key, degree);
    const auto step = StepCompass::step(place, from, key, degree, ranking);
    if (!step) return std::nullopt;
    return label(step->tones, degree, key);
}

using Opt = std::optional<std::string>;

} // namespace

TEST_SUITE("StepCompass") {

// MARK: – Tones and their names

TEST_CASE("tones are read from any color") {
    CHECK(chordTones(cMajor, ChordSpec{Degree::V, ChordColor::grid(StackHeight::seventh)}) == ChordTones({0, 4, 7, 10}));
    CHECK(chordTones(cMajor, ChordSpec{Degree::ii, ChordColor::grid(StackHeight::ninth)}) == ChordTones({0, 3, 7, 10, 2}));
    CHECK(chordTones(cMajor, ChordSpec{Degree::I, ChordColor::base()}) == StepCompass::base(cMajor, Degree::I));
}

TEST_CASE("tones are named as the app names chords") {
    CHECK(ChordTones({0, 4, 7}).name() == "maj");
    CHECK(ChordTones({0, 3, 7, 10}).name() == "min7");
    CHECK(ChordTones({0, 4, 7, 10, 2}).name() == "9");
    CHECK(ChordTones({0, 4, 7, 9, 2}).name() == "6/9");
    CHECK(ChordTones({0, 5, 7}).name() == "sus4");
    CHECK(ChordTones({0, 5, 7, 10}).name() == "7sus4");
    CHECK(ChordTones({0, 4, 7, 2}).name() == "add9");
    CHECK(ChordTones({0, 3, 7, 2}).name() == "min add9");
    CHECK(ChordTones({0, 4, 7, 10, 1}).name() == "7♭9");
    CHECK(ChordTones({0, 3, 6, 10}).name() == "min7♭5");
    CHECK(ChordTones({0, 3, 6, 9}).name() == "dim7");
    CHECK(ChordTones({0, 4, 8}).name() == "aug");
    CHECK(ChordTones({0, 7}).name() == "5");
    CHECK(ChordTones({0, 4}).name() == "maj(no5)");
    CHECK(ChordTones({0, 4, 7, 11, 9}).name() == "maj7(13)");
}

/// Every tone in the octave above the root, a tension above the chord
/// an octave higher, so it stays on top of an inversion.
TEST_CASE("tensions are voiced an octave up") {
    using V = std::vector<int>;
    CHECK(ChordTones({0, 4, 7, 10, 2}).intervals() == V{0, 4, 7, 10, 14});
    CHECK(ChordTones({0, 2, 7}).intervals() == V{0, 2, 7});                  // sus2: the 2nd is the 3rd's place
    CHECK(ChordTones({0, 4, 7, 5}).intervals() == V{0, 4, 7, 17});           // add11
    CHECK(ChordTones({0, 4, 7, 10, 9}).intervals() == V{0, 4, 7, 10, 21});   // 13 over a 7th
    CHECK(ChordTones({0, 4, 7, 9}).intervals() == V{0, 4, 7, 9});            // 6 over none
}

TEST_CASE("another chord over the root is named over its bass") {
    CHECK(label(ChordTones({0, 3, 8}), Degree::iii) == "C/E");
    CHECK(label(ChordTones({0, 3, 6, 8}), Degree::viiDim) == "G 7/B");
    CHECK(label(ChordTones({0, 3, 7, 10}), Degree::ii) == "D min7");
}

TEST_CASE("a tone color sounds its tones") {
    const Voicing voicing = computeVoicing(
        cMajor, ChordSpec{Degree::V, ChordColor::tones(ChordTones({0, 4, 7, 10, 2}))},
        Inversion::root(), 4, false, std::nullopt);
    CHECK(voicing.notes() == std::vector<int>{67, 71, 74, 77, 81});   // G9
}

// MARK: – The places

/// V in C major, by theory: up adds its own next tones (the 7th, then
/// the 9th), right raises the 3rd to sus4 then the 5th (borrowed), left
/// lowers (both borrowed, the 3rd first), down takes the 5th then the 3rd.
TEST_CASE("the dominant's places") {
    CHECK(place(CompassPlace(ColorStepKind::add, 1), Degree::V) == Opt("G 7"));
    CHECK(place(CompassPlace(ColorStepKind::add, 2), Degree::V) == Opt("G add9"));
    CHECK(place(CompassPlace(ColorStepKind::raise, 1), Degree::V) == Opt("G sus4"));
    CHECK(place(CompassPlace(ColorStepKind::raise, 2), Degree::V) == Opt("G aug"));
    CHECK(place(CompassPlace(ColorStepKind::lower, 1), Degree::V) == Opt("G min"));
    CHECK(place(CompassPlace(ColorStepKind::lower, 2), Degree::V) == Opt("G maj(♭5)"));
    CHECK(place(CompassPlace(ColorStepKind::takeAway, 1), Degree::V) == Opt("G maj(no5)"));
    CHECK(place(CompassPlace(ColorStepKind::takeAway, 2), Degree::V) == Opt("G 5"));
}

/// The same place is each degree's own: up is its diatonic 7th.
TEST_CASE("up adds each degree's own seventh") {
    std::vector<Opt> sevenths;
    for (Degree degree : allDegrees) sevenths.push_back(place(CompassPlace(ColorStepKind::add, 1), degree));
    CHECK(sevenths == std::vector<Opt>{"C maj7", "D min7", "E min7", "F maj7", "G 7", "A min7", "B min7♭5"});
}

TEST_CASE("a step is fitted to the key") {
    const auto steps = StepCompass::steps(StepCompass::base(cMajor, Degree::I), cMajor, Degree::I,
                                          ColorStepRanking::theory);
    const auto &adds = steps.at(ColorStepKind::add);
    const auto &raises = steps.at(ColorStepKind::raise);
    const auto add11 = *std::find_if(adds.begin(), adds.end(), [](const ColorStep &s) { return s.to == 5; });
    const auto addFlat7 = *std::find_if(adds.begin(), adds.end(), [](const ColorStep &s) { return s.to == 10; });
    CHECK(add11.fit == ColorFit::avoid);        // F a semitone over E
    CHECK(addFlat7.fit == ColorFit::borrowed);  // B♭ is not in C major
    CHECK(raises.front().fit == ColorFit::inKey);   // sus4
    CHECK((add11.editName() == "+4" && raises.front().editName() == "3→4"));
}

/// Each kind's choices are its in-key ones first, so a place filled
/// from outside the key is one that has nothing in it.
TEST_CASE("in key comes first by theory") {
    for (Degree degree : allDegrees) {
        const auto steps = StepCompass::steps(StepCompass::base(cMajor, degree), cMajor, degree,
                                              ColorStepRanking::theory);
        for (const auto &[kind, list] : steps) {
            std::vector<ColorFit> fits;
            for (const ColorStep &step : list) fits.push_back(step.fit);
            CHECK(std::is_sorted(fits.begin(), fits.end()));
        }
    }
}

TEST_CASE("common ranking puts the commonest chord first") {
    CHECK(place(CompassPlace(ColorStepKind::add, 1), Degree::I, std::nullopt, ColorStepRanking::common) == Opt("C 7"));
    CHECK(place(CompassPlace(ColorStepKind::add, 2), Degree::I, std::nullopt, ColorStepRanking::common) == Opt("C maj7"));
    CHECK(place(CompassPlace(ColorStepKind::add, 1), Degree::I, std::nullopt, ColorStepRanking::theory) == Opt("C maj7"));
}

TEST_CASE("a two note chord has nothing to take away") {
    const ChordTones fifth({0, 7});
    CHECK(!StepCompass::step(CompassPlace(ColorStepKind::takeAway, 1), fifth, cMajor, Degree::I,
                             ColorStepRanking::theory).has_value());
}

/// Every step is one step (`colorSteps`) from the chord it is from.
TEST_CASE("every step is one step") {
    for (const Key &key : {cMajor, cMinor}) {
        for (Degree degree : allDegrees) {
            const ChordTones base = StepCompass::base(key, degree);
            for (const auto &[kind, list] : StepCompass::steps(base, key, degree, ColorStepRanking::theory)) {
                for (const ColorStep &step : list) {
                    CHECK(colorSteps(base.pitchClasses(), step.tones.pitchClasses()) == 1);
                }
            }
        }
    }
}

// MARK: – Walks

/// A walk is of places, so it is each degree's own: two adds are the
/// 9th chord on V and on ii.
TEST_CASE("a walk is each degree's own") {
    const std::vector<CompassPlace> twoAdds = {CompassPlace(ColorStepKind::add, 1), CompassPlace(ColorStepKind::add, 1)};
    CHECK(label(StepCompass::walk(twoAdds, cMajor, Degree::V, ColorStepRanking::theory), Degree::V) == "G 9");
    CHECK(label(StepCompass::walk(twoAdds, cMajor, Degree::ii, ColorStepRanking::theory), Degree::ii) == "D min9");
    CHECK(StepCompass::walk({}, cMajor, Degree::I, ColorStepRanking::theory) == ChordTones({0, 4, 7}));
}

TEST_CASE("a minor key's places are its own") {
    CHECK(place(CompassPlace(ColorStepKind::add, 1), Degree::I, std::nullopt, ColorStepRanking::theory, cMinor) == Opt("C min7"));
    CHECK(place(CompassPlace(ColorStepKind::lower, 1), Degree::I, std::nullopt, ColorStepRanking::theory, cMinor) == Opt("C sus2"));
}

}
