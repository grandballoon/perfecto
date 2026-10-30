// The left hand's colors over Face Chords: the Orchid's buttons and the
// phone's joystick table on the left stick, the pins LB puts there, and the
// studio that plays them beside the desk.

#include <doctest.h>

#include "perfecto/desk/face_colors.hpp"
#include "perfecto/desk/scene.hpp"
#include "perfecto/desk/studio.hpp"
#include "rig.hpp"

#include <algorithm>
#include <vector>

using namespace perfecto::desk;
using namespace perfecto::desk::testing;
using namespace perfecto::theory;

namespace {

const SoundCatalog catalog({{"Keys", {{"electricPiano", "Electric Piano"}}}, {"Synth", {{"soloLead", "Solo Lead"}}}});
const Key cMajor{PitchClass::C, ScaleType::major};

GamepadFrame frame(double time, std::set<PadButton> buttons = {}, Stick left = Stick::rest(), double rightTrigger = 0) {
    return GamepadFrame{.time = time, .left = left, .rightTrigger = rightTrigger, .buttons = std::move(buttons)};
}

Studio faceChords(FaceStick stick = FaceStick::orchid) {
    DeskSettings settings;
    settings.faceStick = stick;
    return Studio(Desk(catalog, settings, LayoutKind::faceChords));
}

const std::vector<int> &notes(const Studio &studio) { return studio.desk().faceChords().line().notes(); }

ChordColor built(std::optional<ChordType> type, std::set<ChordExtension> extensions = {}) {
    return ChordColor::built(ChordBuild(type, std::move(extensions)));
}

bool has(const Studio::Played &played, Rumble rumble) {
    const auto &e = played.effects;
    return std::find(e.begin(), e.end(), DeskEffect::rumble(rumble)) != e.end();
}

constexpr PadButton a = PadButton::a;
constexpr PadButton lb = PadButton::lb;

} // namespace

