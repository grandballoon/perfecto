// Perfecto at a desk: the settings, a state for each layout, the menu, and
// the frame before. One `step` a frame: the controller in, what to sound out.

#ifndef PERFECTO_DESK_DESK_HPP
#define PERFECTO_DESK_DESK_HPP

#include "perfecto/desk/arranger.hpp"
#include "perfecto/desk/face_chords.hpp"
#include "perfecto/desk/layout.hpp"
#include "perfecto/desk/music.hpp"
#include "perfecto/desk/neighbourhood.hpp"
#include "perfecto/desk/pad.hpp"
#include "perfecto/desk/petals.hpp"
#include "perfecto/desk/twin_rings.hpp"
#include "perfecto/desk/two_voices.hpp"

#include <array>
#include <optional>
#include <string>
#include <vector>

namespace perfecto::desk {

/// The sounds there are to choose from, by category, in the order the
/// library lists them. The shell gives it from the presets (`SynthPreset`),
/// so the core knows sounds only by id and name.
class SoundCatalog {
public:
    struct Sound {
        std::string id;
        std::string name;
        bool operator==(const Sound &) const = default;
    };

    struct Category {
        std::string name;
        std::vector<Sound> sounds;
        bool operator==(const Category &) const = default;
    };

    struct Place {
        int category;
        int index;
        bool operator==(const Place &) const = default;
    };

    /// Categories with no sounds are left out.
    explicit SoundCatalog(const std::vector<Category> &categories);

    bool operator==(const SoundCatalog &) const = default;

    const std::vector<Category> &categories() const { return categories_; }

    /// Where the sound `id` is: its category and its place in it.
    std::optional<Place> place(const std::string &id) const;

    std::string name(const std::string &id) const;

    /// The sound `steps` from `id` through every category in order.
    std::string sound(int steps, const std::string &id) const;

private:
    std::vector<Category> categories_;
};

/// The menu, driven by the d-pad and A: every setting a layout shares, and
/// the sound library.
struct DeskMenu {
    enum class Row {
        layout, consonance, guardInKey, forgetRun, ring, ringOrder, ringFilter, lbLayer, chordSound, lineSound,
        key, scale, octave, tempo, grid, voiceLeading, ranking, output, saveMIDI,
    };

    static constexpr std::array<Row, 19> allRows = {
        Row::layout,     Row::consonance, Row::guardInKey, Row::forgetRun,    Row::ring,
        Row::ringOrder,  Row::ringFilter, Row::lbLayer,    Row::chordSound,   Row::lineSound,
        Row::key,        Row::scale,      Row::octave,     Row::tempo,        Row::grid,
        Row::voiceLeading, Row::ranking,  Row::output,     Row::saveMIDI,
    };

    /// The library open over the menu: a sound for `line`, browsed by
    /// category (left and right) and sound (up and down).
    struct Library {
        Line line;
        int category;
        int index;
        bool operator==(const Library &) const = default;
    };

    Row row = Row::layout;
    std::optional<Library> library;

    bool operator==(const DeskMenu &) const = default;
};

std::string name(DeskMenu::Row row);

/// Perfecto at a desk: the settings, a state for each layout, the menu, and
/// the frame before. One `step` a frame: the controller in, what to sound
/// out.
class Desk {
public:
    DeskSettings settings;

    explicit Desk(SoundCatalog catalog, DeskSettings settings = DeskSettings(),
                  LayoutKind layout = LayoutKind::twinRings);

    /// Two desks are the same if they are in the same state: when the last
    /// frame came is not part of it.
    bool operator==(const Desk &other) const;

    LayoutKind layout() const { return layout_; }
    const FaceChords &faceChords() const { return faceChords_; }
    const TwinRings &twinRings() const { return twinRings_; }
    const Petals &petals() const { return petals_; }
    const Neighbourhood &neighbourhood() const { return neighbourhood_; }
    const TwoVoices &twoVoices() const { return twoVoices_; }
    const Arranger &arranger() const { return arranger_; }
    const std::optional<DeskMenu> &menu() const { return menu_; }
    const SoundCatalog &catalog() const { return catalog_; }
    /// What the last frame said, if any has come.
    const std::optional<GamepadFrame> &frame() const { return frame_; }

    std::vector<DeskEffect> step(const GamepadFrame &frame);

    /// The chord to pin: what the layout is sounding, or else what the hands
    /// are on.
    std::optional<DeskChord> pinnable() const;

    /// Plays `layout` from now: the one left lets go of everything.
    std::vector<DeskEffect> choose(LayoutKind layout);

    /// Opens or closes the menu, as Start does.
    std::vector<DeskEffect> toggleMenu();

    /// Lets go of everything the layout holds: the app is quitting.
    std::vector<DeskEffect> letGo();

    /// Plays `map` on the face buttons in Face Chords.
    void setFaceMap(FaceChords::Map map) { faceChords_.setMap(std::move(map)); }

    /// What every control does now.
    Legend legend() const;

    /// The value a menu row shows.
    std::string value(DeskMenu::Row row) const;

private:
    LayoutKind layout_;
    FaceChords faceChords_;
    TwinRings twinRings_;
    Petals petals_;
    Neighbourhood neighbourhood_;
    TwoVoices twoVoices_;
    Arranger arranger_;
    std::optional<DeskMenu> menu_;
    SoundCatalog catalog_;
    std::optional<GamepadFrame> frame_;

    std::vector<DeskEffect> releaseLayout();
    std::vector<DeskEffect> stepMenu(const PadInput &input);
    std::vector<DeskEffect> change(DeskMenu::Row row, int steps);
    const std::string &sound(Line line) const;
    void setSound(const std::string &id, Line line);
    /// A short sound of `line`'s: the tonic's chord, or its note an octave up.
    DeskEffect preview(Line line) const;
};

} // namespace perfecto::desk

#endif
