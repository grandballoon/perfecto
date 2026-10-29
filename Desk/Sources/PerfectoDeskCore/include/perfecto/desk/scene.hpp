// What the desk's screen shows, as values: the layouts along the top, each
// layout's stage as panels of items, what every control does, the
// favorites, and the menu over it all. One pure function of the desk makes
// it, so a shell (Godot's, or any engine's) only draws what it is given and
// sends back what the mouse chooses; every word and every choice of what to
// show is here, and tested by equality.
//
// It has no Swift original: the Mac desk's SwiftUI views worked it out as
// they drew, and these are those views' decisions, moved into the core.

#ifndef PERFECTO_DESK_SCENE_HPP
#define PERFECTO_DESK_SCENE_HPP

#include "perfecto/desk/desk.hpp"
#include "perfecto/desk/layout.hpp"
#include "perfecto/desk/pad.hpp"

#include <optional>
#include <string>
#include <utility>
#include <variant>
#include <vector>

namespace perfecto::desk {

/// A color by what it means; the shell's theme gives each its light and
/// dark form.
enum class Tint {
    /// The chords: the phone's orange.
    chord,
    /// The line: the phone's layers' blue.
    melody,
    /// One step from what sounds: the gentle moves.
    near,
    /// A note from outside the key.
    borrowed,
    text,
    secondary,
    faint,
    /// The 360's face buttons.
    a,
    b,
    x,
    y,
};

/// The tint of a face button, or none for the other controls.
std::optional<Tint> tint(PadButton button);

/// A thing a mouse can choose, sent back to the core as it is
/// (`perform(Desk &, const Action &)`).
struct Action {
    enum class Kind {
        chooseLayout,
        toggleMenu,
        arrangeRing,
        pinPlayed,
        unpin,
        addTable,
        removeTable,
        renameTable,
        playTable,
        setKeyDefault,
        // The timeline's (`Studio::perform`): a layer by its id in `index`,
        // an event by its id in `value`.
        record,
        play,
        loop,
        quantize,
        erase,
        undo,
        redo,
        chooseLane,
        muteLane,
        selectEvent,
        stretchChoice,
        deselect,
    };

    Kind kind;
    /// The layout, the arrangement, the table or the degree, by its index.
    int index = 0;
    /// A pinned color's index among its degree's; the switch's new state (1 on).
    int value = 0;
    /// A table's new name.
    std::string text;

    bool operator==(const Action &) const = default;
};

// The items a panel is made of.

/// A small heading over a part of the stage: what plays it and what it is,
/// with a word at its far end.
struct Caption {
    Caption(std::string control, std::string title, std::string aside = "", Tint asideTint = Tint::faint)
        : control(std::move(control)), title(std::move(title)), aside(std::move(aside)), asideTint(asideTint) {}

    std::string control;
    std::string title;
    std::string aside;
    Tint asideTint = Tint::faint;

    bool operator==(const Caption &) const = default;
};

/// A line of text.
struct Note {
    std::string text;
    Tint tint = Tint::secondary;
    bool strong = false;
    /// Large, as the chord a layout is aimed at.
    bool large = false;

    bool operator==(const Note &) const = default;
};

/// A stick's pie: its targets round a circle, each named by what it would
/// sound, and the stick's own place as a dot.
struct Pie {
    std::vector<std::optional<Target>> targets;
    /// A second shell of targets, further out, at the same bearings.
    std::optional<std::vector<std::optional<Target>>> outer;
    Stick stick;
    /// What the middle says: the chord there, and a line under it.
    std::string title;
    std::string detail;
    Tint accent = Tint::chord;
    bool compact = false;

    bool operator==(const Pie &) const = default;
};

/// Two pies side by side.
struct Pies {
    std::vector<Pie> pies;

    bool operator==(const Pies &) const = default;
};

/// The color ring: bands of sectors, inside out, each sector darkest first,
/// the modes named round the outside and the gap where its ends meet.
struct Ring {
    struct Sector {
        std::string mode;
        double bearing;
        /// The degree's own mode: the chord as the key has it.
        bool isOwn;

        bool operator==(const Sector &) const = default;
    };

    std::vector<std::vector<Target>> bands;
    std::vector<Sector> sectors;
    /// Degrees of the stick a sector takes.
    double span;
    double gap;
    /// "Locrian | Lydian": the brightest and the darkest, either side of the gap.
    std::string gapModes;
    Stick stick;
    std::string title;
    std::string detail;

    bool operator==(const Ring &) const = default;
};

/// How far triggers are pulled, side by side.
struct Triggers {
    struct Bar {
        std::string name;
        double value;
        /// Where its steps change, 0 to 1; none for a trigger played smoothly.
        std::vector<double> edges;
        Tint tint = Tint::chord;

