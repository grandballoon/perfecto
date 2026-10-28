import Foundation
import MusicTheoryCore
import Testing
@testable import DeskCore

@Suite("The ring's arrangements")
struct RingTests {

    private let c = Key(root: .C, scale: .major)
    private let span = RingPie.sectorSpan

    private func bearing(of mode: HeptatonicMode, _ pie: RingPie) -> Double? {
        pie.sectors.first { $0.mode == mode }?.bearing
    }

    @Test func homePutsTheOwnModeOnTopAndTheGapWhereTheEndsAre() {
        let pie = RingPie(.home, key: c, degree: .I)
        #expect(bearing(of: .ionian, pie) == 0)
        #expect(bearing(of: .lydian, pie) == span)
        #expect(bearing(of: .locrian, pie) == -5 * span)
        // On I the ring is lopsided: one brighter, five darker, the gap on the right.
        #expect(abs(pie.gap - (180 - 2 * span)) < 0.001)
        #expect(RingPie(.home, key: c, degree: .ii).gap == 180)
    }

    @Test func fixedNeverTurns() {
        for degree in Degree.allCases {
            let pie = RingPie(.fixed, key: c, degree: degree)
            #expect(bearing(of: .dorian, pie) == 0)
            #expect(pie.gap == 180)
        }
        #expect(RingPie(.fixed, key: c, degree: .I).sectors.first { $0.isOwn }?.mode == .ionian)
        #expect(bearing(of: .ionian, RingPie(.fixed, key: c, degree: .I)) == 2 * span)
    }

    @Test func centredPutsTheOwnModeOnTopAmongItsNearestInBrightness() {
        for degree in Degree.allCases {
            let pie = RingPie(.centred, key: c, degree: degree)
            #expect(pie.sectors.first { $0.isOwn }?.bearing == 0)
            let sums = pie.sectors.map { $0.mode.intervals.reduce(0, +) }
            #expect(sums == sums.sorted())
        }
        // Dorian is in the middle of the brightness order: three either side.
        let ii = RingPie(.centred, key: c, degree: .ii)
        #expect(ii.sectors.map(\.bearing) == (-3...3).map { Double($0) * span })
        // I is near the bright end, but is balanced better than at home.
        let i = RingPie(.centred, key: c, degree: .I)
        #expect(i.sectors.filter { $0.bearing > 0 }.count >= 2)
    }

    @Test func aCellPlaysTheSameChordWhicheverWayTheRingIsTurned() {
        let cell = RingCell(mode: .mixolydian, height: .seventh)
        let chords = RingArrangement.allCases.map {
            DeskChord(key: c, degree: .I, color: RingPie($0, key: c, degree: .I).color(of: cell)).name
        }
        #expect(chords == ["C 7", "C 7", "C 7"])
    }

    @Test func theStickFindsTheModeWhereTheArrangementPutsIt() {
        var rig = Rig(TwinRings())
        rig.settings.ringArrangement = .fixed
        // Fixed: Mixolydian is one sector clockwise of Dorian.
        rig.at(1) { $0.right = lean(span, 0.6) }
        #expect(rig.layout.chord(rig.settings).name == "C 7")
    }

    @Test func l3TurnsTheRingAndTheKeptColorStays() {
        var rig = Rig(TwinRings())
        rig.at(1) { $0.right = lean(-span, 0.6) }
        rig.at(1.1) { $0.right = .rest }
        #expect(rig.layout.chord(rig.settings).name == "C 7")
        rig.at(2) { $0.buttons = [.l3] }
        #expect(rig.settings.ringArrangement == .fixed)
        #expect(rig.layout.chord(rig.settings).name == "C 7")
        rig.at(2.1) { $0.buttons = [] }
        rig.at(3) { $0.buttons = [.l3] }
        rig.at(3.1) { $0.buttons = [] }
        rig.at(4) { $0.buttons = [.l3] }
        #expect(rig.settings.ringArrangement == .home)
    }

    @Test func petalsDepthFollowsTheArrangement() {
        var rig = Rig(Petals())
        rig.settings.ringArrangement = .centred
        // Pulled all the way, RT is three brighter: past Lydian, centred borrows.
        rig.at(1) { $0.rightTrigger = 1 }
        let mode = rig.settings.ring(.I).mode(steps: rig.layout.shift)
        #expect(mode != .lydian)
        #expect(mode.intervals.reduce(0, +) >= HeptatonicMode.lydian.intervals.reduce(0, +))
    }

    @Test func settingsKeptBeforeTheRingWasASettingStillLoad() throws {
        var old = DeskSettings()
        old.tempo = 120
        old.key = Key(root: .D, scale: .dorian)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        json.removeValue(forKey: "ringArrangement")
        let loaded = try JSONDecoder().decode(DeskSettings.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(loaded.tempo == 120)
        #expect(loaded.key == old.key)
        #expect(loaded.ringArrangement == .home)
    }
}

@Suite("The ring's orders and filters")
struct RingOrderTests {

