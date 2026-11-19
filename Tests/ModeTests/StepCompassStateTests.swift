import Testing
@testable import Perfecto

/// The step compass as a live color surface: a place played colors the
/// chord while it is held, even when it comes down before the chord, and a
/// kept walk is each degree's own.
@Suite("StepCompassState")
@MainActor
struct StepCompassStateTests {

    private func makeCompassState() -> (PerformanceState, RecordingSink) {
        let sink = RecordingSink()
        let state = PerformanceState(sink: sink, clock: ManualClock())
        return (state, sink)
    }

    @Test func nothingHeldPlaysTheTriad() {
        let (state, sink) = makeCompassState()
        state.press(.degree(.I))
        #expect(sink.playCalls.last?.notes == [60, 64, 67])
        #expect(state.color(for: .I) == .base)
    }

    /// A place that comes down before the chord colors its first sound:
    /// the chord is never heard plain.
    @Test func aPlaceHeldBeforeTheChordColorsItFromTheStart() {
        let (state, sink) = makeCompassState()
        state.compassPressed(CompassPlace(.add, 1))
        state.press(.degree(.V))
        #expect(sink.playCalls.count == 1)
        #expect(sink.playCalls.last?.notes == [67, 71, 74, 77])   // G7
    }

    @Test func aPlacePressedWhileHeldRecolorsTheChordAndLiftingGoesBack() {
        let (state, sink) = makeCompassState()
        state.press(.degree(.V))
        state.compassPressed(CompassPlace(.raise, 1))
        #expect(sink.playCalls.last?.notes == [67, 72, 74])       // Gsus4
        state.compassLifted(CompassPlace(.raise, 1))
        #expect(sink.playCalls.last?.notes == [67, 71, 74])
    }

    /// The place held stays the same as the chord changes, and means the
    /// new chord's own step.
    @Test func aHeldPlaceIsEachChordsOwn() {
        let (state, sink) = makeCompassState()
        state.compassPressed(CompassPlace(.add, 1))
        state.press(.degree(.ii))
        #expect(sink.playCalls.last?.notes == [62, 65, 69, 72])   // Dm7
        state.release(.degree(.ii))
        state.press(.degree(.I))
        #expect(sink.playCalls.last?.notes == [60, 64, 67, 71])   // Cmaj7
        #expect(state.activeVoicingText == "C maj7")
    }

    /// A step back takes the walk kept to the chord it led to before, and
    /// the chord held follows; played, there is no walk to step back on.
    @Test func aStepBackUndoesTheWalksLastStep() {
        let (state, sink) = makeCompassState()
        state.keepsCompassColor = true
        state.press(.degree(.V))
        state.compassPressed(CompassPlace(.add, 1))
        state.compassPressed(CompassPlace(.add, 1))
        #expect(sink.playCalls.last?.notes == [67, 71, 74, 77, 81])   // G9
        state.compassStepBack()
        #expect(state.compassWalk == [CompassPlace(.add, 1)])
        #expect(sink.playCalls.last?.notes == [67, 71, 74, 77])       // G7
        state.compassStepBack()
        state.compassStepBack()
        #expect(state.compassWalk.isEmpty)
        #expect(sink.playCalls.last?.notes == [67, 71, 74])
    }

    /// The walk's steps, as the edge layout's compass names them.
    @Test func aWalksStepsAreTheDegreesOwn() {
        let key = Key(root: .C, scale: .major)
        let walk = [CompassPlace(.add, 1), CompassPlace(.add, 1)]
        #expect(CompassWalk.steps(walk, key: key, degree: .V, ranking: .theory, assistance: .none).map(\.editName) == ["+♭7", "+2"])
        #expect(CompassWalk.steps(walk, key: key, degree: .I, ranking: .theory, assistance: .none).map(\.editName) == ["+7", "+2"])
    }

    @Test func liftingAnotherPlaceLeavesTheLatest() {
        let (state, sink) = makeCompassState()
        state.press(.degree(.V))
        state.compassPressed(CompassPlace(.add, 1))
        state.compassPressed(CompassPlace(.add, 2))
        state.compassLifted(CompassPlace(.add, 1))
        #expect(sink.playCalls.last?.notes == [67, 71, 74, 81])   // G add9
    }

    /// Kept, each tap is a step from the last, and the walk is each
    /// degree's own: two adds are G9 on V and Dm9 on ii.
    @Test func aKeptWalkStepsFromTheLastAndFollowsTheDegree() {
        let (state, sink) = makeCompassState()
        state.keepsCompassColor = true
        state.compassPressed(CompassPlace(.add, 1))
        state.compassLifted(CompassPlace(.add, 1))
        state.compassPressed(CompassPlace(.add, 1))
        state.press(.degree(.V))
        #expect(sink.playCalls.last?.notes == [67, 71, 74, 77, 81])   // G9
        state.release(.degree(.V))
        state.press(.degree(.ii))
        #expect(sink.playCalls.last?.notes == [62, 65, 69, 72, 76])   // Dm9
        state.compassCleared()
        #expect(sink.playCalls.last?.notes == [62, 65, 69])
    }

