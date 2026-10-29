// Favorite colorations: colors pinned to the chords of a key, kept in named
// tables ("Jazz", "Pop", "Film"). One table is the one played, and a table
// can be a key's default, so playing in that key turns to it.

#ifndef PERFECTO_DESK_FAVORITES_HPP
#define PERFECTO_DESK_FAVORITES_HPP

#include <perfecto/theory/chord_color.hpp>
#include <perfecto/theory/key.hpp>

#include <optional>
#include <string>
#include <vector>

namespace perfecto::desk {

struct DeskChord;

/// The colors pinned to one chord of one key.
struct Pin {
    theory::Key key;
    theory::Degree degree;
    std::vector<theory::ChordColor> colors;

    bool operator==(const Pin &) const = default;
};

/// A named table of favorites.
struct FavoriteTable {
    std::string name;
    std::vector<Pin> pins;

    bool operator==(const FavoriteTable &) const = default;

    /// The colors pinned to `degree` in `key`, in the order they were pinned.
    std::vector<theory::ChordColor> colors(const theory::Key &key, theory::Degree degree) const;
};

/// Every table, the one played, and the keys that have a table of their own.
class Favorites {
public:
    /// The most colors a chord holds: as many as a stick's eight directions.
    static constexpr int perChord = 8;

    struct KeyDefault {
        theory::Key key;
        std::string table;
        bool operator==(const KeyDefault &) const = default;
    };

    /// Where a chord is pinned: its degree, and the color that plays it there.
    struct Place {
        theory::Degree degree;
        theory::ChordColor color;
        bool operator==(const Place &) const = default;
    };

    bool operator==(const Favorites &) const = default;

    const std::vector<FavoriteTable> &tables() const { return tables_; }
    /// The table played, an index of `tables`.
    int active() const { return active_; }
    /// Each key's own table, by its name.
    const std::vector<KeyDefault> &defaults() const { return defaults_; }

    const FavoriteTable &table() const { return tables_[static_cast<size_t>(active_)]; }

    /// The favorites of `degree` in `key` in the table played.
    std::vector<theory::ChordColor> colors(const theory::Key &key, theory::Degree degree) const;

    /// Where `chord` is pinned in `home`: its degree there, and the color
    /// that plays it there. A chord borrowed from another key is pinned by
    /// its tones, so it plays the same; a borrowed root, which has no degree
    /// in the key, cannot be pinned. (Swift's static `pin(of:in:)`.)
    static std::optional<Place> pinOf(const DeskChord &chord, const theory::Key &home);

    /// Pins `chord` to its degree of `home` in the table played. Returns
    /// whether it was pinned: not if it is there already, or the chord's
    /// favorites are full, or it cannot be pinned.
    bool pin(const DeskChord &chord, const theory::Key &home);

    /// Takes the favorite at `index` of `degree` in `key` out of the table played.
    void unpin(const theory::Key &key, theory::Degree degree, int index);

    // The tables

    /// Adds a table called `name` (made unique) and plays it.
    void addTable(const std::string &name);

    void rename(int index, const std::string &name);

    /// Takes the table at `index` away; there is always one left.
    void removeTable(int index);

    void play(int index);

    /// The table played the next one along (`steps` < 0, the one before).
    void playNext(int steps);

    /// The table that is `key`'s own, if one is.
    std::optional<std::string> defaultTable(const theory::Key &key) const;

    /// Makes the table played `key`'s own, or with `isOn` false, leaves the
    /// key without one.
    void setDefault(const theory::Key &key, bool isOn);

    /// The key is now `key`: its own table is played, if it has one.
    void keyChanged(const theory::Key &key);

private:
    std::vector<FavoriteTable> tables_ = {FavoriteTable{"Favorites", {}}};
    int active_ = 0;
    std::vector<KeyDefault> defaults_;

    std::string unique(const std::string &name, std::optional<int> except = std::nullopt) const;
};

} // namespace perfecto::desk

#endif
