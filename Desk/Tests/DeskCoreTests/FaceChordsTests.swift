import MusicTheoryCore
import Testing
@testable import DeskCore

// Ported to Tests/PerfectoDeskCoreTests/face_chords_tests.cpp.
@Suite("Face Chords")
struct FaceChordsTests {
    private func hold(_ frame: inout GamepadFrame, _ buttons: Set<PadButton>, lt: Double = 0) {
        frame.buttons = buttons
        frame.leftTrigger = lt
    }

    private func silences(_ effects: [DeskEffect]) -> Bool {
        effects.contains(.silence(.chord))
    }

    private func silencesOver(_ effects: [DeskEffect]) -> Bool {
        effects.contains(.silence(.melody))
    }

    /// A rig with the second voice added (R3) at time 0.1.
    private func withSecond() -> Rig<FaceChords> {
        var rig = Rig(FaceChords())
        rig.at(0.1) { hold(&$0, [.r3]) }
        rig.at(0.2) { hold(&$0, []) }
        return rig
    }

    /// The second voice added and LB double-clicked: both voices on.
    private func together() -> Rig<FaceChords> {
        var rig = withSecond()
        rig.at(0.3) { hold(&$0, [.lb]) }
        rig.at(0.35) { hold(&$0, []) }
        rig.at(0.4) { hold(&$0, [.lb]) }
        rig.at(0.45) { hold(&$0, []) }
        return rig
    }

    @Test func eachButtonStrikesItsNumberedChordTheMinorOnesWithLT() {
        var rig = Rig(FaceChords())
        let plain: [(PadButton, [Int])] = [(.a, [60, 64, 67]), (.b, [65, 69, 72]), (.x, [67, 71, 74]), (.y, [71, 74, 77])]
        let layered: [(PadButton, [Int])] = [(.a, [60, 64, 67]), (.b, [62, 65, 69]), (.x, [64, 67, 71]), (.y, [69, 72, 76])]
        var time = 1.0
        for (layer, lt) in [(plain, 0.0), (layered, 1.0)] {
            for (button, notes) in layer {
                #expect(sounded(rig.at(time) { hold(&$0, [button], lt: lt) }) == [notes])
                #expect(silences(rig.at(time + 0.5) { hold(&$0, [], lt: lt) }))
                time += 1
            }
        }
    }

    @Test func pullingLTWhileAButtonIsHeldChangesTheChordAndLettingGoChangesItBack() {
        var rig = Rig(FaceChords())
        #expect(sounded(rig.at(1) { hold(&$0, [.b]) }) == [[65, 69, 72]])
        #expect(sounded(rig.at(2) { hold(&$0, [.b], lt: 1) }) == [[62, 65, 69]])
        #expect(rig.layout.heard?.button == .b && rig.layout.heard?.degree == .ii)
        #expect(sounded(rig.at(3) { hold(&$0, [.b], lt: 0) }) == [[65, 69, 72]])
        #expect(rig.layout.heard?.degree == .IV)
    }

    @Test func ltOnATheTonicInBothLayersStrikesNothingAgain() {
        var rig = Rig(FaceChords())
        rig.at(1) { hold(&$0, [.a]) }
        #expect(sounded(rig.at(2) { hold(&$0, [.a], lt: 1) }).isEmpty)
        #expect(rig.layout.line.isSounding)
    }

    @Test func ltAloneSoundsNothing() {
        var rig = Rig(FaceChords())
        #expect(sounded(rig.at(1) { hold(&$0, [], lt: 1) }).isEmpty)
        #expect(sounded(rig.at(2) { hold(&$0, [], lt: 0) }).isEmpty)
        #expect(!rig.layout.line.isSounding)
    }

    @Test func ltIsHeldALittleEitherSideOfHalfway() {
        var rig = Rig(FaceChords())
        rig.at(1) { hold(&$0, [.x], lt: 0.52) }
        #expect(!rig.layout.isLayered)
        rig.at(1.5) { hold(&$0, [.x], lt: 0.6) }
        #expect(rig.layout.isLayered)
        #expect(sounded(rig.at(2) { hold(&$0, [.x], lt: 0.47) }).isEmpty)
        #expect(rig.layout.isLayered)
        #expect(sounded(rig.at(3) { hold(&$0, [.x], lt: 0.4) }) == [[67, 71, 74]])
    }

