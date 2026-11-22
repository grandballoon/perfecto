import MusicTheoryCore
import Testing
@testable import DeskCore

@Suite("Twin rings")
struct TwinRingsTests {

    @Test func aStrikesTheTonicsChord() {
        var rig = Rig(TwinRings())
        let out = rig.at(1) { $0.buttons = [.a] }
        #expect(out == [.sound(.chord, notes: [60, 64, 67], sound: "electricPiano", level: 0.8, brightness: 1, tie: false)])
    }

    @Test func theLeftStickChoosesTheDegreeAndKeepsIt() {
        var rig = Rig(TwinRings())
        // iii is two sectors clockwise of I, in scale order.
        rig.at(1) { $0.left = lean(2 * 360 / 7) }
        rig.at(2) { $0.left = .rest }
        let result1 = rig.at(3) { $0.buttons = [.a] }
        #expect(sounded(result1) == [[64, 67, 71]])
    }

    @Test func aLeanOnTheRingRecolorsTheChordHeld() {
        var rig = Rig(TwinRings())
        rig.at(1) { $0.buttons = [.a] }
        // A sector darker than I's own Ionian is Mixolydian; the inner ring is the 7th.
        let out = rig.at(2) { $0.right = lean(-RingPie.sectorSpan, 0.6) }
        #expect(out == [.sound(.chord, notes: [60, 64, 67, 70], sound: "electricPiano", level: 0.8, brightness: 1, tie: true)])
        #expect(rig.layout.chord(rig.settings).name == "C 7")
    }

    @Test func aFlickKeepsTheColorAndAHoldDoesNot() {
        var flick = Rig(TwinRings())
        flick.at(1) { $0.right = lean(0, 0.8) }
        flick.at(1.1) { $0.right = .rest }
        #expect(flick.layout.chord(flick.settings).name == "C maj9")

        var hold = Rig(TwinRings())
        hold.at(1) { $0.right = lean(0, 0.8) }
        hold.at(1.5) { $0.right = lean(0, 0.8) }
        hold.at(1.6) { $0.right = .rest }
        #expect(hold.layout.chord(hold.settings).name == "C maj")
    }

    @Test func theRightTriggerStrikesByHowFastItIsPulled() {
        var rig = Rig(TwinRings())
        rig.at(1) { $0.rightTrigger = 0.1 }
        let out = rig.at(1.02) { $0.rightTrigger = 0.7 }
        guard case let .sound(_, notes, _, level, _, _)? = out.first else {
            Issue.record("a strike")
            return
        }
        #expect(notes == [60, 64, 67])
        #expect(level == 1)
        let result2 = rig.at(1.5) { $0.rightTrigger = 0 }
        #expect(result2.contains(.silence(.chord)))
    }

    @Test func aBumperTappedMovesTheKeyAFifth() {
        var rig = Rig(TwinRings())
        rig.at(1) { $0.buttons = [.rb] }
        rig.at(1.1) { $0.buttons = [] }
        #expect(rig.settings.key == Key(root: .G, scale: .major))
        rig.at(2) { $0.buttons = [.lb] }
        rig.at(2.1) { $0.buttons = [] }
        rig.at(3) { $0.buttons = [.lb] }
        rig.at(3.1) { $0.buttons = [] }
        #expect(rig.settings.key == Key(root: .F, scale: .major))
    }

    @Test func lbPutsTheStepCompassOnTheRightStick() {
        var rig = Rig(TwinRings())
        rig.at(1) { $0.buttons = [.lb] }
        // Up adds the degree's next tone: its 7th.
        rig.at(1.2) { $0.right = lean(0) }
        #expect(rig.layout.chord(rig.settings).name == "C maj7")
        // Let go of the bumper after using it: no tap.
        rig.at(1.3) { $0.right = .rest; $0.buttons = [] }
        #expect(rig.settings.key == Key(root: .C, scale: .major))
    }

    @Test func aLongPressOfLBLeavesTheCompassOn() {
        var rig = Rig(TwinRings())
        rig.at(1) { $0.buttons = [.lb] }
        let latched = rig.at(1 + TapOrHold.tapTime) { $0.buttons = [.lb] }
        #expect(latched.contains(.rumble(.bump)))
        rig.at(1.5) { $0.buttons = [] }
        // Let go, the compass is still on the right stick, and the key has not moved.
        #expect(rig.layout.isOnCompass)
        #expect(rig.settings.key == Key(root: .C, scale: .major))
        rig.at(2) { $0.right = lean(0) }
        #expect(rig.layout.chord(rig.settings).name == "C maj7")
        rig.at(2.1) { $0.right = .rest }
        // Another long-press turns it off.
        rig.at(3) { $0.buttons = [.lb] }
        rig.at(3 + TapOrHold.tapTime) { $0.buttons = [.lb] }
        rig.at(3.5) { $0.buttons = [] }
        #expect(!rig.layout.isOnCompass)
    }

