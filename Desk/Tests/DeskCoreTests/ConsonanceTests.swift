import Foundation
import MusicTheoryCore
import Testing
@testable import DeskCore

@Suite("The consonance guard")
struct ConsonanceTests {

    private let c = Key(root: .C, scale: .major)

    private func chord(_ root: PitchClass, _ tones: [Int]) -> DeskChord {
        DeskChord(root: root, tones: ChordTones(tones), in: c)
    }

    private func guarded(_ mode: GuardMode, heard chords: [[Int]] = []) -> ConsonanceGuard {
        var consonance = ConsonanceGuard()
        consonance.mode = mode
        consonance.hear(chords.map { .sound(.chord, notes: $0, sound: "", level: 1, brightness: 1, tie: false) })
        return consonance
    }

    @Test func offPlaysEverything() {
        #expect(guarded(.off).allows(chord(.C, [0, 1, 4]), in: c))
    }

    @Test func alwaysPlaysTheConsonantQualitiesOnly() {
        let always = guarded(.always)
        #expect(always.allows(chord(.C, [0, 4, 7]), in: c))
        #expect(always.allows(chord(.G, [0, 4, 7, 10, 2]), in: c))
        #expect(always.refusal(of: chord(.C, [0, 1, 4]), in: c) != nil)
        // A borrowed chord is consonant, unless the key's notes alone are asked for.
        #expect(always.allows(chord(.C, [0, 3, 7]), in: c))
        var inKey = always
        inKey.inKey = true
        #expect(inKey.refusal(of: chord(.C, [0, 3, 7]), in: c) == "C min is outside the key")
        // A line's note must be the key's.
        #expect(always.allows(note: 62, in: c))
        #expect(!always.allows(note: 61, in: c))
    }

    @Test func withWhatIsSoundingAChordMustShareANoteAndANoteMustSitInTheChord() {
        let sounding = guarded(.sounding, heard: [[60, 64, 67]])
        #expect(sounding.allows(chord(.A, [0, 3, 7]), in: c))
        #expect(sounding.refusal(of: chord(.Fs, [0, 4, 7]), in: c) == "F# maj shares no note with what is sounding")
        // D over C major is an added 9th; C♯ is a clash.
        #expect(sounding.allows(note: 62, in: c))
        #expect(sounding.refusal(ofNote: 61, in: c) == "C# clashes with the chord")
        // With nothing sounding, nothing is near or far.
        var silent = sounding
        silent.hear([.silence(.chord)])
        #expect(silent.allows(chord(.Fs, [0, 4, 7]), in: c))
    }

    @Test func withTheRunAChordBringsOneNewNoteAtMost() {
        let run = guarded(.run, heard: [[60, 64, 67], [65, 69, 72], [67, 71, 74]])
        #expect(run.pool == [0, 2, 4, 5, 7, 9, 11])
        #expect(run.allows(chord(.G, [0, 4, 7, 10]), in: c))
        // B♭ alone is one step out; E♭ major brings E♭ and B♭.
        #expect(run.allows(chord(.C, [0, 4, 7, 10]), in: c))
        #expect(run.refusal(of: chord(.Ds, [0, 4, 7]), in: c) == "D# maj is outside the run")
        #expect(!run.allows(note: 63, in: c))
        // Nothing heard, nothing is outside.
        #expect(guarded(.run).allows(chord(.Ds, [0, 4, 7]), in: c))
    }

    @Test func theRunRemembersTheLastFewChords() {
        let chords = (0..<8).map { [48 + $0, 52 + $0, 55 + $0] }
        let run = guarded(.run, heard: chords)
        #expect(run.recent.count == ConsonanceGuard.window)
        // The first two are forgotten: the oldest remembered is the third, D major.
        #expect(run.recent.first == [2, 6, 9])
    }

    @Test func onlyTheModeIsKept() throws {
        var settings = DeskSettings()
        settings.consonance = guarded(.run, heard: [[60, 64, 67]])
        settings.consonance.inKey = true
        let kept = try JSONDecoder().decode(DeskSettings.self, from: JSONEncoder().encode(settings))
        #expect(kept.consonance.mode == .run)
        #expect(kept.consonance.inKey)
        #expect(kept.consonance.recent.isEmpty)
    }

    @Test func aDegreeOutsideTheRunIsNotChosen() {
        var desk = Desk(catalog: SoundCatalog([]))
        desk.settings.consonance.mode = .run
        // Strike C major: the run is C E G.
        _ = desk.step(GamepadFrame(time: 1, buttons: [.a]))
        _ = desk.step(GamepadFrame(time: 1.1))
        // V, G major, brings B and D, two new notes: the stick leaves I chosen.
        _ = desk.step(GamepadFrame(time: 2, left: lean(2 * 360 / 7)))
        #expect(desk.twinRings.degree == .I)
        // iii, E minor, brings only B.
        _ = desk.step(GamepadFrame(time: 3, left: lean(360 / 7)))
        let played = desk.step(GamepadFrame(time: 3.2, left: .rest, buttons: [.a]))
        #expect(sounded(played) == [[64, 67, 71]])
    }

    @Test func aStrikeOutsideTheRunIsRefusedAndSaysWhy() {
        var desk = Desk(catalog: SoundCatalog([]))
        // The run is heard while the guard is off, too.
        _ = desk.step(GamepadFrame(time: 1, buttons: [.a]))
        _ = desk.step(GamepadFrame(time: 1.1))
        _ = desk.step(GamepadFrame(time: 2, left: lean(2 * 360 / 7)))
        _ = desk.step(GamepadFrame(time: 2.1))
        desk.settings.consonance.mode = .run
        let refused = desk.step(GamepadFrame(time: 3, buttons: [.a]))
        #expect(refused.contains(.refuse("G maj is outside the run")))
        #expect(sounded(refused).isEmpty)
    }

    @Test func blockedTargetsAreDimmedWhereTheyAre() {
        var settings = DeskSettings()
        settings.consonance.mode = .run
        settings.consonance.hear([.sound(.chord, notes: [60, 64, 67], sound: "", level: 1, brightness: 1, tie: false)])
        let targets = TwinRings().degreeTargets(settings)
        #expect(targets.count == 7)
        #expect(targets.first { $0.name == "G maj" }?.isHidden == true)
        #expect(targets.first { $0.name == "E min" }?.isHidden == false)
    }
}