    @Test func theLatestButtonIsHeardAndLettingItGoHandsBackToTheOneBeneath() {
        var rig = Rig(FaceChords())
        rig.at(1) { hold(&$0, [.a]) }
        #expect(sounded(rig.at(2) { hold(&$0, [.a, .x]) }) == [[67, 71, 74]])
        #expect(sounded(rig.at(3) { hold(&$0, [.a]) }) == [[60, 64, 67]])
        #expect(silences(rig.at(4) { hold(&$0, []) }))
        #expect(!rig.layout.line.isSounding)
        #expect(rig.layout.heard == nil)
    }

    @Test func aLayerThatLeavesAButtonOutPlaysThePressBeneathItOrNothing() {
        var map = FaceChords.Map.standard
        map.layered[.y] = nil
        var rig = Rig(FaceChords(map: map))
        rig.at(1) { hold(&$0, [.a]) }
        rig.at(2) { hold(&$0, [.a, .y]) }
        #expect(rig.layout.heard?.degree == .viiDim)
        #expect(sounded(rig.at(3) { hold(&$0, [.a, .y], lt: 1) }) == [[60, 64, 67]])
        rig.at(4) { hold(&$0, [.y], lt: 1) }
        #expect(!rig.layout.line.isSounding)
        #expect(sounded(rig.at(5) { hold(&$0, [.y], lt: 0) }) == [[71, 74, 77]])
    }

    @Test func theDPadRevoicesTheChordHeld() {
        var rig = Rig(FaceChords())
        rig.at(1) { hold(&$0, [.a]) }
        #expect(sounded(rig.at(2) { hold(&$0, [.a, .up]) }) == [[72, 76, 79]])
    }

    private static let catalog = SoundCatalog([
        .init(name: "Keys", sounds: [.init(id: "electricPiano", name: "Electric Piano")]),
    ])

    @Test func theMenuLetsGoAndAButtonStillDownWhenItClosesStrikesNothing() {
        var desk = Desk(layout: .faceChords, catalog: Self.catalog)
        _ = desk.step(GamepadFrame(time: 1, buttons: [.a]))
        #expect(desk.faceChords.line.isSounding)
        #expect(silences(desk.step(GamepadFrame(time: 2, buttons: [.a, .start]))))
        _ = desk.step(GamepadFrame(time: 3, buttons: [.a]))
        _ = desk.step(GamepadFrame(time: 4, buttons: [.a, .start]))
        #expect(desk.menu == nil)
        #expect(sounded(desk.step(GamepadFrame(time: 5, leftTrigger: 1, buttons: [.a]))).isEmpty)
        #expect(!desk.faceChords.line.isSounding)
        #expect(sounded(desk.step(GamepadFrame(time: 6))).isEmpty)
        #expect(!desk.faceChords.line.isSounding)
    }

    @Test func backLeavesItSilent() {
        var desk = Desk(layout: .faceChords, catalog: Self.catalog)
        _ = desk.step(GamepadFrame(time: 1, buttons: [.b]))
        #expect(silences(desk.step(GamepadFrame(time: 2, buttons: [.b, .back]))))
        #expect(desk.layout == .twinRings)
        #expect(!desk.faceChords.line.isSounding)
    }

    @Test func theLegendNamesEachChordByNumberAndNameAndWhatLTBrings() {
        var rig = Rig(FaceChords())
        var legend = rig.layout.legend(rig.settings)
        #expect(legend[.button(.b)] == "IV · F maj")
        #expect(legend[.button(.y)] == "vii° · B dim")
        #expect(legend[.leftTrigger] == "Hold: ii iii vi")
        rig.at(1) { hold(&$0, [], lt: 1) }
        legend = rig.layout.legend(rig.settings)
        #expect(legend[.button(.b)] == "ii · D min")
        #expect(legend[.leftTrigger] == "Let go: IV V vii°")
    }

    @Test func withOneVoiceLBAndAFaceButtonPlayTheFirstVoice() {
        var rig = Rig(FaceChords())
        let out = rig.at(1) { hold(&$0, [.lb, .x]) }
        #expect(sounded(out) == [[67, 71, 74]])
        #expect(sounded(out, on: .melody).isEmpty)
    }