    @Test func aTapOfLBStillMovesTheKeyWithTheCompassOn() {
        var rig = Rig(TwinRings())
        rig.at(1) { $0.buttons = [.lb] }
        rig.at(1.5) { $0.buttons = [.lb] }
        rig.at(1.6) { $0.buttons = [] }
        rig.at(2) { $0.buttons = [.lb] }
        rig.at(2.1) { $0.buttons = [] }
        #expect(rig.settings.key == Key(root: .F, scale: .major))
        #expect(rig.layout.isOnCompass)
    }

    @Test func r3AtRestTakesTheCompassBackAndThenTheColor() {
        var rig = Rig(TwinRings())
        // A Mixolydian 7th kept on the ring, and the compass's first add kept on it.
        rig.at(1) { $0.right = lean(-RingPie.sectorSpan, 0.6) }
        rig.at(1.1) { $0.right = .rest }
        rig.at(2) { $0.buttons = [.lb] }
        rig.at(2.05) { $0.right = lean(0) }
        rig.at(2.1) { $0.right = .rest }
        rig.at(2.2) { $0.buttons = [] }
        #expect(rig.layout.chord(rig.settings).name != "C 7")
        #expect(rig.layout.resetsTo(rig.settings)?.name == "C 7")
        rig.at(3) { $0.buttons = [.r3] }
        rig.at(3.1) { $0.buttons = [] }
        #expect(rig.layout.chord(rig.settings).name == "C 7")
        rig.at(4) { $0.buttons = [.r3] }
        rig.at(4.1) { $0.buttons = [] }
        #expect(rig.layout.chord(rig.settings).name == "C maj")
        #expect(rig.layout.resetsTo(rig.settings) == nil)
    }

    @Test func theLeftTriggerArpeggiates() {
        var rig = Rig(TwinRings())
        rig.at(1) { $0.buttons = [.a] }
        // Pulled to the first step: quarter notes at 96 bpm.
        let out = rig.at(1) { $0.leftTrigger = 0.3 }
        #expect(sounded(out) == [[60]])
        let result3 = rig.at(1 + 60.0 / 96)
        #expect(sounded(result3) == [[64]])
        let result4 = rig.at(1 + 2 * 60.0 / 96)
        #expect(sounded(result4) == [[67]])
    }

    @Test func theDpadVoicesTheChordHeld() {
        var rig = Rig(TwinRings())
        rig.at(1) { $0.buttons = [.a] }
        let out = rig.at(2) { $0.buttons = [.a, .right] }
        #expect(sounded(out) == [[64, 67, 72]])
        #expect(rig.settings.inversion == .first)
    }
}

@Suite("Petals and depth")
struct PetalsTests {

    @Test func theFaceButtonsStrikeFourHeights() {
        var rig = Rig(Petals())
        let result5 = rig.at(1) { $0.buttons = [.a] }
        #expect(sounded(result5) == [[60, 64, 67]])
        let result6 = rig.at(2) { $0.buttons = [.a, .x] }
        #expect(sounded(result6) == [[60, 64, 67, 71]])
        // Letting go of X hands the chord back to A, beneath it.
        let result7 = rig.at(3) { $0.buttons = [.a] }
        #expect(sounded(result7) == [[60, 64, 67]])
        let result8 = rig.at(4) { $0.buttons = [] }
        #expect(result8.contains(.silence(.chord)))
    }

    @Test func theTriggersBendTheMode() {
        var rig = Rig(Petals())
        rig.at(1) { $0.leftTrigger = 0.3 }
        #expect(rig.layout.chord(.height(.seventh), rig.settings).name == "C 7")
        rig.at(2) { $0.leftTrigger = 0; $0.rightTrigger = 0.3 }
        #expect(rig.layout.chord(.height(.eleventh), rig.settings).name == "C maj9♯11")
    }

    @Test func lbPutsMarksOnTheButtons() {
        var rig = Rig(Petals())
        rig.at(1) { $0.buttons = [.lb] }
        rig.at(2) { $0.buttons = [.lb, .a] }
        #expect(rig.layout.line.chord?.name == "C sus4")
    }

    @Test func theRightStickBendsTheVoicingAndR3KeepsIt() {
        var rig = Rig(Petals())
        rig.at(1) { $0.buttons = [.a] }
        let result9 = rig.at(2) { $0.right = lean(90, 0.6) }
        #expect(sounded(result9) == [[64, 67, 72]])
        rig.at(3) { $0.buttons = [.a, .r3] }
        #expect(rig.settings.inversion == .first)
        // Back to the middle, nothing more is bent.
        let result10 = rig.at(4) { $0.right = .rest; $0.buttons = [.a] }
        #expect(sounded(result10) == [])
    }
}

