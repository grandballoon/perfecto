import Testing
@testable import Perfecto

@Suite("LoopMath")
struct LoopMathTests {

    // MARK: – phase

    @Test func phaseCountsFramesIntoTheCurrentCycle() {
        #expect(LoopMath.phase(of: 100, anchor: 100, period: 40) == 0)
        #expect(LoopMath.phase(of: 135, anchor: 100, period: 40) == 35)
        #expect(LoopMath.phase(of: 140, anchor: 100, period: 40) == 0)
        #expect(LoopMath.phase(of: 1_000_003, anchor: 100, period: 40) == 23)
    }

    @Test func phaseBeforeTheAnchorStillFallsInsideTheLoop() {
        #expect(LoopMath.phase(of: 95, anchor: 100, period: 40) == 35)
        #expect(LoopMath.phase(of: 60, anchor: 100, period: 40) == 0)
        #expect(LoopMath.phase(of: -1, anchor: 100, period: 40) == 19)
    }

    // MARK: – fold

    @Test func foldPlacesAShortTakeAtItsOffset() {
        let loop = LoopMath.fold([[1, 2, 3]], offset: 2, period: 8)
        #expect(loop == [[0, 0, 1, 2, 3, 0, 0, 0]])
    }

    @Test func foldWrapsATakeThatCrossesTheLoopEnd() {
        let loop = LoopMath.fold([[1, 2, 3, 4]], offset: 6, period: 8)
        #expect(loop == [[3, 4, 0, 0, 0, 0, 1, 2]])
    }

    @Test func foldLayersATakeLongerThanTheLoopOverItself() {
        let loop = LoopMath.fold([[1, 2, 3, 4, 5, 6]], offset: 1, period: 4)
        #expect(loop == [[4, 1 + 5, 2 + 6, 3]])
    }

    @Test func foldOfAWholeLoopAtOffsetZeroChangesNothing() {
        let take: [[Float]] = [[1, 2, 3, 4], [5, 6, 7, 8]]
        #expect(LoopMath.fold(take, offset: 0, period: 4) == take)
    }

    @Test func foldKeepsEveryChannel() {
        let loop = LoopMath.fold([[1], [2]], offset: 1, period: 2)
        #expect(loop == [[0, 1], [0, 2]])
    }

    // MARK: – fitted

    @Test func fittedPadsAShortTakeWithSilence() {
        #expect(LoopMath.fitted([[1, 2]], to: 4) == [[1, 2, 0, 0]])
    }

    @Test func fittedCutsALongTake() {
        #expect(LoopMath.fitted([[1, 2, 3, 4]], to: 2) == [[1, 2]])
    }

    // MARK: – fades

    @Test func fadeInStartsSilentAndLeavesTheRestAlone() {
        var channels: [[Float]] = [Array(repeating: 1, count: 16)]
        LoopMath.fadeIn(&channels, frames: 4)
        #expect(channels[0][0] == 0)
        #expect(channels[0][1] > 0 && channels[0][1] < channels[0][2])
        #expect(channels[0][4...].allSatisfy { $0 == 1 })
    }

    @Test func fadeOutEndsSilentAndLeavesTheRestAlone() {
        var channels: [[Float]] = [Array(repeating: 1, count: 16)]
        LoopMath.fadeOut(&channels, frames: 4)
        #expect(channels[0][15] == 0)
        #expect(channels[0][14] > 0 && channels[0][14] < channels[0][13])
        #expect(channels[0][..<12].allSatisfy { $0 == 1 })
    }

    @Test func fadesLongerThanTheTakeDoNotOverrun() {
        var channels: [[Float]] = [[1, 1]]
        LoopMath.fadeIn(&channels, frames: 256)
        LoopMath.fadeOut(&channels, frames: 256)
        #expect(channels[0].count == 2)
    }
}