    @Test func r3AddsASecondVoiceAndLBHeldPlaysItAloneAnOctaveOverOnTheLine() {
        var rig = withSecond()
        #expect(rig.layout.hasSecond)
        #expect(sounded(rig.at(1) { hold(&$0, [.a]) }) == [[60, 64, 67]])
        let out = rig.at(2) { hold(&$0, [.a, .lb, .x]) }
        #expect(sounded(out).isEmpty)
        #expect(sounded(out, on: .melody) == [[79, 83, 86]])
        #expect(rig.layout.heard?.button == .a && rig.layout.heard?.degree == .I)
        #expect(rig.layout.voices[1].heard?.button == .x && rig.layout.voices[1].heard?.degree == .V)
        // Letting LB go leaves the press where it went.
        #expect(rig.at(3) { hold(&$0, [.a, .x]) }.isEmpty)
        let up = rig.at(4) { hold(&$0, [.a]) }
        #expect(silencesOver(up))
        #expect(!silences(up))
    }

    @Test func withoutLBAPressWithTheSecondVoiceAddedIsTheFirsts() {
        var rig = withSecond()
        let out = rig.at(1) { hold(&$0, [.b]) }
        #expect(sounded(out) == [[65, 69, 72]])
        #expect(sounded(out, on: .melody).isEmpty)
    }

    @Test func aDoubleClickOfLBPlaysBothVoicesOnEveryPressAndAnotherGoesBackToOne() {
        var rig = together()
        #expect(rig.layout.isTogether)
        var out = rig.at(1) { hold(&$0, [.b]) }
        #expect(sounded(out) == [[65, 69, 72]])
        #expect(sounded(out, on: .melody) == [[77, 81, 84]])
        out = rig.at(1.5) { hold(&$0, []) }
        #expect(silences(out))
        #expect(silencesOver(out))
        rig.at(2) { hold(&$0, [.lb]) }
        rig.at(2.1) { hold(&$0, []) }
        rig.at(2.2) { hold(&$0, [.lb]) }
        rig.at(2.3) { hold(&$0, []) }
        #expect(!rig.layout.isTogether)
        #expect(sounded(rig.at(3) { hold(&$0, [.b]) }, on: .melody).isEmpty)
    }

    @Test func twoPressesOfLBTooFarApartAreNoDoubleClick() {
        var rig = withSecond()
        rig.at(1) { hold(&$0, [.lb]) }
        rig.at(1.1) { hold(&$0, []) }
        rig.at(1.1 + FaceChords.doubleClick + 0.05) { hold(&$0, [.lb]) }
        #expect(!rig.layout.isTogether)
    }

    @Test func withBothOnLBAndAFaceButtonPlayTheSecondVoiceOverTheFirst() {
        var rig = together()
        rig.at(1) { hold(&$0, [.a]) }
        let out = rig.at(2) { hold(&$0, [.a, .lb, .x]) }
        #expect(sounded(out).isEmpty)
        #expect(sounded(out, on: .melody) == [[79, 83, 86]])
        // Letting X go hands the second voice back to A beneath it.
        #expect(sounded(rig.at(3) { hold(&$0, [.a]) }, on: .melody) == [[72, 76, 79]])
    }

    @Test func withBothOnLTAndAFaceButtonTogetherPlayThatButtonsLTChordOverTheFirstWhichKeepsItsOwn() {
        var rig = together()
        rig.at(1) { hold(&$0, [.b]) }
        // LT a moment before Y: the pull moves the first voice at first, as a
        // pull alone does, and then Y with it makes the pull the second voice's.
        var out = rig.at(2) { hold(&$0, [.b], lt: 1) }
        #expect(sounded(out) == [[62, 65, 69]])
        out = rig.at(2.04) { hold(&$0, [.b, .y], lt: 1) }
        #expect(rig.layout.isOverPull)
        #expect(sounded(out) == [[65, 69, 72]])
        #expect(sounded(out, on: .melody) == [[81, 84, 88]])
        #expect(rig.layout.heard?.button == .b && rig.layout.heard?.degree == .IV)
        #expect(rig.layout.voices[1].heard?.button == .y && rig.layout.voices[1].heard?.degree == .vi)
        // Letting LT go ends the pull: the second voice is Y without it.
        out = rig.at(3) { hold(&$0, [.b, .y]) }
        #expect(!rig.layout.isOverPull)
        #expect(sounded(out).isEmpty)
        #expect(sounded(out, on: .melody) == [[83, 86, 89]])
    }

