import MusicTheoryCore

// Favorite colorations: colors pinned to the chords of a key, kept in named
// tables ("Jazz", "Pop", "Film"). One table is the one played, and a table
// can be a key's default, so playing in that key turns to it.

/// The colors pinned to one chord of one key.
public struct Pin: Codable, Equatable, Sendable {
    public let key: Key
    public let degree: Degree
    public internal(set) var colors: [ChordColor]
}

/// A named table of favorites.
public struct FavoriteTable: Codable, Equatable, Sendable {
    public internal(set) var name: String
    public internal(set) var pins: [Pin]

    public init(name: String, pins: [Pin] = []) {
        self.name = name
        self.pins = pins
    }

    /// The colors pinned to `degree` in `key`, in the order they were pinned.
    public func colors(_ key: Key, _ degree: Degree) -> [ChordColor] {
        pins.first { $0.key == key && $0.degree == degree }?.colors ?? []
    }
}

/// Every table, the one played, and the keys that have a table of their own.
public struct Favorites: Codable, Equatable, Sendable {
    /// The most colors a chord holds: as many as a stick's eight directions.
    public static let perChord = 8

    public private(set) var tables = [FavoriteTable(name: "Favorites")]
    /// The table played, an index of `tables`.
    public private(set) var active = 0
    /// Each key's own table, by its name.
    public private(set) var defaults: [KeyDefault] = []

    public struct KeyDefault: Codable, Equatable, Sendable {
        public let key: Key
        public let table: String
    }

    public init() {}

    public var table: FavoriteTable { tables[active] }

    /// The favorites of `degree` in `key` in the table played.
    public func colors(_ key: Key, _ degree: Degree) -> [ChordColor] {
        table.colors(key, degree)
    }

    /// Where `chord` is pinned in `home`: its degree there, and the color
    /// that plays it there. A chord borrowed from another key is pinned by
    /// its tones, so it plays the same; a borrowed root, which has no degree
    /// in the key, cannot be pinned.
    public static func pin(of chord: DeskChord, in home: Key) -> (degree: Degree, color: ChordColor)? {
        if chord.key == home { return (chord.spec.degree, chord.spec.color) }
        guard let degree = home.degree(of: chord.root) else { return nil }
        return (degree, .tones(chord.tones))
    }

    /// Pins `chord` to its degree of `home` in the table played. Returns
    /// whether it was pinned: not if it is there already, or the chord's
    /// favorites are full, or it cannot be pinned.
    @discardableResult
    public mutating func pin(_ chord: DeskChord, in home: Key) -> Bool {
        guard let (degree, color) = Self.pin(of: chord, in: home) else { return false }
        var table = tables[active]
        if let at = table.pins.firstIndex(where: { $0.key == home && $0.degree == degree }) {
            guard !table.pins[at].colors.contains(color), table.pins[at].colors.count < Self.perChord else { return false }
            table.pins[at].colors.append(color)
        } else {
            table.pins.append(Pin(key: home, degree: degree, colors: [color]))
        }
        tables[active] = table
        return true
    }

    /// Takes the favorite at `index` of `degree` in `key` out of the table played.
    public mutating func unpin(_ key: Key, _ degree: Degree, at index: Int) {
        guard let at = tables[active].pins.firstIndex(where: { $0.key == key && $0.degree == degree }),
              tables[active].pins[at].colors.indices.contains(index) else { return }
        tables[active].pins[at].colors.remove(at: index)
        if tables[active].pins[at].colors.isEmpty { tables[active].pins.remove(at: at) }
    }

    // MARK: – The tables

    /// Adds a table called `name` (made unique) and plays it.
    public mutating func addTable(named name: String) {
        tables.append(FavoriteTable(name: unique(name)))
        active = tables.count - 1
    }

    public mutating func rename(_ index: Int, to name: String) {
        guard tables.indices.contains(index) else { return }
        let old = tables[index].name
        let new = unique(name, except: index)
        tables[index].name = new
        defaults = defaults.map { $0.table == old ? KeyDefault(key: $0.key, table: new) : $0 }
    }

    /// Takes the table at `index` away; there is always one left.
    public mutating func removeTable(_ index: Int) {
        guard tables.count > 1, tables.indices.contains(index) else { return }
        let name = tables[index].name
        tables.remove(at: index)
        defaults.removeAll { $0.table == name }
        if active >= index { active = max(0, active - 1) }
    }

    public mutating func play(_ index: Int) {
        if tables.indices.contains(index) { active = index }
    }

    /// The table played the next one along (`steps` < 0, the one before).
    public mutating func playNext(_ steps: Int) {
        active = ((active + steps) % tables.count + tables.count) % tables.count
    }

    /// The table that is `key`'s own, if one is.
    public func defaultTable(for key: Key) -> String? {
        defaults.first { $0.key == key }?.table
    }

    /// Makes the table played `key`'s own, or with `isOn` false, leaves the
    /// key without one.
    public mutating func setDefault(for key: Key, _ isOn: Bool) {
        defaults.removeAll { $0.key == key }
        if isOn { defaults.append(KeyDefault(key: key, table: table.name)) }
    }

    /// The key is now `key`: its own table is played, if it has one.
    public mutating func keyChanged(to key: Key) {
        if let name = defaultTable(for: key), let index = tables.firstIndex(where: { $0.name == name }) {
            active = index
        }
    }

    private func unique(_ name: String, except index: Int? = nil) -> String {
        let base = name.isEmpty ? "Table" : name
        let taken = Set(tables.indices.filter { $0 != index }.map { tables[$0].name })
        var candidate = base
        var number = 2
        while taken.contains(candidate) {
            candidate = "\(base) \(number)"
            number += 1
        }
        return candidate
    }
}