        bool operator==(const Bar &) const = default;
    };

    std::vector<Bar> bars;

    bool operator==(const Triggers &) const = default;
};

/// Named values in a row, and a word at the end.
struct Facts {
    std::vector<std::pair<std::string, std::string>> facts;
    std::string aside;

    bool operator==(const Facts &) const = default;
};

/// A row of choices, the one chosen lit, between the controls that move
/// through them; a mouse chooses one if it has an action.
struct Choices {
    std::string before;
    std::vector<std::string> names;
    int chosen;
    std::string after;
    /// What a click on the choice at `index` does: this, with its index.
    std::optional<Action::Kind> action;

    bool operator==(const Choices &) const = default;
};

/// What a line of chords is sounding, named.
struct Sounding {
    bool isSounding;
    /// The chord, or with nothing sounding, how to strike one.
    std::string text;
    /// The arpeggio's rate, if one is on.
    std::string arpeggio;

    bool operator==(const Sounding &) const = default;
};

/// The voices' layer: the bass's moves upright beside the upper voices' pie.
struct Voices {
    /// Up a semitone, up two, down a semitone, down two.
    std::vector<std::optional<Target>> bass;
    Stick left;
    Pie upper;

    bool operator==(const Voices &) const = default;
};

/// The four face buttons, where they are on the controller, each with the
/// chord it would strike now.
struct Diamond {
    struct Petal {
        PadButton button;
        bool isHeld;
        Target target;

        bool operator==(const Petal &) const = default;
    };

    std::vector<Petal> petals;

    bool operator==(const Diamond &) const = default;
};

/// The face buttons as large tiles where they are on the controller, each
/// with the number and the name of the chord it strikes now, and in the
/// middle the chord sounding.
struct Faces {
    struct Face {
        PadButton button;
        /// Where it is in the diamond: A at the bottom.
        double bearing;
        /// "IV", or empty for a button that strikes nothing in this layer.
        std::string numeral;
        /// "F".
        std::string name;
        /// The other layer's chord on it, if it has another: "+LT ii" while
        /// LT is let go, "−LT IV" while it is held.
        std::string other;
        bool isHeld;
        /// It is the button heard.
        bool isHeard;

        bool operator==(const Face &) const = default;
    };

    std::vector<Face> faces;
    /// The chord sounding, its number and its name; empty with none.
    std::string numeral;
    std::string name;
    /// What the middle says with nothing sounding, or under the chord.
    std::string detail;

    bool operator==(const Faces &) const = default;
};

/// Targets in a row, the one aimed at lit: the modes from darker to brighter.
struct Scale {
    std::vector<Target> targets;

    bool operator==(const Scale &) const = default;
};

/// Chips: in rows of `columns`, or with none, as many as fit.
struct Chips {
    struct Chip {
        std::string text;
        bool isLit = false;
        /// A place with nothing in it, drawn faint.
        bool isEmpty = false;

        bool operator==(const Chip &) const = default;
    };

    std::vector<Chip> chips;
    int columns = 0;

    bool operator==(const Chips &) const = default;
};

/// The Trautonium's bar, upright: the key's notes marked along it, and the
/// pitch the line is at. Places are 0 at the bottom to 1 at the top.
struct Bar {
    struct Mark {
        double place;
        bool isTonic;

        bool operator==(const Mark &) const = default;
    };

    std::vector<Mark> marks;
    std::optional<double> pitch;

    bool operator==(const Bar &) const = default;
};

/// The arranger's bars, a lane to each. Places are 0 at the bar's start to 1
/// at its end.
struct Lanes {
    struct Block {
        double from;
        double to;
        /// The chord's name, in the bar it starts in only.
        std::string name;
        bool isHeard;

        bool operator==(const Block &) const = default;
    };

    struct GridLine {
        double place;
        bool isBeat;

        bool operator==(const GridLine &) const = default;
    };

    struct Lane {
        int number;
        std::vector<GridLine> lines;
        std::vector<Block> blocks;
        /// The chord being written, as far as it has grown.
        std::optional<std::pair<double, double>> writing;
        std::optional<double> cursor;
        std::optional<double> playhead;

        bool operator==(const Lane &) const = default;
    };

    std::vector<Lane> lanes;

    bool operator==(const Lanes &) const = default;
};

using Item = std::variant<Caption, Note, Pie, Pies, Ring, Triggers, Facts, Choices, Sounding, Voices, Diamond,
                          Faces, Scale, Chips, Bar, Lanes>;

/// A panel of the stage: its items top to bottom.
struct Panel {
    std::vector<Item> items;
    /// The widest it is drawn; 0 takes what there is.
    double maxWidth = 0;