    @Test func theOriginIsThePlainChordOrTheWalk() {
        let (state, _) = makeCompassState()
        #expect(state.compassOrigin(for: .V) == ChordTones([0, 4, 7]))
        state.keepsCompassColor = true
        state.compassPressed(CompassPlace(.add, 1))
        #expect(state.compassOrigin(for: .V) == ChordTones([0, 4, 7, 10]))
    }

    @Test func switchingKeepClearsTheCompass() {
        let (state, _) = makeCompassState()
        state.compassPressed(CompassPlace(.add, 1))
        state.keepsCompassColor = true
        #expect(state.compassPlaces.isEmpty)
        state.compassPressed(CompassPlace(.add, 1))
        #expect(state.compassPlaces == [CompassPlace(.add, 1)])
        state.keepsCompassColor = false
        #expect(state.compassPlaces.isEmpty)
    }

    @Test func theRankingChangesWhatAPlacePlays() {
        let (state, sink) = makeCompassState()
        state.press(.degree(.I))
        state.compassPressed(CompassPlace(.add, 1))
        #expect(sink.playCalls.last?.notes == [60, 64, 67, 71])   // Cmaj7
        state.compassRanking = .common
        #expect(sink.playCalls.last?.notes == [60, 64, 67, 70])   // C7
    }

    @Test func thePlacesMakeACross() {
        let cells = CompassPlace.all.map { StepCompassGrid.cell(of: $0) }
        #expect(Set(cells.map { "\($0.column),\($0.row)" }).count == CompassPlace.all.count)
        #expect(cells.allSatisfy { $0.column == 2 || $0.row == 2 })
        #expect(StepCompassGrid.cell(of: CompassPlace(.add, 1)) == (2, 1))
        #expect(StepCompassGrid.cell(of: CompassPlace(.lower, 2)) == (0, 2))
    }
}

/// The edge layout's table and tree color the chord through the same state
/// as the compass: held while a finger is on them, kept by the pin.
@Suite("ColorSurfaceState")
@MainActor
struct ColorSurfaceStateTests {

    private func makeState() -> (PerformanceState, RecordingSink) {
        let sink = RecordingSink()
        let state = PerformanceState(sink: sink, clock: ManualClock())
        return (state, sink)
    }

    private let maj7 = ChordTones([0, 4, 7, 11])

    /// A quality is the same quality on every degree, in key or not.
    @Test func aTableQualityPlaysOnTheChordHeldAndLiftingGoesBack() {
        let (state, sink) = makeState()
        state.press(.degree(.V))
        state.tablePressed(maj7)
        #expect(sink.playCalls.last?.notes == [67, 71, 74, 78])   // Gmaj7
        state.tableLifted(maj7)
        #expect(sink.playCalls.last?.notes == [67, 71, 74])
    }

    @Test func aKeptTableQualityStaysUntilThePlainChord() {
        let (state, sink) = makeState()
        state.keepsCompassColor = true
        state.tablePressed(maj7)
        state.tableLifted(maj7)
        state.press(.degree(.ii))
        #expect(sink.playCalls.last?.notes == [62, 66, 69, 73])   // Dmaj7
        state.compassCleared()
        #expect(sink.playCalls.last?.notes == [62, 65, 69])
    }

    /// The latest surface touched is the color: a compass place lets the
    /// table's quality go.
    @Test func aCompassPlaceTakesOverFromTheTable() {
        let (state, sink) = makeState()
        state.keepsCompassColor = true
        state.tablePressed(maj7)
        state.compassPressed(CompassPlace(.add, 1))
        state.press(.degree(.V))
        #expect(state.tableTones == nil)
        #expect(sink.playCalls.last?.notes == [67, 71, 74, 77])   // G7
    }

    /// A tree node plays every step of its path at once; played, lifting
    /// is the plain chord again.
    @Test func aTreeNodePlaysItsWholePath() {
        let (state, sink) = makeState()
        state.press(.degree(.V))
        state.treeHeld([CompassPlace(.add, 1)])
        #expect(sink.playCalls.last?.notes == [67, 71, 74, 77])        // G7
        state.treeHeld([CompassPlace(.add, 1), CompassPlace(.add, 1)])
        #expect(sink.playCalls.last?.notes == [67, 71, 74, 77, 81])    // G9
        state.treeLifted()
        #expect(sink.playCalls.last?.notes == [67, 71, 74])
        #expect(state.compassWalk.isEmpty)
    }