@Suite("Neighbourhood")
struct NeighbourhoodTests {

    @Test func theTonnetzLensHasTheFlips() {
        var rig = Rig(Neighbourhood())
        rig.at(1) { $0.buttons = [.rb] }
        #expect(rig.layout.lens == .tonnetz)
        let names = rig.layout.neighbours(rig.settings).map { $0?.chord.name }
        #expect(names == ["C min", "A min", "G maj", "D# maj", "F min", "G# maj", "F maj", "E min"])
    }

    @Test func aFlickMovesAndStrikes() {
        var rig = Rig(Neighbourhood())
        rig.at(1)
        // Up, in the color lens: the 7th added.
        rig.at(2) { $0.right = lean(0) }
        let out = rig.at(2.1) { $0.right = .rest }
        #expect(rig.layout.centre.name == "C maj7")
        #expect(sounded(out) == [[60, 64, 67, 71]])
        #expect(rig.layout.path.map(\.name) == ["C maj", "C maj7"])
    }

    @Test func aHoldListensAndComesBack() {
        var rig = Rig(Neighbourhood())
        rig.at(1) { $0.buttons = [.a] }
        rig.at(2) { $0.right = lean(0) }
        rig.at(2.5) { $0.right = lean(0) }
        let out = rig.at(2.6) { $0.right = .rest }
        #expect(rig.layout.centre.name == "C maj")
        #expect(sounded(out) == [[60, 64, 67]])
    }

    @Test func theLeftStickWalksThePath() {
        var rig = Rig(Neighbourhood())
        rig.at(1)
        rig.at(2) { $0.right = lean(0) }
        rig.at(2.1) { $0.right = .rest }
        rig.at(3) { $0.left = lean(270) }
        #expect(rig.layout.centre.name == "C maj")
        rig.at(3.5) { $0.left = .rest }
        rig.at(4) { $0.left = lean(90) }
        #expect(rig.layout.centre.name == "C maj7")
    }

    @Test func degreesShareNotesWithTheirNeighbours() {
        var rig = Rig(Neighbourhood())
        rig.at(1) { $0.buttons = [.lb] }
        #expect(rig.layout.lens == .degrees)
        let names = rig.layout.neighbours(rig.settings).map { $0?.chord.name }
        #expect(names == [nil, "G maj", "E min", "B dim", nil, "D min", "A min", "F maj"])
    }
}

@Suite("Two voices")
struct TwoVoicesTests {

    @Test func ltSwellsTheChord() {
        var rig = Rig(TwoVoices())
        rig.at(1) { $0.leftTrigger = 0.2 }
        let out = rig.at(1.02) { $0.leftTrigger = 0.2 }
        #expect(sounded(out) == [[60, 64, 67]])
        let result11 = rig.at(1.5) { $0.leftTrigger = 1 }
        #expect(result11.contains(.shape(.chord, level: 1, brightness: 1, bend: 0)))
    }

    @Test func rtPlaysTheNotePointedAtAndSlides() {
        var rig = Rig(TwoVoices())
        rig.at(1) { $0.right = lean(0, 0.7) }
        let struck = rig.at(1.1) { $0.rightTrigger = 1 }
        #expect(sounded(struck, on: .melody) == [[72]])
        // E is two petals clockwise: the held note slides up four semitones.
        let slid = rig.at(1.3) { $0.right = lean(2 * 360 / 7, 0.7) }
        #expect(slid.contains { if case let .shape(.melody, _, _, bend) = $0 { return bend == 4 } else { return false } })
    }

    @Test func chordTonesOnlyLeavesOutTheRest() {
        var rig = Rig(TwoVoices())
        rig.at(1) { $0.buttons = [.y] }
        let reachable = rig.layout.petals(rig.settings).filter(\.isReachable).map(\.note)
        #expect(reachable == [72, 76, 79])
    }

    @Test func theBarComesToRestInTune() {
        var rig = Rig(TwoVoices())
        rig.at(1) { $0.buttons = [.rb]; $0.right = Stick(x: 0, y: 0.03) }
        rig.at(1.01) { $0.rightTrigger = 1 }
        rig.at(1.05) { $0.rightTrigger = 1 }
        rig.at(1.3) { $0.rightTrigger = 1 }
        #expect(rig.layout.melody.pitch == 84)
    }
}

@Suite("BeatGrid")
struct BeatGridTests {
    @Test func theGridSnapsLengths() {
        #expect(BeatGrid.sixteenth.length(0.1) == 0.25)
        #expect(BeatGrid.sixteenth.length(1.02) == 1)
        #expect(BeatGrid.quarter.length(1.4) == 2)
        #expect(BeatGrid.free.length(0.05) == 0.125)
        #expect(BeatGrid.eighth.nearest(1.3) == 1.5)
    }
}