    private let c = Key(root: .C, scale: .major)

    /// Each mode's place, in sectors clockwise from the top.
    private func places(_ order: RingOrder, _ arrangement: RingArrangement = .home, degree: Degree = .I,
                        near: DeskChord? = nil) -> [HeptatonicMode: Int] {
        let pie = RingPie(arrangement, order: order, key: c, degree: degree, near: near)
        return Dictionary(uniqueKeysWithValues: pie.sectors.map { ($0.mode, Int(($0.bearing / RingPie.sectorSpan).rounded())) })
    }

    @Test func characterPutsRaisedNotesClockwiseAndLoweredAnticlockwise() {
        let ring = places(.character)
        #expect(ring[.ionian] == 0)
        #expect(ring[.dorian] == 1 && ring[.lydian] == 2)
        #expect(ring[.aeolian] == -1 && ring[.mixolydian] == -2 && ring[.phrygian] == -3 && ring[.locrian] == -4)
    }

    @Test func qualityPutsMajorThirdsOnOneSideAndMinorOnTheOther() {
        let pie = RingPie(.fixed, order: .quality, key: c, degree: .I)
        for sector in pie.sectors {
            if sector.mode.intervals.contains(4) { #expect(sector.bearing > 0) }
            if sector.mode.intervals.contains(3) && sector.mode.intervals.contains(7) { #expect(sector.bearing < 0) }
        }
        // Each side's brightest is by the seam at the top.
        #expect(pie.sectors.min { abs($0.bearing) < abs($1.bearing) }.map { [$0.mode] } == [.dorian]
            || pie.sectors.min { abs($0.bearing) < abs($1.bearing) }.map { [$0.mode] } == [.lydian])
    }

    @Test func fewestBorrowedFansOutFromTheKeysOwn() {
        let ring = places(.borrowed)
        #expect(ring[.ionian] == 0)
        // One note borrowed either side, the brighter clockwise.
        #expect(ring[.lydian] == 1 && ring[.mixolydian] == -1)
        #expect(ring[.dorian] == 2 && ring[.aeolian] == -2)
        #expect(ring[.phrygian] == 3 && ring[.locrian] == -3)
    }

    @Test func commonFirstKeepsIonianOnTopWhenFixed() {
        for degree in Degree.allCases {
            #expect(places(.common, .fixed, degree: degree)[.ionian] == 0)
        }
        // At home, the degree's own mode is on top.
        #expect(places(.common, degree: .ii)[.dorian] == 0)
    }

    @Test func nearestTurnsToTheChordStruck() {
        let seventh = DeskChord(key: c, degree: .I, color: .grid(.seventh, .mixolydian))
        #expect(places(.nearness, near: seventh)[.mixolydian] == 0)
        #expect(places(.nearness)[.ionian] == 0)
    }

    @Test func aFilterLeavesCellsInPlaceButOutOfReach() {
        let pie = RingPie(.home, filter: .inKey, key: c, degree: .I)
        #expect(pie.allows(RingCell(mode: .lydian, height: .seventh)))
        #expect(!pie.allows(RingCell(mode: .lydian, height: .eleventh)))
        #expect(!pie.allows(RingCell(mode: .mixolydian, height: .seventh)))
        let reachable = pie.gate(extended: false).sectors.map { pie.sectors[$0].mode }
        #expect(reachable == [.ionian, .lydian])
        // The sectors keep their places.
        #expect(pie.sectors.map(\.bearing) == RingPie(.home, key: c, degree: .I).sectors.map(\.bearing))
        // Dorian, Aeolian, Phrygian and Locrian have a minor third.
        #expect(RingPie(.home, filter: .minorThird, key: c, degree: .I).gate(extended: false).sectors.count == 4)
    }

    @Test func aStickCannotReachAFilteredSector() {
        var rig = Rig(TwinRings())
        rig.settings.ringFilter = .inKey
        // Where Mixolydian is, darker than Ionian: out of reach, so the chord stays plain.
        rig.at(1) { $0.right = lean(-RingPie.sectorSpan, 0.6) }
        #expect(rig.layout.chord(rig.settings).name == "C maj")
        rig.at(2) { $0.right = lean(RingPie.sectorSpan, 0.6) }
        #expect(rig.layout.chord(rig.settings).name == "C maj7")
    }

    @Test func petalsStepsByBrightnessWhateverTheOrder() {
        var rig = Rig(Petals())
        rig.settings.ringOrder = .common
        rig.at(1) { $0.leftTrigger = 0.3 }
        #expect(rig.layout.chord(.height(.seventh), rig.settings).name == "C 7")
    }
}