    /// Kept, lifting keeps the path, and the tree steps from it next.
    @Test func aKeptTreeNodeIsWhereTheTreeStepsFromNext() {
        let (state, sink) = makeState()
        state.keepsCompassColor = true
        state.press(.degree(.V))
        state.treeHeld([CompassPlace(.add, 1)])
        state.treeLifted()
        #expect(state.compassWalk == [CompassPlace(.add, 1)])
        #expect(sink.playCalls.last?.notes == [67, 71, 74, 77])        // G7 stays
        state.treeHeld([CompassPlace(.add, 1)])
        #expect(sink.playCalls.last?.notes == [67, 71, 74, 77, 81])    // G9, a step on
        state.enterBackground()
        #expect(state.compassWalk == [CompassPlace(.add, 1)])
        #expect(state.heldPath.isEmpty)
    }

    @Test func anotherSurfaceStartsPlain() {
        let (state, _) = makeState()
        state.keepsCompassColor = true
        state.tablePressed(maj7)
        state.centerSurface = .tree
        #expect(state.tableTones == nil)
        #expect(state.compassPlaces.isEmpty)
    }
}

/// The key assistance on the live surfaces: assisting, a choice out of the
/// key does nothing when pressed, and a color kept out of the key on
/// another chord is not heard.
@Suite("KeyAssistanceState")
@MainActor
struct KeyAssistanceStateTests {

    private func makeState(_ assistance: KeyAssistance) -> (PerformanceState, RecordingSink) {
        let sink = RecordingSink()
        let state = PerformanceState(sink: sink, clock: ManualClock())
        state.keyAssistance = assistance
        return (state, sink)
    }

    /// On I in C major, the compass's first lower is C minor: out of the key.
    private let minorThird = CompassPlace(.lower, 1)
    private let maj7 = ChordTones([0, 4, 7, 11])

    @Test func aPlaceOutOfTheKeyIsPlayedUnlessAssisting() {
        for assistance in [KeyAssistance.none, .colorCode] {
            let (state, sink) = makeState(assistance)
            state.press(.degree(.I))
            state.compassPressed(minorThird)
            #expect(sink.playCalls.last?.notes == [60, 63, 67])
        }
    }

    @Test func assistingAPlaceOutOfTheKeyDoesNothing() {
        let (state, sink) = makeState(.assist)
        state.press(.degree(.I))
        let calls = sink.playCalls.count
        state.compassPressed(minorThird)
        #expect(sink.playCalls.count == calls)
        #expect(state.compassPlaces.isEmpty)
        #expect(!state.placesSound([minorThird]))
        #expect(state.placesSound([CompassPlace(.raise, 1)]))
    }

    /// Before a chord there is no telling, so the place comes down; the
    /// chord struck under it does not take the step out of its key.
    @Test func assistingAPlaceHeldBeforeAChordIsLeftOutIfOutOfItsKey() {
        let (state, sink) = makeState(.assist)
        state.compassPressed(minorThird)
        state.press(.degree(.I))
        #expect(sink.playCalls.last?.notes == [60, 64, 67])
    }

    @Test func assistingAQualityOutOfTheKeyDoesNothing() {
        let (state, sink) = makeState(.assist)
        state.press(.degree(.V))
        let calls = sink.playCalls.count
        state.tablePressed(maj7)
        #expect(sink.playCalls.count == calls)
        #expect(state.tableTones == nil)
    }

    /// maj7 kept on I is out of the key on V, which plays its triad.
    @Test func assistingAQualityKeptIsNotHeardWhereItIsOutOfTheKey() {
        let (state, sink) = makeState(.assist)
        state.keepsCompassColor = true
        state.press(.degree(.I))
        state.tablePressed(maj7)
        #expect(sink.playCalls.last?.notes == [60, 64, 67, 71])
        state.release(.degree(.I))
        state.press(.degree(.V))
        #expect(sink.playCalls.last?.notes == [67, 71, 74])
        #expect(state.tableTones == maj7)
    }

    @Test func switchingToAssistSilencesAColorHeldOutOfTheKey() {
        let (state, sink) = makeState(.colorCode)
        state.keepsCompassColor = true
        state.press(.degree(.V))
        state.tablePressed(maj7)
        #expect(sink.playCalls.last?.notes == [67, 71, 74, 78])
        state.keyAssistance = .assist
        #expect(sink.playCalls.last?.notes == [67, 71, 74])
    }

    @Test func assistingAnOctavesRootOutOfTheKeyIsSilent() {
        let (state, _) = makeState(.assist)
        #expect(state.isSilent(.root(.Cs)))
        #expect(!state.isSilent(.root(.D)))
        #expect(!state.isSilent(.degree(.ii)))
        state.press(.root(.Cs))
        #expect(state.heldKeys.isEmpty)
        let (coded, _) = makeState(.colorCode)
        #expect(!coded.isSilent(.root(.Cs)))
    }
}
