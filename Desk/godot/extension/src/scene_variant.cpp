#include "scene_variant.h"

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include <array>
#include <string_view>
#include <utility>

using namespace godot;
namespace desk = perfecto::desk;

namespace perfecto_godot {

namespace {

String text(const std::string &value) { return String::utf8(value.c_str()); }

const char *name(desk::Tint tint) {
    switch (tint) {
    case desk::Tint::chord: return "chord";
    case desk::Tint::melody: return "melody";
    case desk::Tint::near: return "near";
    case desk::Tint::borrowed: return "borrowed";
    case desk::Tint::text: return "text";
    case desk::Tint::secondary: return "secondary";
    case desk::Tint::faint: return "faint";
    case desk::Tint::a: return "a";
    case desk::Tint::b: return "b";
    case desk::Tint::x: return "x";
    case desk::Tint::y: return "y";
    }
    return "text";
}

const char *name(desk::ChordFit fit) {
    switch (fit) {
    case desk::ChordFit::inKey: return "in_key";
    case desk::ChordFit::tense: return "tense";
    case desk::ChordFit::borrowed: return "borrowed";
    }
    return "in_key";
}

constexpr std::array<std::pair<desk::Action::Kind, std::string_view>, 10> actionNames = {{
    {desk::Action::Kind::chooseLayout, "choose_layout"},
    {desk::Action::Kind::toggleMenu, "toggle_menu"},
    {desk::Action::Kind::arrangeRing, "arrange_ring"},
    {desk::Action::Kind::pinPlayed, "pin_played"},
    {desk::Action::Kind::unpin, "unpin"},
    {desk::Action::Kind::addTable, "add_table"},
    {desk::Action::Kind::removeTable, "remove_table"},
    {desk::Action::Kind::renameTable, "rename_table"},
    {desk::Action::Kind::playTable, "play_table"},
    {desk::Action::Kind::setKeyDefault, "set_key_default"},
}};

const char *name(desk::Action::Kind kind) {
    for (const auto &[k, n] : actionNames)
        if (k == kind) return n.data();
    return "";
}

Variant v(const std::string &value) { return text(value); }
Variant v(double value) { return value; }
Variant v(bool value) { return value; }
Variant v(int value) { return value; }
Variant v(desk::Tint tint) { return name(tint); }
Variant v(const desk::Stick &stick) { return Vector2(float(stick.x), float(stick.y)); }

// Declared before the templates, which find them by ordinary lookup (they
// are not in the namespace of what they convert, so not found by ADL).
Variant v(const std::pair<std::string, std::string> &pair);
Variant v(const std::pair<double, double> &pair);
Variant v(const desk::Target &target);
Variant v(const desk::Pie &pie);
Variant v(const desk::Triggers::Bar &bar);
Variant v(const desk::Ring::Sector &sector);
Variant v(const desk::Chips::Chip &chip);
Variant v(const desk::Bar::Mark &mark);
Variant v(const desk::Lanes::GridLine &line);
Variant v(const desk::Lanes::Block &block);
Variant v(const desk::Lanes::Lane &lane);
Variant v(const desk::Diamond::Petal &petal);
Variant v(const desk::Panel &panel);
Variant v(const desk::Hand::Entry &entry);
Variant v(const desk::FavoritesView::Table &table);
Variant v(const desk::FavoritesView::Degree &degree);
Variant v(const desk::MenuView::Row &row);
Variant v(const desk::MenuView::Library::Category &category);

template <class T> Variant v(const std::vector<T> &values);

template <class T> Variant v(const std::optional<T> &value) { return value ? v(*value) : Variant(); }

template <class T> Variant v(const std::vector<T> &values) {
    Array array;
    for (const auto &value : values) array.push_back(v(value));
    return array;
}

Variant v(const std::pair<std::string, std::string> &pair) {
    Array array;
    array.push_back(text(pair.first));
    array.push_back(text(pair.second));
    return array;
}

Variant v(const std::pair<double, double> &pair) {
    Array array;
    array.push_back(pair.first);
    array.push_back(pair.second);
    return array;
}

Variant v(const desk::Target &target) {
    Dictionary d;
    d["bearing"] = target.bearing;
    d["name"] = text(target.name);
    d["detail"] = text(target.detail);
    d["fit"] = name(target.fit);
    d["near"] = target.isNear;
    d["aimed"] = target.isAimed;
    d["kept"] = target.isKept;
    d["hidden"] = target.isHidden;
    return d;
}

Dictionary tagged(const char *type) {
    Dictionary d;
    d["type"] = type;
    return d;
}

Variant v(const desk::Pie &pie) {
    Dictionary d = tagged("pie");
    d["targets"] = v(pie.targets);
    d["outer"] = v(pie.outer);
    d["stick"] = v(pie.stick);
    d["title"] = text(pie.title);
    d["detail"] = text(pie.detail);
    d["accent"] = v(pie.accent);
    d["compact"] = pie.compact;
    return d;
}

Variant v(const desk::Triggers::Bar &bar) {
    Dictionary d;
    d["name"] = text(bar.name);
    d["value"] = bar.value;
    d["edges"] = v(bar.edges);
    d["tint"] = v(bar.tint);
    return d;
}

Variant v(const desk::Ring::Sector &sector) {
    Dictionary d;
    d["mode"] = text(sector.mode);
    d["bearing"] = sector.bearing;
    d["own"] = sector.isOwn;
    return d;
}

Variant v(const desk::Chips::Chip &chip) {
    Dictionary d;
    d["text"] = text(chip.text);
    d["lit"] = chip.isLit;
    d["empty"] = chip.isEmpty;
    return d;
}

Variant v(const desk::Bar::Mark &mark) {
    Dictionary d;
    d["place"] = mark.place;
    d["tonic"] = mark.isTonic;
    return d;
}

Variant v(const desk::Lanes::GridLine &line) {
    Dictionary d;
    d["place"] = line.place;
    d["beat"] = line.isBeat;
    return d;
}

Variant v(const desk::Lanes::Block &block) {
    Dictionary d;
    d["from"] = block.from;
    d["to"] = block.to;
    d["name"] = text(block.name);
    d["heard"] = block.isHeard;
    return d;
}

Variant v(const desk::Lanes::Lane &lane) {
    Dictionary d;
    d["number"] = lane.number;
    d["lines"] = v(lane.lines);
    d["blocks"] = v(lane.blocks);
    d["writing"] = v(lane.writing);
    d["cursor"] = v(lane.cursor);
    d["playhead"] = v(lane.playhead);
    return d;
}

Variant v(const desk::Diamond::Petal &petal) {
    Dictionary d;
    d["button"] = text(desk::name(petal.button));
    d["held"] = petal.isHeld;
    d["tint"] = v(desk::tint(petal.button));
    d["target"] = v(petal.target);
    return d;
}

Variant item(const desk::Item &item) {
    return std::visit(
        [](const auto &value) -> Variant {
            using T = std::decay_t<decltype(value)>;
            if constexpr (std::is_same_v<T, desk::Caption>) {
                Dictionary d = tagged("caption");
                d["control"] = text(value.control);
                d["title"] = text(value.title);
                d["aside"] = text(value.aside);
                d["aside_tint"] = v(value.asideTint);
                return d;
            } else if constexpr (std::is_same_v<T, desk::Note>) {
                Dictionary d = tagged("note");
                d["text"] = text(value.text);
                d["tint"] = v(value.tint);
                d["strong"] = value.strong;
                d["large"] = value.large;
                return d;
            } else if constexpr (std::is_same_v<T, desk::Pie>) {
                return v(value);
            } else if constexpr (std::is_same_v<T, desk::Pies>) {
                Dictionary d = tagged("pies");
                d["pies"] = v(value.pies);
                return d;
            } else if constexpr (std::is_same_v<T, desk::Ring>) {
                Dictionary d = tagged("ring");
                d["bands"] = v(value.bands);
                d["sectors"] = v(value.sectors);
                d["span"] = value.span;
                d["gap"] = value.gap;
                d["gap_modes"] = text(value.gapModes);
                d["stick"] = v(value.stick);
                d["title"] = text(value.title);
                d["detail"] = text(value.detail);
                return d;
            } else if constexpr (std::is_same_v<T, desk::Triggers>) {
                Dictionary d = tagged("triggers");
                d["bars"] = v(value.bars);
                return d;
            } else if constexpr (std::is_same_v<T, desk::Facts>) {
                Dictionary d = tagged("facts");
                d["facts"] = v(value.facts);
                d["aside"] = text(value.aside);
                return d;
            } else if constexpr (std::is_same_v<T, desk::Choices>) {
                Dictionary d = tagged("choices");
                d["before"] = text(value.before);
                d["names"] = v(value.names);
                d["chosen"] = value.chosen;
                d["after"] = text(value.after);
                d["action"] = value.action ? Variant(name(*value.action)) : Variant();
                return d;
            } else if constexpr (std::is_same_v<T, desk::Sounding>) {
                Dictionary d = tagged("sounding");
                d["sounding"] = value.isSounding;
                d["text"] = text(value.text);
                d["arpeggio"] = text(value.arpeggio);
                return d;
            } else if constexpr (std::is_same_v<T, desk::Voices>) {
                Dictionary d = tagged("voices");
                d["bass"] = v(value.bass);
                d["left"] = v(value.left);
                d["upper"] = v(value.upper);
                return d;
            } else if constexpr (std::is_same_v<T, desk::Diamond>) {
                Dictionary d = tagged("diamond");
                d["petals"] = v(value.petals);
                return d;
            } else if constexpr (std::is_same_v<T, desk::Scale>) {
                Dictionary d = tagged("scale");
                d["targets"] = v(value.targets);
                return d;
            } else if constexpr (std::is_same_v<T, desk::Chips>) {
                Dictionary d = tagged("chips");
                d["chips"] = v(value.chips);
                d["columns"] = value.columns;
                return d;
            } else if constexpr (std::is_same_v<T, desk::Bar>) {
                Dictionary d = tagged("bar");
                d["marks"] = v(value.marks);
                d["pitch"] = v(value.pitch);
                return d;
            } else {
                Dictionary d = tagged("lanes");
                d["lanes"] = v(value.lanes);
                return d;
            }
        },
        item);
}

Variant v(const desk::Panel &panel) {
    Array items;
    for (const auto &each : panel.items) items.push_back(item(each));
    Dictionary d;
    d["items"] = items;
    d["max_width"] = panel.maxWidth;
    return d;
}

Variant v(const desk::Hand::Entry &entry) {
    Dictionary d;
    d["mark"] = text(entry.mark);
    d["text"] = text(entry.text);
    d["key"] = text(entry.key);
    d["held"] = entry.isHeld;
    d["tint"] = v(entry.tint);
    return d;
}

Variant v(const desk::FavoritesView::Table &table) {
    Dictionary d;
    d["name"] = text(table.name);
    d["active"] = table.isActive;
    d["default"] = table.isDefault;
    d["count"] = table.count;
    return d;
}

Variant v(const desk::FavoritesView::Degree &degree) {
    Dictionary d;
    d["numeral"] = text(degree.numeral);
    d["pinned"] = v(degree.pinned);
    return d;
}

Variant v(const desk::MenuView::Row &row) {
    Dictionary d;
    d["name"] = text(row.name);
    d["value"] = text(row.value);
    d["chosen"] = row.isChosen;
    d["changes"] = row.changes;
    return d;
}

Variant v(const desk::MenuView::Library::Category &category) {
    Array sounds;
    for (const auto &[sound, chosen] : category.sounds) {
        Dictionary s;
        s["name"] = text(sound);
        s["chosen"] = chosen;
        sounds.push_back(s);
    }
    Dictionary d;
    d["name"] = text(category.name);
    d["lit"] = category.isLit;
    d["sounds"] = sounds;
    return d;
}

Variant v(const desk::MenuView &menu) {
    Dictionary d;
    d["rows"] = v(menu.rows);
    if (menu.library) {
        Dictionary library;
        library["line"] = text(menu.library->line);
        library["categories"] = v(menu.library->categories);
        d["library"] = library;
    } else {
        d["library"] = Variant();
    }
    return d;
}

} // namespace

Dictionary sceneVariant(const desk::Scene &scene) {
    Dictionary top;
    top["layouts"] = v(scene.top.layouts);
    top["chosen"] = scene.top.chosen;
    top["summary"] = text(scene.top.summary);
    top["guard"] = scene.top.guard ? v(*scene.top.guard) : Variant();
    top["facts"] = v(scene.top.facts);

    Dictionary hand;
    hand["caption"] = text(scene.hand.caption);
    hand["left"] = v(scene.hand.left);
    hand["right"] = v(scene.hand.right);

    const auto &f = scene.favorites;
    Dictionary favorites;
    favorites["tables"] = v(f.tables);
    favorites["can_remove"] = f.canRemove;
    favorites["key_default"] = text(f.keyDefault);
    favorites["is_key_default"] = f.isKeyDefault;
    favorites["pinned_caption"] = text(f.pinnedCaption);
    favorites["pinned_title"] = text(f.pinnedTitle);
    favorites["pin"] = text(f.pin);
    favorites["can_pin"] = f.canPin;
    favorites["degrees"] = v(f.degrees);
    favorites["help"] = text(f.help);

    Dictionary d;
    d["top"] = top;
    d["stage"] = v(scene.stage);
    d["hand"] = hand;
    d["favorites"] = favorites;
    d["menu"] = scene.menu ? v(*scene.menu) : Variant();
    return d;
}

std::optional<desk::Action> actionOf(const Dictionary &dictionary) {
    const String kind = dictionary.get("kind", "");
    for (const auto &[k, n] : actionNames)
        if (kind == String(n.data())) {
            desk::Action action{k};
            action.index = int(dictionary.get("index", 0));
            action.value = int(dictionary.get("value", 0));
            action.text = String(dictionary.get("text", "")).utf8().get_data();
            return action;
        }
    return std::nullopt;
}

} // namespace perfecto_godot
