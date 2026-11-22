// Face Chords as it is held: A the root, RT the chords' second layer, the
// phone's step compass on the left stick with LT its outer places, Key assist,
// and Back the way into the timeline.

#include <doctest.h>

#include "perfecto/desk/face_compass.hpp"
#include "perfecto/desk/scene.hpp"
#include "perfecto/desk/studio.hpp"

#include <perfecto/theory/step_compass.hpp>

#include <cmath>

using namespace perfecto::desk;
using namespace perfecto::theory;

namespace {

const SoundCatalog catalog({{"Keys", {{"electricPiano", "Electric Piano"}}}});
const Key cMajor{PitchClass::C, ScaleType::major};
constexpr auto ranking = ColorStepRanking::theory;

constexpr PadButton a = PadButton::a, b = PadButton::b, x = PadButton::x, y = PadButton::y;
constexpr PadButton lb = PadButton::lb, back = PadButton::back;

Stick lean(double bearing) {
    const double radians = bearing * std::acos(-1.0) / 180;
    return Stick{std::sin(radians), std::cos(radians)};
}

GamepadFrame frame(double time, std::set<PadButton> buttons = {}, Stick left = Stick::rest(), double lt = 0,
                   double rt = 0) {
    return GamepadFrame{
        .time = time, .left = left, .leftTrigger = lt, .rightTrigger = rt, .buttons = std::move(buttons)};
}

Studio studio(KeyAssist assist = KeyAssist::normal) {
    DeskSettings settings;
    settings.keyAssist = assist;
    return Studio(Desk(catalog, settings, LayoutKind::faceChords));
}

std::optional<Degree> heard(const Studio &s) {
    const auto found = s.desk().faceChords().heard();
    return found ? std::optional(found->second) : std::nullopt;
}

const std::vector<int> &notes(const Studio &s) { return s.desk().faceChords().line().notes(); }

std::vector<int> notesOf(Degree degree, const ChordColor &color) {
    return DeskChord(cMajor, degree, color).tones().pitchClasses();
}

} // namespace

