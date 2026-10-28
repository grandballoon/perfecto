import MusicTheoryCore
import Testing
@testable import DeskCore

@Suite("Desk")
struct DeskTests {

    private let catalog = SoundCatalog([
        .init(name: "Keys", sounds: [.init(id: "electricPiano", name: "Electric Piano"), .init(id: "organ", name: "Organ")]),
        .init(name: "Synth", sounds: [.init(id: "soloLead", name: "Solo Lead")]),
    ])

    private func frame(_ time: Double, _ buttons: Set<PadButton> = []) -> GamepadFrame {
        GamepadFrame(time: time, buttons: buttons)
    }

    @Test func backGoesToTheNextLayoutAndLetsGo() {
        var desk = Desk(catalog: catalog)
        _ = desk.step(frame(1, [.a]))
        let out = desk.step(frame(2, [.a, .back]))
        #expect(desk.layout == .petals)
        #expect(out.contains(.silence(.chord)))
    }

    @Test func theMenuChangesTheChordSoundAndPlaysIt() {
        var desk = Desk(catalog: catalog)
        _ = desk.step(frame(1, [.start]))
        #expect(desk.menu != nil)
        for i in 0..<8 {
            _ = desk.step(frame(2 + Double(i) * 0.1, [.down]))
            _ = desk.step(frame(2.05 + Double(i) * 0.1))
        }
        let out = desk.step(frame(3, [.right]))
        #expect(desk.settings.chordSound == "organ")
        #expect(out == [.preview(sound: "organ", notes: [60, 64, 67])])
        _ = desk.step(frame(4, [.b]))
        #expect(desk.menu == nil)
    }

    @Test func theLibraryBrowsesByCategory() {
        var desk = Desk(catalog: catalog)
        _ = desk.step(frame(1, [.start]))
        for i in 0..<8 {
            _ = desk.step(frame(2 + Double(i) * 0.1, [.down]))
            _ = desk.step(frame(2.05 + Double(i) * 0.1))
        }
        _ = desk.step(frame(3, [.a]))
        #expect(desk.menu?.library == DeskMenu.Library(line: .chord, category: 0, index: 0))
        _ = desk.step(frame(4, [.right]))
        #expect(desk.settings.chordSound == "soloLead")
        _ = desk.step(frame(5, [.a]))
        #expect(desk.menu?.library == nil)
        #expect(desk.menu != nil)
    }

    @Test func theMenusKeyRowMovesBySemitones() {
        var desk = Desk(catalog: catalog)
        _ = desk.step(frame(1, [.start]))
        for (i, button) in [PadButton.down, .down, .down, .down, .down, .down, .down, .down, .down, .down, .right].enumerated() {
            _ = desk.step(frame(Double(i) * 2 + 2, [button]))
            _ = desk.step(frame(Double(i) * 2 + 3))
        }
        #expect(desk.settings.key == Key(root: .Cs, scale: .major))
    }

    @Test func aChordsFitIsReadAgainstTheKey() {
        let c = Key(root: .C, scale: .major)
        #expect(DeskChord(key: c, degree: .V, color: .grid(.seventh, nil)).fit(in: c) == .inKey)
        #expect(DeskChord(root: .Ds, tones: ChordTones([0, 4, 7]), in: c).fit(in: c) == .borrowed)
        #expect(DeskChord(key: c, degree: .I, color: .tones(ChordTones([0, 4, 5, 7]))).fit(in: c) == .tense)
    }
}