    @Test func withBothOnAFaceButtonAndLTJustAfterAreStruckTogetherTheFirstVoiceGoingBack() {
        var rig = together()
        rig.at(1) { hold(&$0, [.b]) }
        var out = rig.at(2) { hold(&$0, [.b, .y]) }
        #expect(sounded(out) == [[71, 74, 77]])
        out = rig.at(2 + FaceChords.together - 0.01) { hold(&$0, [.b, .y], lt: 1) }
        #expect(sounded(out) == [[65, 69, 72]])
        #expect(sounded(out, on: .melody) == [[81, 84, 88]])
        #expect(rig.layout.voices[0].held == [.b])
    }

    @Test func withBothOnLTPulledLaterWhileAButtonIsHeldSwitchesBothVoicesChord() {
        var rig = together()
        rig.at(1) { hold(&$0, [.b]) }
        let out = rig.at(1 + FaceChords.together + 0.1) { hold(&$0, [.b], lt: 1) }
        #expect(!rig.layout.isOverPull)
        #expect(sounded(out) == [[62, 65, 69]])
        #expect(sounded(out, on: .melody) == [[74, 77, 81]])
    }

    @Test func withBothOnAPressWithLTHeldFromBeforePlaysBothVoicesInItsLayer() {
        var rig = together()
        rig.at(1) { hold(&$0, [], lt: 1) }
        let out = rig.at(2) { hold(&$0, [.x], lt: 1) }
        #expect(sounded(out) == [[64, 67, 71]])
        #expect(sounded(out, on: .melody) == [[76, 79, 83]])
    }

    @Test func withOneVoiceLTAndAFaceButtonTogetherPlayTheFirstVoicesLTChordAsBefore() {
        var rig = withSecond()
        rig.at(1) { hold(&$0, [], lt: 1) }
        let out = rig.at(1.02) { hold(&$0, [.x], lt: 1) }
        #expect(sounded(out) == [[64, 67, 71]])
        #expect(sounded(out, on: .melody).isEmpty)
    }

    @Test func r3AgainTakesTheSecondVoiceAwaySilencingIt() {
        var rig = together()
        rig.at(1) { hold(&$0, [.a]) }
        let out = rig.at(2) { hold(&$0, [.a, .r3]) }
        #expect(silencesOver(out))
        #expect(!silences(out))
        #expect(!rig.layout.hasSecond)
        #expect(!rig.layout.isTogether)
        #expect(rig.layout.line.isSounding)
    }

    @Test func theDPadRevoicesBothVoices() {
        var rig = together()
        rig.at(1) { hold(&$0, [.a]) }
        let out = rig.at(2) { hold(&$0, [.a, .up]) }
        #expect(sounded(out) == [[72, 76, 79]])
        #expect(sounded(out, on: .melody) == [[84, 88, 91]])
    }

    @Test func theMenuLetsGoOfBothVoices() {
        var desk = Desk(layout: .faceChords, catalog: Self.catalog)
        _ = desk.step(GamepadFrame(time: 0.1, buttons: [.r3]))
        _ = desk.step(GamepadFrame(time: 0.2))
        _ = desk.step(GamepadFrame(time: 1, buttons: [.a]))
        _ = desk.step(GamepadFrame(time: 2, buttons: [.a, .lb, .x]))
        #expect(desk.pinnable == DeskChord(key: Key(root: .C, scale: .major), degree: .I))
        let out = desk.step(GamepadFrame(time: 3, buttons: [.a, .x, .start]))
        #expect(silences(out))
        #expect(silencesOver(out))
        #expect(desk.faceChords.hasSecond)
    }

    @Test func theLegendSaysWhatR3AndLBDoForTheVoices() {
        var legend = Rig(FaceChords()).layout.legend(DeskSettings())
        #expect(legend[.button(.r3)] == "Add a second voice")
        #expect(legend[.button(.lb)] == nil)
        legend = withSecond().layout.legend(DeskSettings())
        #expect(legend[.button(.r3)] == "Take away voice 2")
        #expect(legend[.button(.lb)] == "Hold: voice 2 · double-click: both")
        legend = together().layout.legend(DeskSettings())
        #expect(legend[.button(.lb)] == "Hold: voice 2 over · double-click: voice 1")
        #expect(legend[.leftTrigger] == "Hold: ii iii vi · with a face: voice 2")
    }
}
