import MusicTheoryCore
import Testing
@testable import DeskCore

@Suite("Voice leading")
struct VoiceLeadingTests {

    private let c = Key(root: .C, scale: .major)
    private let cMajor = [60, 64, 67]

    private func name(_ notes: [Int], _ direction: Int, _ shell: Int = 1) -> String? {
        VoiceLeading.neighbour(of: notes, by: VoiceMove(direction: direction, shell: shell), in: c)?.name
    }

    @Test func eachDirectionIsOneExactMotion() {
        // Up: the top voice a semitone up, G to G♯.
        #expect(VoiceLeading.moved(cMajor, by: VoiceMove(direction: 0, shell: 1)) == [60, 64, 68])
        // Right: the middle voice up, E to F.
        #expect(VoiceLeading.moved(cMajor, by: VoiceMove(direction: 2, shell: 1)) == [60, 65, 67])
        // Upper left: the two apart, the top up and the middle down.
        #expect(VoiceLeading.moved(cMajor, by: VoiceMove(direction: 7, shell: 1)) == [60, 63, 68])
        // The outer shell moves each voice two semitones.
        #expect(VoiceLeading.moved(cMajor, by: VoiceMove(direction: 1, shell: 2)) == [60, 66, 69])
    }

    @Test func theNeighboursAreTheConsonantChordsOnly() {
        #expect(name(cMajor, 0) == "C aug")
        #expect(name(cMajor, 2) == "C sus4")
        #expect(name(cMajor, 6) == "C min")
        #expect(name(cMajor, 0, 2) == "A min/C")
        // The top voice down a semitone makes C E F♯: not consonant.
        #expect(name(cMajor, 4) == nil)
    }

    @Test func theBassMovesTooAndTheRootMayMove() {
        let down = VoiceLeading.bassNeighbour(of: cMajor, by: VoiceMove(direction: 1, shell: 1), in: c)
        #expect(down?.name == "E min/B")
        #expect(down?.notes(DeskSettings()) == [59, 64, 67])
    }

    @Test func voicesNeverCrossOrMeet() {
        #expect(VoiceLeading.moved([60, 64, 65], by: VoiceMove(direction: 4, shell: 1)) == nil)
        #expect(VoiceLeading.moved([60, 64, 66], by: VoiceMove(direction: 4, shell: 2)) == nil)
    }

    @Test func aChordIsReadFromItsBassWhenItCanBe() {
        #expect(VoiceLeading.chord(of: [64, 67, 72], in: c)?.name == "C maj/E")
        #expect(VoiceLeading.chord(of: [60, 64, 67, 70], in: c)?.name == "C 7")
        #expect(VoiceLeading.chord(of: [60, 61, 62], in: c) == nil)
    }
}

@Suite("Twin rings' voices")
struct TwinRingsVoicesTests {

    /// Twin rings with the LB layer left on, showing the voices.
    private func voices() -> Rig<TwinRings> {
        var rig = Rig(TwinRings())
        rig.at(1) { $0.buttons = [.lb] }
        rig.at(1 + TapOrHold.tapTime) { $0.buttons = [.lb] }
        rig.at(1.5) { $0.buttons = [] }
        rig.at(2) { $0.buttons = [.l3] }
        rig.at(2.1) { $0.buttons = [] }
        return rig
    }

    @Test func l3WithTheLayerOnSwitchesToTheVoices() {
        let rig = voices()
        #expect(rig.settings.lbLayer == .voices)
        #expect(rig.layout.isOnVoices)
        // The ring's arrangement was not turned.
        #expect(rig.settings.ringArrangement == .home)
    }

    @Test func aFlickTakesAStepAndR3TakesItBack() {
        var rig = voices()
        rig.at(3) { $0.right = lean(90, 0.6) }
        #expect(rig.layout.chord(rig.settings).name == "C sus4")
        rig.at(3.1) { $0.right = .rest }
        #expect(rig.layout.walked?.name == "C sus4")
        // Steps walk on from where they took the voices: the middle down from F to E.
        rig.at(4) { $0.right = lean(270, 0.6) }
        rig.at(4.1) { $0.right = .rest }
        #expect(rig.layout.chord(rig.settings).name == "C maj")
        #expect(rig.layout.chord(rig.settings).notes(rig.settings) == [60, 64, 67])
        rig.at(5) { $0.right = lean(0, 0.95) }
        rig.at(5.1) { $0.right = .rest }
        #expect(rig.layout.chord(rig.settings).name == "A min/C")
        rig.at(6) { $0.buttons = [.r3] }
        rig.at(6.1) { $0.buttons = [] }
        #expect(rig.layout.walked == nil)
        #expect(rig.layout.chord(rig.settings).name == "C maj")
    }

    @Test func aHoldPlaysTheMoveAndGoesBack() {
        var rig = voices()
        rig.at(3) { $0.buttons = [.a] }
        let played = rig.at(3.5) { $0.right = lean(270, 0.6) }
        #expect(sounded(played) == [[60, 63, 67]])
        rig.at(4) { $0.right = lean(270, 0.6) }
        let back = rig.at(4.1) { $0.right = .rest }
        #expect(sounded(back) == [[60, 64, 67]])
        #expect(rig.layout.walked == nil)
    }

    @Test func theLeftStickMovesTheBass() {
        var rig = voices()
        rig.at(3) { $0.left = lean(180, 0.6) }
        rig.at(3.1) { $0.left = .rest }
        #expect(rig.layout.chord(rig.settings).name == "E min/B")
        // The degree pie is not played meanwhile.
        #expect(rig.layout.degree == .I)
    }

    @Test func aMoveThatIsNotConsonantCannotBeTaken() {
        var rig = voices()
        rig.at(3) { $0.right = lean(180, 0.6) }
        #expect(rig.layout.voiceAim == nil)
        rig.at(3.1) { $0.right = .rest }
        #expect(rig.layout.walked == nil)
    }
}