TEST_SUITE("Face compass") {

TEST_CASE("A is the root, the others three chords, and RT the other three") {
    const std::vector<std::tuple<PadButton, double, Degree>> chords = {
        {a, 0, Degree::I},  {b, 0, Degree::IV}, {x, 0, Degree::V},  {y, 0, Degree::viiDim},
        {b, 1, Degree::ii}, {x, 1, Degree::iii}, {y, 1, Degree::vi},
    };
    for (const auto &[button, rt, degree] : chords) {
        Studio s = studio();
        s.step(frame(1, {}, Stick::rest(), 0, rt));
        s.step(frame(1.1, {button}, Stick::rest(), 0, rt));
        CHECK(heard(s) == degree);
    }
}

TEST_CASE("LT alone changes no chord: it is the compass's") {
    Studio s = studio();
    s.step(frame(1, {b}));
    s.step(frame(1.1, {b}, Stick::rest(), 1));
    CHECK(heard(s) == Degree::IV);
}

TEST_CASE("the four directions are the inner places, and LT the outer") {
    const std::vector<std::pair<double, ColorStepKind>> directions = {{0, ColorStepKind::add},
                                                                      {90, ColorStepKind::raise},
                                                                      {180, ColorStepKind::takeAway},
                                                                      {270, ColorStepKind::lower}};
    for (const auto &[bearing, kind] : directions)
        for (const bool outer : {false, true}) {
            const CompassPlace place(kind, outer ? 2 : 1);
            Studio s = studio();
            s.step(frame(1, {a}));
            s.step(frame(1.1, {a}, lean(bearing), outer ? 1 : 0));
            const auto step = StepCompass::step(place, StepCompass::base(cMajor, Degree::I), cMajor, Degree::I, ranking);
            REQUIRE(step.has_value());
            CHECK(s.desk().faceChords().line().chord()->tones() == step->tones);
        }
}

TEST_CASE("Assist never plays out of the key, and falls back within the kind") {
    for (const Degree degree : allDegrees)
        for (const CompassPlace &place : CompassPlace::all()) {
            const auto played = FaceCompass::step(place, cMajor, degree, ranking, KeyAssist::assist);
            const auto all = StepCompass::steps(StepCompass::base(cMajor, degree), cMajor, degree, ranking);
            const auto &choices = all.at(place.kind());
            const bool anyInKey = std::any_of(choices.begin(), choices.end(),
                                              [](const ColorStep &step) { return step.fit != ColorFit::borrowed; });
            CHECK(played.has_value() == anyInKey);
            if (!played) continue;
            CHECK(played->fit != ColorFit::borrowed);
            CHECK(played->kind == place.kind());
            const auto own = StepCompass::step(place, StepCompass::base(cMajor, degree), cMajor, degree, ranking);
            if (own && own->fit != ColorFit::borrowed) CHECK(*played == *own);
        }
}

TEST_CASE("Normal and Color code play the place as it is, and only Color code shows what is borrowed") {
    for (const Degree degree : allDegrees)
        for (const CompassPlace &place : CompassPlace::all()) {
            const auto own = StepCompass::step(place, StepCompass::base(cMajor, degree), cMajor, degree, ranking);
            CHECK(FaceCompass::step(place, cMajor, degree, ranking, KeyAssist::normal) == own);
            CHECK(FaceCompass::step(place, cMajor, degree, ranking, KeyAssist::colorCode) == own);
        }
    CHECK(FaceCompass::shownFit(ChordFit::borrowed, KeyAssist::normal) == ChordFit::inKey);
    CHECK(FaceCompass::shownFit(ChordFit::borrowed, KeyAssist::colorCode) == ChordFit::borrowed);
    CHECK(FaceCompass::shownFit(ChordFit::tense, KeyAssist::colorCode) == ChordFit::inKey);
}

TEST_CASE("the stick colors what the button strikes, on each degree its own") {
    Studio s = studio();
    s.step(frame(1, {}, lean(0)));
    s.step(frame(1.1, {x}, lean(0)));
    const auto expected = FaceCompass::color(FaceCompass::place(0, false), cMajor, Degree::V, ranking, KeyAssist::normal);
    CHECK(s.desk().faceChords().line().chord()->tones().pitchClasses() == notesOf(Degree::V, expected));
    const auto colored = notes(s);
    s.step(frame(1.2, {x}));
    CHECK(notes(s) != colored);
}

TEST_CASE("in the timeline LB is its own, and out of it the pins'") {
    Studio s = studio();
    s.step(frame(1, {a}));
    s.step(frame(1.1, {a}, lean(0)));
    s.step(frame(1.2, {a, back}, lean(0)));
    CHECK(s.timeline().isLayered());
    s.step(frame(1.3, {a}, lean(0)));
    s.step(frame(1.4, {a, lb}, lean(0)));
    CHECK_FALSE(s.colors().isOnPins());
    CHECK(s.desk().settings.favorites.colors(cMajor, Degree::I).empty());
    s.step(frame(1.5, {a}, lean(0)));
    s.step(frame(1.6, {a, back}, lean(0)));
    CHECK_FALSE(s.timeline().isLayered());
    s.step(frame(1.7, {a}, lean(0)));
    s.step(frame(1.8, {a, lb}, lean(0)));
    CHECK(s.colors().isOnPins());
}

TEST_CASE("Back then A records, and RT + A does not") {
    Studio s = studio();
    s.step(frame(1));
    s.step(frame(1.1, {a}, Stick::rest(), 0, 1));
    CHECK_FALSE(s.timeline().recording());
    s.step(frame(1.2));
    s.step(frame(1.3, {back}));
    s.step(frame(1.35));
    s.step(frame(1.4, {a}));
    CHECK(s.timeline().recording());
}

TEST_CASE("the panel shows the compass's four places, inner or outer") {
    Studio s = studio();
    s.step(frame(1, {a}));
    auto shown = scene(s, false);
    auto pie = std::get<Pie>(shown.stage.at(0).items.at(1));
    REQUIRE(pie.targets.size() == 4);
    REQUIRE(pie.outer.has_value());
    REQUIRE(pie.outer->size() == 4);
    CHECK(pie.outerTrigger == "LT");
    CHECK_FALSE(pie.isOuterOn);
    CHECK(std::get<Caption>(shown.stage.at(0).items.at(0)).title == "Compass · inner");
    const auto inner = pie.targets[0]->name;
    const auto further = (*pie.outer)[0]->name;
    s.step(frame(1.1, {a}, lean(0), 1));
    shown = scene(s, false);
    pie = std::get<Pie>(shown.stage.at(0).items.at(1));
    CHECK(std::get<Caption>(shown.stage.at(0).items.at(0)).title == "Compass · outer");
    CHECK(pie.isOuterOn);
    // Both rings stay where they were, and only the outer place is aimed at.
    CHECK(pie.targets[0]->name == inner);
    CHECK((*pie.outer)[0]->name == further);
    CHECK_FALSE(pie.targets[0]->isAimed);
    CHECK((*pie.outer)[0]->isAimed);
}

}
