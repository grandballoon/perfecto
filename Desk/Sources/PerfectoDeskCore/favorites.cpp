#include "perfecto/desk/favorites.hpp"

#include "perfecto/desk/music.hpp"

#include <algorithm>
#include <set>

namespace perfecto::desk {

using namespace theory;

std::vector<ChordColor> FavoriteTable::colors(const Key &key, Degree degree) const {
    for (const Pin &pin : pins)
        if (pin.key == key && pin.degree == degree) return pin.colors;
    return {};
}

std::vector<ChordColor> Favorites::colors(const Key &key, Degree degree) const { return table().colors(key, degree); }

std::optional<Favorites::Place> Favorites::pinOf(const DeskChord &chord, const Key &home) {
    if (chord.key == home) return Place{chord.spec.degree, chord.spec.color};
    const auto degree = home.degreeOf(chord.root());
    if (!degree) return std::nullopt;
    return Place{*degree, ChordColor::tones(chord.tones())};
}

bool Favorites::pin(const DeskChord &chord, const Key &home) {
    const auto place = pinOf(chord, home);
    if (!place) return false;
    FavoriteTable table = tables_[static_cast<size_t>(active_)];
    const auto at = std::find_if(table.pins.begin(), table.pins.end(),
                                 [&](const Pin &pin) { return pin.key == home && pin.degree == place->degree; });
    if (at != table.pins.end()) {
        if (std::find(at->colors.begin(), at->colors.end(), place->color) != at->colors.end() ||
            !(static_cast<int>(at->colors.size()) < perChord))
            return false;
        at->colors.push_back(place->color);
    } else {
        table.pins.push_back(Pin{home, place->degree, {place->color}});
    }
    tables_[static_cast<size_t>(active_)] = std::move(table);
    return true;
}

void Favorites::unpin(const Key &key, Degree degree, int index) {
    auto &pins = tables_[static_cast<size_t>(active_)].pins;
    const auto at =
        std::find_if(pins.begin(), pins.end(), [&](const Pin &pin) { return pin.key == key && pin.degree == degree; });
    if (at == pins.end() || index < 0 || index >= static_cast<int>(at->colors.size())) return;
    at->colors.erase(at->colors.begin() + index);
    if (at->colors.empty()) pins.erase(at);
}

void Favorites::addTable(const std::string &name) {
    tables_.push_back(FavoriteTable{unique(name), {}});
    active_ = static_cast<int>(tables_.size()) - 1;
}

void Favorites::rename(int index, const std::string &name) {
    if (index < 0 || index >= static_cast<int>(tables_.size())) return;
    const std::string old = tables_[static_cast<size_t>(index)].name;
    const std::string renamed = unique(name, index);
    tables_[static_cast<size_t>(index)].name = renamed;
    for (KeyDefault &entry : defaults_)
        if (entry.table == old) entry = KeyDefault{entry.key, renamed};
}

void Favorites::removeTable(int index) {
    if (tables_.size() <= 1 || index < 0 || index >= static_cast<int>(tables_.size())) return;
    const std::string name = tables_[static_cast<size_t>(index)].name;
    tables_.erase(tables_.begin() + index);
    std::erase_if(defaults_, [&](const KeyDefault &entry) { return entry.table == name; });
    if (active_ >= index) active_ = std::max(0, active_ - 1);
}

void Favorites::play(int index) {
    if (index >= 0 && index < static_cast<int>(tables_.size())) active_ = index;
}

void Favorites::playNext(int steps) {
    const int count = static_cast<int>(tables_.size());
    active_ = ((active_ + steps) % count + count) % count;
}

std::optional<std::string> Favorites::defaultTable(const Key &key) const {
    for (const KeyDefault &entry : defaults_)
        if (entry.key == key) return entry.table;
    return std::nullopt;
}

void Favorites::setDefault(const Key &key, bool isOn) {
    std::erase_if(defaults_, [&](const KeyDefault &entry) { return entry.key == key; });
    if (isOn) defaults_.push_back(KeyDefault{key, table().name});
}

void Favorites::keyChanged(const Key &key) {
    const auto name = defaultTable(key);
    if (!name) return;
    const auto found = std::find_if(tables_.begin(), tables_.end(),
                                    [&](const FavoriteTable &table) { return table.name == *name; });
    if (found != tables_.end()) active_ = static_cast<int>(found - tables_.begin());
}

std::string Favorites::unique(const std::string &name, std::optional<int> except) const {
    const std::string base = name.empty() ? "Table" : name;
    std::set<std::string> taken;
    for (size_t i = 0; i < tables_.size(); ++i)
        if (!except || static_cast<int>(i) != *except) taken.insert(tables_[i].name);
    std::string candidate = base;
    int number = 2;
    while (taken.contains(candidate)) {
        candidate = base + " " + std::to_string(number);
        number += 1;
    }
    return candidate;
}

} // namespace perfecto::desk