    bool operator==(const Panel &) const = default;
};

// Around the stage.

/// The layouts, and what the desk is set to.
struct TopBar {
    std::vector<std::string> layouts;
    int chosen;
    std::string summary;
    /// The consonance guard while it is on: its mode, and the notes the run has heard.
    std::optional<std::pair<std::string, std::string>> guard;
    std::vector<std::pair<std::string, std::string>> facts;

    bool operator==(const TopBar &) const = default;
};

/// What every control does now, the left hand's controls and the right's as
/// they are on the controller, each lit while it is held.
struct Hand {
    struct Entry {
        /// The control's own mark: "A", "LB", "LS".
        std::string mark;
        std::string text;
        /// The keyboard's key for it, when the keyboard plays.
        std::string key;
        bool isHeld;
        /// A face button's tint, drawn round.
        std::optional<Tint> tint;

        bool operator==(const Entry &) const = default;
    };

    std::string caption;
    std::vector<Entry> left;
    std::vector<Entry> right;

    bool operator==(const Hand &) const = default;
};

/// The favorite colorations: the tables, the colors pinned to each chord of
/// the key in the one played, and what the mouse can do to them.
struct FavoritesView {
    struct Table {
        std::string name;
        bool isActive;
        /// The key's own: played whenever the key is chosen.
        bool isDefault;
        int count;

        bool operator==(const Table &) const = default;
    };

    struct Degree {
        std::string numeral;
        std::vector<std::string> pinned;

        bool operator==(const Degree &) const = default;
    };

    std::vector<Table> tables;
    bool canRemove;
    /// "Play Favorites whenever the key is C Major", and whether it is.
    std::string keyDefault;
    bool isKeyDefault;
    std::string pinnedCaption;
    std::string pinnedTitle;
    /// "Pin G 7", or how to have something to pin.
    std::string pin;
    bool canPin;
    std::vector<Degree> degrees;
    std::string help;

    bool operator==(const FavoritesView &) const = default;
};

/// The menu over the stage: a row for each setting, or the sound library.
struct MenuView {
    struct Row {
        std::string name;
        std::string value;
        bool isChosen;
        /// Whether ◀ ▶ change it (a row that does something has none).
        bool changes;

        bool operator==(const Row &) const = default;
    };

    struct Library {
        struct Category {
            std::string name;
            bool isLit;
            std::vector<std::pair<std::string, bool>> sounds;

            bool operator==(const Category &) const = default;
        };

        std::string line;
        std::vector<Category> categories;

        bool operator==(const Library &) const = default;
    };

    std::vector<Row> rows;
    std::optional<Library> library;

    bool operator==(const MenuView &) const = default;
};

/// The timeline along the top of the stage: a lane to each layer, its
/// chords as blocks in time, and the controls a mouse can use. Places are in
/// beats from the song's start.
struct TimelineBar {
    struct Block {
        int id;
        double from;
        double to;
        /// The chord's name.
        std::string name;
        /// The voice that plays it.
        int channel;
        bool isChosen;
        /// Sounding now.
        bool isHeard;
        /// A loop's repetition: drawn faint, and chosen through the loop.
        bool isEcho;
        /// Recorded, and outside the layer's loop: not heard.
        bool isLeftOut;

        bool operator==(const Block &) const = default;
    };

    struct Lane {
        int id;
        std::string name;
        std::vector<Block> blocks;
        std::optional<std::pair<double, double>> loop;
        bool isMuted;
        bool isChosen;
        bool isRecording;

        bool operator==(const Lane &) const = default;
    };

    /// A button for the mouse, with the controller's way to it.
    struct Control {
        std::string label;
        std::string keys;
        bool isLit;
        bool isEnabled;
        Action action;

        bool operator==(const Control &) const = default;
    };

    /// The beats shown.
    double from;
    double to;
    int beatsPerBar;
    std::optional<double> playhead;
    std::vector<Lane> lanes;
    std::vector<Control> controls;
    /// What it is doing, and what can be done next.
    std::string status;
    Tint statusTint;
    std::string hint;

    bool operator==(const TimelineBar &) const = default;
};

/// Everything the screen shows.
struct Scene {
    TopBar top;
    std::vector<Panel> stage;
    Hand hand;
    FavoritesView favorites;
    std::optional<MenuView> menu;
    /// The timeline, over Face Chords.
    std::optional<TimelineBar> timeline;

    bool operator==(const Scene &) const = default;
};

/// What `desk` shows, the controls as the keyboard plays them if `keyboard`.
Scene scene(const Desk &desk, bool keyboard);

/// What `legend` says every control does, as the hands hold `frame`.
Hand hand(const Legend &legend, const GamepadFrame &frame, bool keyboard);

/// Does what a mouse chose, and says what to sound.
std::vector<DeskEffect> perform(Desk &desk, const Action &action);

} // namespace perfecto::desk

#endif
