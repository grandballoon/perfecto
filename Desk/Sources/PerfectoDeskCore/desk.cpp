#include "perfecto/desk/desk.hpp"

#include <algorithm>

namespace perfecto::desk {

using namespace perfecto::theory;

namespace {

void append(std::vector<DeskEffect> &out, const std::vector<DeskEffect> &more) {
    out.insert(out.end(), more.begin(), more.end());
}

template <class T, size_t N> int indexIn(const std::array<T, N> &all, T value) {
    return static_cast<int>(std::find(all.begin(), all.end(), value) - all.begin());
}

/// `all`'s value `steps` from `value`, round and round.
template <class T, size_t N> T stepped(const std::array<T, N> &all, T value, int steps) {
    const int count = static_cast<int>(N);
    return all[((indexIn(all, value) + steps) % count + count) % count];
}

} // namespace

// MARK: – The catalog

SoundCatalog::SoundCatalog(const std::vector<Category> &categories) {
    for (const Category &category : categories)
        if (!category.sounds.empty()) categories_.push_back(category);
}

std::optional<SoundCatalog::Place> SoundCatalog::place(const std::string &id) const {
    for (size_t c = 0; c < categories_.size(); ++c) {
        const auto &sounds = categories_[c].sounds;
        for (size_t i = 0; i < sounds.size(); ++i)
            if (sounds[i].id == id) return Place{static_cast<int>(c), static_cast<int>(i)};
    }
    return std::nullopt;
}

std::string SoundCatalog::name(const std::string &id) const {
    const auto at = place(id);
    return at ? categories_[at->category].sounds[at->index].name : id;
}

std::string SoundCatalog::sound(int steps, const std::string &id) const {
    std::vector<Sound> all;
    for (const Category &category : categories_) all.insert(all.end(), category.sounds.begin(), category.sounds.end());
    const auto found = std::find_if(all.begin(), all.end(), [&](const Sound &s) { return s.id == id; });
    if (found == all.end()) return all.empty() ? id : all.front().id;
    const int count = static_cast<int>(all.size());
    const int at = static_cast<int>(found - all.begin());
    return all[((at + steps) % count + count) % count].id;
}

// MARK: – The menu

std::string name(DeskMenu::Row row) {
    switch (row) {
    case DeskMenu::Row::layout: return "Layout";
    case DeskMenu::Row::consonance: return "Consonance guard";
    case DeskMenu::Row::guardInKey: return "Guard: key's notes only";
    case DeskMenu::Row::forgetRun: return "Forget the run";
    case DeskMenu::Row::ring: return "Color ring";
    case DeskMenu::Row::ringOrder: return "Ring order";
    case DeskMenu::Row::ringFilter: return "Ring filter";
    case DeskMenu::Row::lbLayer: return "LB layer";
    case DeskMenu::Row::chordSound: return "Chord sound";
    case DeskMenu::Row::lineSound: return "Line sound";
    case DeskMenu::Row::key: return "Key";
    case DeskMenu::Row::scale: return "Scale";
    case DeskMenu::Row::octave: return "Octave";
    case DeskMenu::Row::tempo: return "Tempo";
    case DeskMenu::Row::grid: return "Arranger grid";
    case DeskMenu::Row::voiceLeading: return "Voice leading";
    case DeskMenu::Row::ranking: return "Compass order";
    case DeskMenu::Row::output: return "Output";
    case DeskMenu::Row::saveMIDI: return "Save the arrangement";
    }
    return {};
}

// MARK: – The desk

Desk::Desk(SoundCatalog catalog, DeskSettings settings, LayoutKind layout)
    : settings(std::move(settings)), layout_(layout), catalog_(std::move(catalog)) {}

bool Desk::operator==(const Desk &other) const {
    const auto untimed = [](const std::optional<GamepadFrame> &frame) {
        return frame ? std::optional<GamepadFrame>(frame->untimed()) : std::nullopt;
    };
    return settings == other.settings && layout_ == other.layout_ && faceChords_ == other.faceChords_ &&
           twinRings_ == other.twinRings_ && petals_ == other.petals_ && neighbourhood_ == other.neighbourhood_ &&
           twoVoices_ == other.twoVoices_ && arranger_ == other.arranger_ && menu_ == other.menu_ &&
           catalog_ == other.catalog_ && untimed(frame_) == untimed(other.frame_);
}

std::vector<DeskEffect> Desk::step(const GamepadFrame &frame) {
    const GamepadFrame previous = frame_ ? *frame_ : GamepadFrame{.time = frame.time};
    frame_ = frame;
    const PadInput input(frame, previous);
    if (menu_) return stepMenu(input);
    if (input.pressed(PadButton::start)) {
        menu_ = DeskMenu();
        return releaseLayout();
    }
    if (input.pressed(PadButton::back)) return choose(stepped(allLayoutKinds, layout_, 1));
    const Key key = settings.key;
    std::vector<DeskEffect> out;
    switch (layout_) {
    case LayoutKind::faceChords: out = faceChords_.step(input, settings); break;
    case LayoutKind::twinRings: out = twinRings_.step(input, settings); break;
    case LayoutKind::petals: out = petals_.step(input, settings); break;
    case LayoutKind::neighbourhood: out = neighbourhood_.step(input, settings); break;
    case LayoutKind::twoVoices: out = twoVoices_.step(input, settings); break;
    case LayoutKind::arranger: out = arranger_.step(input, settings); break;
    }
    if (settings.key != key) settings.favorites.keyChanged(settings.key);
    settings.consonance.hear(out);
    return out;
}

std::optional<DeskChord> Desk::pinnable() const {
    switch (layout_) {
    case LayoutKind::faceChords:
        for (const auto &voice : faceChords_.voices())
            if (voice.line.isSounding()) return voice.line.chord();
        return std::nullopt;
    case LayoutKind::twinRings:
        return twinRings_.line().isSounding() ? twinRings_.line().chord() : twinRings_.chord(settings);
    case LayoutKind::petals:
        return petals_.line().isSounding() ? petals_.line().chord() : std::nullopt;
    case LayoutKind::neighbourhood:
        return neighbourhood_.line().isSounding() ? neighbourhood_.line().chord() : neighbourhood_.centre();
    case LayoutKind::twoVoices:
        return twoVoices_.chords().isSounding() ? twoVoices_.chords().chord() : twoVoices_.chord(settings);
    case LayoutKind::arranger:
        return arranger_.line().isSounding() ? arranger_.line().chord() : arranger_.aimed(settings);
    }
    return std::nullopt;
}

std::vector<DeskEffect> Desk::choose(LayoutKind layout) {
    if (layout == layout_) return {};
    std::vector<DeskEffect> out = releaseLayout();
    layout_ = layout;
    out.push_back(DeskEffect::rumble(Rumble::bump));
    return out;
}

std::vector<DeskEffect> Desk::toggleMenu() {
    if (!menu_) {
        menu_ = DeskMenu();
        return releaseLayout();
    }
    menu_.reset();
    return {};
}

std::vector<DeskEffect> Desk::letGo() { return releaseLayout(); }

std::vector<DeskEffect> Desk::releaseLayout() {
    std::vector<DeskEffect> out;
    switch (layout_) {
    case LayoutKind::faceChords: out = faceChords_.releaseAll(); break;
    case LayoutKind::twinRings: out = twinRings_.releaseAll(); break;
    case LayoutKind::petals: out = petals_.releaseAll(); break;
    case LayoutKind::neighbourhood: out = neighbourhood_.releaseAll(); break;
    case LayoutKind::twoVoices: out = twoVoices_.releaseAll(); break;
    case LayoutKind::arranger: out = arranger_.releaseAll(); break;
    }
    settings.consonance.hear(out);
    return out;
}

Legend Desk::legend() const {
    if (menu_) {
        if (menu_->library) {
            return {{PadControl::button(PadButton::left), "Category before"},
                    {PadControl::button(PadButton::right), "Next category"},
                    {PadControl::button(PadButton::up), "Sound before"},
                    {PadControl::button(PadButton::down), "Next sound"},
                    {PadControl::button(PadButton::a), "Choose"},
                    {PadControl::button(PadButton::b), "Back"}};
        }
        return {{PadControl::button(PadButton::up), "Row up"},     {PadControl::button(PadButton::down), "Row down"},
                {PadControl::button(PadButton::left), "Less"},     {PadControl::button(PadButton::right), "More"},
                {PadControl::button(PadButton::a), "Open"},        {PadControl::button(PadButton::b), "Close"},
                {PadControl::button(PadButton::start), "Close"}};
    }
    switch (layout_) {
    case LayoutKind::faceChords: return faceChords_.legend(settings);
    case LayoutKind::twinRings: return twinRings_.legend(settings);
    case LayoutKind::petals: return petals_.legend(settings);
    case LayoutKind::neighbourhood: return neighbourhood_.legend(settings);
    case LayoutKind::twoVoices: return twoVoices_.legend(settings);
    case LayoutKind::arranger: return arranger_.legend(settings);
    }
    return {};
}

// MARK: – The menu

std::vector<DeskEffect> Desk::stepMenu(const PadInput &input) {
    if (!menu_) return {};
    DeskMenu menu = *menu_;
    std::vector<DeskEffect> out;
    bool closes = input.pressed(PadButton::start);
    if (menu.library) {
        DeskMenu::Library library = *menu.library;
        const auto &categories = catalog_.categories();
        const int sounds = static_cast<int>(categories[library.category].sounds.size());
        if (input.pressed(PadButton::up)) library.index = std::max(0, library.index - 1);
        if (input.pressed(PadButton::down)) library.index = std::min(sounds - 1, library.index + 1);
        if (input.pressed(PadButton::left) || input.pressed(PadButton::right)) {
            const int count = static_cast<int>(categories.size());
            library.category = (library.category + (input.pressed(PadButton::left) ? count - 1 : 1)) % count;
            library.index =
                std::min(library.index, static_cast<int>(categories[library.category].sounds.size()) - 1);
        }
        // A sound is chosen as it is reached, and heard.
        const std::string chosen = categories[library.category].sounds[library.index].id;
        if (chosen != sound(library.line)) {
            setSound(chosen, library.line);
            out.push_back(preview(library.line));
        }
        if (input.pressed(PadButton::a) || input.pressed(PadButton::b)) menu.library.reset();
        else menu.library = library;
    } else {
        closes = closes || input.pressed(PadButton::b);
        const auto &rows = DeskMenu::allRows;
        const int at = indexIn(rows, menu.row);
        if (input.pressed(PadButton::up)) menu.row = rows[std::max(0, at - 1)];
        if (input.pressed(PadButton::down)) menu.row = rows[std::min(static_cast<int>(rows.size()) - 1, at + 1)];
        if (input.pressed(PadButton::left)) append(out, change(menu.row, -1));
        if (input.pressed(PadButton::right)) append(out, change(menu.row, 1));
        if (input.pressed(PadButton::a)) {
            switch (menu.row) {
            case DeskMenu::Row::chordSound:
            case DeskMenu::Row::lineSound: {
                const Line line = menu.row == DeskMenu::Row::chordSound ? Line::chord : Line::melody;
                const auto place = catalog_.place(sound(line)).value_or(SoundCatalog::Place{0, 0});
                menu.library = DeskMenu::Library{line, place.category, place.index};
                break;
            }
            case DeskMenu::Row::saveMIDI:
                if (const auto file = arranger_.midiFile(settings))
                    out.push_back(DeskEffect::saveMIDI(file->encoded(), "Perfecto Desk " + settings.summary()));
                break;
            case DeskMenu::Row::layout: closes = true; break;
            default: append(out, change(menu.row, 1)); break;
            }
        }
    }
    if (closes) menu_.reset();
    else menu_ = menu;
    return out;
}

std::vector<DeskEffect> Desk::change(DeskMenu::Row row, int steps) {
    switch (row) {
    case DeskMenu::Row::layout: layout_ = stepped(allLayoutKinds, layout_, steps); break;
    case DeskMenu::Row::consonance: settings.moveGuard(steps); break;
    case DeskMenu::Row::guardInKey: settings.consonance.inKey = !settings.consonance.inKey; break;
    case DeskMenu::Row::forgetRun: settings.consonance.forgetRun(); break;
    case DeskMenu::Row::ring: settings.moveRingArrangement(steps); break;
    case DeskMenu::Row::ringOrder: settings.moveRingOrder(steps); break;
    case DeskMenu::Row::ringFilter: settings.moveRingFilter(steps); break;
    case DeskMenu::Row::lbLayer:
        settings.lbLayer = settings.lbLayer == LBLayer::compass ? LBLayer::voices : LBLayer::compass;
        break;
    case DeskMenu::Row::chordSound:
    case DeskMenu::Row::lineSound: {
        const Line line = row == DeskMenu::Row::chordSound ? Line::chord : Line::melody;
        setSound(catalog_.sound(steps, sound(line)), line);
        return {preview(line)};
    }
    case DeskMenu::Row::key: {
        const int root = (raw(settings.key.root) + steps + 12) % 12;
        settings.key = Key{pitchClass(root), settings.key.scale};
        settings.favorites.keyChanged(settings.key);
        return {preview(Line::chord)};
    }
    case DeskMenu::Row::scale:
        settings.moveScale(steps);
        settings.favorites.keyChanged(settings.key);
        return {preview(Line::chord)};
    case DeskMenu::Row::octave: settings.moveOctave(steps); return {preview(Line::chord)};
    case DeskMenu::Row::tempo:
        settings.tempo = std::min(DeskSettings::tempos.upperBound,
                                  std::max(DeskSettings::tempos.lowerBound, settings.tempo + 2 * double(steps)));
        break;
    case DeskMenu::Row::grid: settings.moveGrid(steps); break;
    case DeskMenu::Row::voiceLeading: settings.voiceLeading = !settings.voiceLeading; break;
    case DeskMenu::Row::ranking:
        settings.ranking = settings.ranking == ColorStepRanking::theory ? ColorStepRanking::common
                                                                         : ColorStepRanking::theory;
        break;
    case DeskMenu::Row::output: settings.output = stepped(allDeskOutputs, settings.output, steps); break;
    case DeskMenu::Row::saveMIDI: break;
    }
    return {};
}

const std::string &Desk::sound(Line line) const {
    return line == Line::chord ? settings.chordSound : settings.lineSound;
}

void Desk::setSound(const std::string &id, Line line) {
    if (line == Line::chord) settings.chordSound = id;
    else settings.lineSound = id;
}

DeskEffect Desk::preview(Line line) const {
    const DeskChord chord(settings.key, Degree::I);
    const std::vector<int> notes = chord.notes(settings);
    return DeskEffect::preview(sound(line), line == Line::chord ? notes : std::vector<int>{notes[0] + 12});
}

std::string Desk::value(DeskMenu::Row row) const {
    switch (row) {
    case DeskMenu::Row::layout: return name(layout_);
    case DeskMenu::Row::consonance: return name(settings.consonance.mode);
    case DeskMenu::Row::guardInKey: return settings.consonance.inKey ? "On" : "Off";
    case DeskMenu::Row::forgetRun: return settings.consonance.recent().empty() ? "Nothing heard" : "A to forget";
    case DeskMenu::Row::ring: return name(settings.ringArrangement);
    case DeskMenu::Row::ringOrder: return name(settings.ringOrder);
    case DeskMenu::Row::ringFilter: return name(settings.ringFilter);
    case DeskMenu::Row::lbLayer: return name(settings.lbLayer);
    case DeskMenu::Row::chordSound: return catalog_.name(settings.chordSound);
    case DeskMenu::Row::lineSound: return catalog_.name(settings.lineSound);
    case DeskMenu::Row::key: return theory::name(settings.key.root);
    case DeskMenu::Row::scale: return displayName(settings.key.scale);
    case DeskMenu::Row::octave: return std::to_string(settings.octave);
    case DeskMenu::Row::tempo: return std::to_string(static_cast<int>(settings.tempo)) + " bpm";
    case DeskMenu::Row::grid: return name(settings.grid);
    case DeskMenu::Row::voiceLeading: return settings.voiceLeading ? "On" : "Off";
    case DeskMenu::Row::ranking: return settings.ranking == ColorStepRanking::theory ? "Theory" : "Common first";
    case DeskMenu::Row::output: return name(settings.output);
    case DeskMenu::Row::saveMIDI: return !arranger_.arrangement().isEmpty() ? "A to save" : "Nothing written yet";
    }
    return {};
}

} // namespace perfecto::desk