TEST_SUITE("Face colors") {

TEST_CASE("the Orchid's buttons are round the stick, and two held build together") {
    using enum OrchidButton;
    CHECK(FaceColors::ring == std::array{maj, minorSeventh, ninth, majorSeventh, min, sixth, dim, sus});
    CHECK(mark(minorSeventh) == "m7");
    CHECK(FaceColors::build(maj, maj) == ChordBuild(ChordType::major));
    CHECK(FaceColors::build(maj, minorSeventh) == ChordBuild(ChordType::major, {ChordExtension::minorSeventh}));
    CHECK(FaceColors::build(minorSeventh, ninth) ==
          ChordBuild(std::nullopt, {ChordExtension::minorSeventh, ChordExtension::ninth}));
    CHECK(FaceColors::build(sus, minorSeventh) == ChordBuild(ChordType::suspended, {ChordExtension::minorSeventh}));
    // Of two types the later is played, as on the Orchid.
    CHECK(FaceColors::build(dim, sus) == ChordBuild(ChordType::suspended));

    // Each pair of neighbours is a chord: on C, the seventh, the ninth, the
    // major ninth, the minor-major seventh, the minor sixth, the diminished seventh.
    const std::vector<std::vector<int>> pairs = {
        {60, 64, 67, 70}, {60, 64, 67, 70, 74}, {60, 64, 67, 71, 74}, {60, 63, 67, 71}, {60, 63, 67, 69}, {60, 63, 66, 69},
    };
    for (int sector = 0; sector < 6; ++sector) {
        const ChordColor color = FaceColors::live(FaceStick::orchid, sector, sector + 1);
        CHECK(DeskChord(cMajor, Degree::I, color).notes(DeskSettings()) == pairs[static_cast<size_t>(sector)]);
    }
}

TEST_CASE("the table is the phone's joystick, its directions as they were") {
    CHECK(FaceColors::live(FaceStick::perfectoDefault, std::nullopt, std::nullopt) == ChordColor::base());
    CHECK(FaceColors::live(FaceStick::perfectoDefault, 0, 0) == ChordColor::joystick(JoystickMode::default_, JoystickDirection::up));
    CHECK(FaceColors::live(FaceStick::perfectoExtended, 4, 1) ==
          ChordColor::joystick(JoystickMode::extended, JoystickDirection::upRight));
    CHECK(FaceColors::live(FaceStick::perfectoChromatic, std::nullopt, 7) ==
          ChordColor::joystick(JoystickMode::chromatic, JoystickDirection::upLeft));
    // The Orchid's at rest is plain too.
    CHECK(FaceColors::live(FaceStick::orchid, std::nullopt, std::nullopt) == ChordColor::base());
}

TEST_CASE("leaning colors the chord held, rolling on adds a second button, and the middle lets go") {
    Studio studio = faceChords();
    studio.step(frame(1, {a}));
    CHECK(notes(studio) == std::vector{60, 64, 67});
    // Right is 9.
    const auto leaned = studio.step(frame(1.1, {a}, lean(90)));
    CHECK(notes(studio) == std::vector{60, 64, 67, 74});
    REQUIRE(leaned.effects.size() == 1);
    CHECK(std::get<DeskEffect::Sound>(leaned.effects[0].value()).tie);
    // Rolled on to M7, with 9 still held: the major ninth.
    studio.step(frame(1.2, {a}, lean(135)));
    CHECK(notes(studio) == std::vector{60, 64, 67, 71, 74});
    // On to Min, 9 still held.
    studio.step(frame(1.3, {a}, lean(180)));
    CHECK(notes(studio) == std::vector{60, 63, 67, 74});
    studio.step(frame(1.4, {a}));
    CHECK(notes(studio) == std::vector{60, 64, 67});
    // From the middle, M7 alone.
    studio.step(frame(1.5, {a}, lean(135)));
    CHECK(notes(studio) == std::vector{60, 64, 67, 71});
    CHECK(studio.desk().faceChords().line().chord() ==
          DeskChord(cMajor, Degree::I, built(std::nullopt, {ChordExtension::majorSeventh})));
}

TEST_CASE("a stick leaned before the button colors the chord it strikes, and every degree alike") {
    Studio studio = faceChords();
    studio.step(frame(1, {}, lean(45)));
    studio.step(frame(1.1, {PadButton::x}, lean(45)));
    // V with m7: G 7.
    CHECK(notes(studio) == std::vector{67, 71, 74, 77});
}

TEST_CASE("Perfecto's table colors from the menu's choice of mode") {
    Studio studio = faceChords(FaceStick::perfectoDefault);
    studio.step(frame(1, {a}));
    // Up-right is Dom 7, up flips the third.
    studio.step(frame(1.1, {a}, lean(45)));
    CHECK(notes(studio) == std::vector{60, 64, 67, 70});
    studio.step(frame(1.2, {a}, lean(0)));
    CHECK(notes(studio) == std::vector{60, 63, 67});
    // The table has no second button: rolling on is the next direction alone.
    studio.step(frame(1.3, {a}, lean(90)));
    CHECK(notes(studio) == std::vector{60, 64, 67, 71});
}

TEST_CASE("LB while coloring pins the color, LB held plays the pins, and LB again takes one out") {
    Studio studio = faceChords();
    studio.step(frame(1, {a}));
    studio.step(frame(1.1, {a}, lean(90)));
    const auto pinned = studio.step(frame(1.2, {a, lb}, lean(90)));
    CHECK(has(pinned, Rumble::bump));
    const ChordColor ninth = built(std::nullopt, {ChordExtension::ninth});
    CHECK(studio.desk().settings.favorites.colors(cMajor, Degree::I) == std::vector{ninth});
    // The color pinned sounds on while the stick stays.
    CHECK(notes(studio) == std::vector{60, 64, 67, 74});
    studio.step(frame(1.3, {a}, lean(90)));
    studio.step(frame(1.4, {a}));
    studio.step(frame(1.5, {a}, lean(45)));
    studio.step(frame(1.6, {a, lb}, lean(45)));
    const ChordColor seventh = built(std::nullopt, {ChordExtension::minorSeventh});
    CHECK(studio.desk().settings.favorites.colors(cMajor, Degree::I) == std::vector{ninth, seventh});
    studio.step(frame(1.7, {a}));

    // The pins round the stick, the first at the top; a place with none is plain.
    studio.step(frame(1.8, {a, lb}));
    CHECK(studio.colors().isOnPins());
    CHECK(notes(studio) == std::vector{60, 64, 67});
    studio.step(frame(1.9, {a, lb}, lean(0)));
    CHECK(notes(studio) == std::vector{60, 64, 67, 74});
    studio.step(frame(2.0, {a, lb}, lean(45)));
    CHECK(notes(studio) == std::vector{60, 64, 67, 70});
    studio.step(frame(2.1, {a, lb}, lean(90)));
    CHECK(notes(studio) == std::vector{60, 64, 67});
    // Another degree has its own pins: none.
    studio.step(frame(2.2, {lb}, lean(0)));
    studio.step(frame(2.3, {PadButton::x, lb}, lean(0)));
    CHECK(notes(studio) == std::vector{67, 71, 74});

    // Pinned again, a color is taken out.
    studio.step(frame(2.4, {a}));
    studio.step(frame(2.5, {a}, lean(90)));
    const auto unpinned = studio.step(frame(2.6, {a, lb}, lean(90)));
    CHECK(has(unpinned, Rumble::tick));
    CHECK(studio.desk().settings.favorites.colors(cMajor, Degree::I) == std::vector{seventh});
}

TEST_CASE("a pin taken from two buttons held stays what it sounded") {
    Studio studio = faceChords();
    studio.step(frame(1, {a}));
    studio.step(frame(1.1, {a}, lean(90)));
    studio.step(frame(1.2, {a}, lean(135)));
    studio.step(frame(1.3, {a, lb}, lean(135)));
    CHECK(studio.desk().settings.favorites.colors(cMajor, Degree::I) ==
          std::vector{built(std::nullopt, {ChordExtension::majorSeventh, ChordExtension::ninth})});
    CHECK(notes(studio) == std::vector{60, 64, 67, 71, 74});
    // Let go of LB on it, and the two are still held.
    studio.step(frame(1.4, {a}, lean(135)));
    CHECK(notes(studio) == std::vector{60, 64, 67, 71, 74});
}

TEST_CASE("LB with the second voice still routes a press, and the stick plays that chord's pins") {
    Studio studio = faceChords();
    studio.step(frame(0.1, {PadButton::r3}));
    studio.step(frame(0.2));
    studio.step(frame(1, {lb}));
    studio.step(frame(1.1, {lb, a}));
    CHECK(studio.desk().faceChords().voices()[1].line.isSounding());
    CHECK_FALSE(studio.desk().faceChords().line().isSounding());
    CHECK(studio.colors().isOnPins());
}

TEST_CASE("RT takes the stick for the timeline, and the menu lets go of the color") {
    Studio studio = faceChords();
    studio.step(frame(1, {a}));
    studio.step(frame(1.1, {a}, lean(90)));
    studio.step(frame(1.2, {a}, lean(90), 1));
    CHECK(notes(studio) == std::vector{60, 64, 67});
    studio.step(frame(1.3, {a}, lean(90)));
    CHECK(notes(studio) == std::vector{60, 64, 67, 74});
    studio.toggleMenu();
    studio.step(frame(1.4, {a}, lean(90)));
    CHECK(studio.desk().faceChords().colors().empty());
    CHECK_FALSE(studio.colors().aim().has_value());
}

TEST_CASE("the timeline hears the chord as it is colored") {
    Studio studio = faceChords();
    studio.step(frame(1, {a}, lean(45)));
    const Heard heard = perfecto::desk::heard(studio.desk());
    REQUIRE(heard.contains(0));
    CHECK(heard.at(0).chord == DeskChord(cMajor, Degree::I, built(std::nullopt, {ChordExtension::minorSeventh})));
    CHECK(heard.at(0).notes == std::vector{60, 64, 67, 70});
}

TEST_CASE("the screen shows what each direction plays on the chord held, and with LB its pins") {
    Studio studio = faceChords();
    studio.step(frame(1, {a}, lean(90)));
    auto stage = scene(studio, false).stage;
    REQUIRE(stage.size() == 2);
    auto caption = std::get<Caption>(stage[0].items.at(0));
    CHECK(caption.title == "The Orchid's chord buttons");
    auto pie = std::get<Pie>(stage[0].items.at(1));
    REQUIRE(pie.targets.size() == 8);
    const auto majorNinth = DeskChord(cMajor, Degree::I, FaceColors::live(FaceStick::orchid, 2, 3));
    CHECK(pie.targets[3]->name == majorNinth.name());
    CHECK(pie.targets[3]->detail == "9 + M7");
    CHECK(pie.targets[2]->isAimed);
    CHECK_FALSE(pie.targets[2]->isKept);
    studio.step(frame(1.1, {a}, lean(135)));
    pie = std::get<Pie>(scene(studio, false).stage[0].items.at(1));
    CHECK(pie.targets[2]->isKept);
    CHECK(pie.targets[3]->isAimed);
    CHECK(pie.title == majorNinth.name());

    // Nothing held: what each direction does.
    studio.step(frame(1.2));
    pie = std::get<Pie>(scene(studio, false).stage[0].items.at(1));
    CHECK(pie.targets[0]->name == "Maj");
    CHECK(pie.targets[0]->detail.empty());

    studio.step(frame(1.3, {a}, lean(90)));
    studio.step(frame(1.4, {a, lb}, lean(90)));
    stage = scene(studio, false).stage;
    caption = std::get<Caption>(stage[0].items.at(0));
    CHECK(caption.title == "The pins of I");
    pie = std::get<Pie>(stage[0].items.at(1));
    CHECK(pie.targets[0]->name == DeskChord(cMajor, Degree::I, built(std::nullopt, {ChordExtension::ninth})).name());
    CHECK_FALSE(pie.targets[1].has_value());

    CHECK(studio.legend().at(PadControl::leftStick()) == "The pins of the chord held");
    studio.step(frame(1.5, {a}));
    CHECK(studio.legend().at(PadControl::leftStick()) == "Color: Orchid buttons · roll on for two");
    CHECK(studio.legend().at(PadControl::button(lb)) == "Press while coloring: pin · hold: the pins");
}

TEST_CASE("the menu chooses the stick's scheme") {
    Desk desk(catalog, DeskSettings(), LayoutKind::faceChords);
    CHECK(desk.value(DeskMenu::Row::faceStick) == "Orchid buttons");
    desk.step(frame(1, {PadButton::start}));
    for (int i = 0; i < 8; ++i) {
        desk.step(frame(2 + double(i) * 0.1, {PadButton::down}));
        desk.step(frame(2.05 + double(i) * 0.1));
    }
    REQUIRE(desk.menu()->row == DeskMenu::Row::faceStick);
    desk.step(frame(3, {PadButton::right}));
    CHECK(desk.settings.faceStick == FaceStick::perfectoDefault);
    desk.step(frame(3.1));
    desk.step(frame(3.2, {PadButton::left}));
    desk.step(frame(3.3));
    desk.step(frame(3.4, {PadButton::left}));
    CHECK(desk.value(DeskMenu::Row::faceStick) == "Perfecto · chromatic");
}

}
