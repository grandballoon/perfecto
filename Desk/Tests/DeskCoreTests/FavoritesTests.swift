import Foundation
import MusicTheoryCore
import Testing
@testable import DeskCore

@Suite("Favorites")
struct FavoritesTests {

    private let c = Key(root: .C, scale: .major)
    private let g = Key(root: .G, scale: .major)
    private let span = RingPie.sectorSpan

    @Test func aPinIsKeptByKeyAndChord() {
        var favorites = Favorites()
        let seventh = DeskChord(key: c, degree: .V, color: .grid(.seventh, nil))
        let pinned1 = favorites.pin(seventh, in: c)
        #expect(pinned1)
        // The same color again, or another key's, is not the same pin.
        let pinned2 = favorites.pin(seventh, in: c)
        #expect(!pinned2)
        #expect(favorites.colors(c, .V) == [.grid(.seventh, nil)])
        #expect(favorites.colors(g, .V).isEmpty)
        favorites.unpin(c, .V, at: 0)
        #expect(favorites.colors(c, .V).isEmpty)
        #expect(favorites.table.pins.isEmpty)
    }

    @Test func aBorrowedChordIsPinnedByItsTones() {
        var favorites = Favorites()
        // E♭ major, borrowed into C, has no degree there: it cannot be pinned.
        let pinned3 = favorites.pin(DeskChord(root: .Ds, tones: ChordTones([0, 4, 7]), in: c), in: c)
        #expect(!pinned3)
        // C minor on I is pinned to I by its notes.
        let minor = DeskChord(root: .C, tones: ChordTones([0, 3, 7]), in: c)
        let pinned4 = favorites.pin(minor, in: c)
        #expect(pinned4)
        #expect(DeskChord(key: c, degree: .I, color: favorites.colors(c, .I)[0]).name == "C min")
    }

    @Test func aChordHoldsEightAtMost() {
        var favorites = Favorites()
        let heights: [StackHeight] = [.triad, .seventh, .ninth, .eleventh, .thirteenth]
        let modes: [HeptatonicMode?] = [nil, .lydian]
        for height in heights { for mode in modes { favorites.pin(DeskChord(key: c, degree: .I, color: .grid(height, mode)), in: c) } }
        #expect(favorites.colors(c, .I).count == Favorites.perChord)
    }

    @Test func tablesAreNamedAndOneIsPlayed() {
        var favorites = Favorites()
        favorites.pin(DeskChord(key: c, degree: .I, color: .grid(.seventh, nil)), in: c)
        favorites.addTable(named: "Jazz")
        favorites.addTable(named: "Jazz")
        #expect(favorites.tables.map(\.name) == ["Favorites", "Jazz", "Jazz 2"])
        #expect(favorites.table.name == "Jazz 2")
        #expect(favorites.colors(c, .I).isEmpty)
        favorites.play(0)
        #expect(favorites.colors(c, .I).count == 1)
        favorites.removeTable(0)
        #expect(favorites.tables.map(\.name) == ["Jazz", "Jazz 2"])
        favorites.removeTable(0)
        favorites.removeTable(0)
        #expect(favorites.tables.count == 1)
    }

    @Test func aKeyCanHaveATableOfItsOwn() {
        var favorites = Favorites()
        favorites.addTable(named: "Bright")
        favorites.setDefault(for: g, true)
        favorites.play(0)
        favorites.keyChanged(to: c)
        #expect(favorites.table.name == "Favorites")
        favorites.keyChanged(to: g)
        #expect(favorites.table.name == "Bright")
        favorites.rename(1, to: "Sunny")
        #expect(favorites.defaultTable(for: g) == "Sunny")
    }

    @Test func yAPinsAndYHeldPlaysTheFavorites() {
        var rig = Rig(TwinRings())
        // Flick to keep the Mixolydian 7th (the right thumb cannot lean and
        // press Y at once), then pin it with Y + A.
        rig.at(1) { $0.right = lean(-span, 0.6) }
        rig.at(1.1) { $0.right = .rest }
        rig.at(1.5) { $0.buttons = [.y] }
        rig.at(1.6) { $0.buttons = [.y, .a] }
        #expect(rig.settings.favorites.colors(rig.settings.key, .I) == [.grid(.seventh, .mixolydian)])
        // Pinning was no tap: hold has not changed.
        rig.at(1.7) { $0.buttons = [] }
        #expect(!rig.layout.holds)
        // Back to the plain color.
        rig.at(1.8) { $0.buttons = [.r3] }
        rig.at(1.9) { $0.buttons = [] }
        #expect(rig.layout.chord(rig.settings).name == "C maj")
        // Y held, the right stick up is the first favorite; a flick keeps it.
        rig.at(2) { $0.buttons = [.y] }
        rig.at(2.1) { $0.right = lean(0) }
        rig.at(2.2) { $0.right = .rest }
        rig.at(2.3) { $0.buttons = [] }
        #expect(rig.layout.chord(rig.settings).name == "C 7")
    }

    @Test func aTapOfYStillHolds() {
        var rig = Rig(TwinRings())
        rig.at(1) { $0.buttons = [.y] }
        rig.at(1.1) { $0.buttons = [] }
        #expect(rig.layout.holds)
    }

    @Test func yXUnpinsTheFavoriteAimedAt() {
        var rig = Rig(TwinRings())
        rig.settings.favorites.pin(DeskChord(key: rig.settings.key, degree: .I, color: .grid(.ninth, nil)), in: rig.settings.key)
        rig.at(1) { $0.buttons = [.y] }
        rig.at(1.1) { $0.right = lean(0) }
        rig.at(1.2) { $0.buttons = [.y, .x] }
        #expect(rig.settings.favorites.colors(rig.settings.key, .I).isEmpty)
    }

    @Test func aKeyChangedTurnsToItsTable() {
        var desk = Desk(catalog: SoundCatalog([]))
        desk.settings.favorites.addTable(named: "G's")
        desk.settings.favorites.setDefault(for: g, true)
        desk.settings.favorites.play(0)
        // A tap of RB in Twin Rings moves the key a fifth up, to G.
        _ = desk.step(GamepadFrame(time: 1, buttons: [.rb]))
        _ = desk.step(GamepadFrame(time: 1.1))
        #expect(desk.settings.key == g)
        #expect(desk.settings.favorites.table.name == "G's")
    }

    @Test func favoritesAreKeptWithTheSettings() throws {
        var settings = DeskSettings()
        settings.favorites.pin(DeskChord(key: c, degree: .ii, color: .grid(.ninth, nil)), in: c)
        let kept = try JSONDecoder().decode(DeskSettings.self, from: JSONEncoder().encode(settings))
        #expect(kept.favorites == settings.favorites)
    }
}
