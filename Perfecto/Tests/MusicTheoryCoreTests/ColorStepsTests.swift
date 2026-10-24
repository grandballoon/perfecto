import Testing
@testable import MusicTheoryCore

@Suite("ColorSteps")
struct ColorStepsTests {

    private let cMajor = Key(root: .C, scale: .major)

    @Test func eachKindOfStep() {
        #expect(colorSteps([0, 4, 7], [0, 4, 7]) == 0)
        #expect(colorSteps([0, 4, 7], [0, 3, 7]) == 1)          // a note moved a semitone
        #expect(colorSteps([0, 4, 7], [0, 4, 7, 10]) == 1)      // one added
        #expect(colorSteps([0, 4, 7, 10], [0, 4, 7]) == 1)      // one taken away
        #expect(colorSteps([0, 4, 7, 11], [0, 4, 7, 10]) == 1)  // maj7 to 7
        #expect(colorSteps([0, 4, 7], [0, 3, 7, 10]) == 2)      // maj to min7
        #expect(colorSteps([0, 4, 7, 14], [0, 4, 7, 2]) == 0)   // a 9th is its 2nd
    }

    @Test func aMoveFurtherThanATone() {
        // Moving a note more than a tone costs as much as taking it away
        // and adding the other.
        #expect(colorSteps([0, 4, 7], [0, 4, 11]) == 2)
    }

    /// Touching cells on the ring: the same height in the next sector, or
    /// the next height in the same sector. The four that are more than a
    /// step apart are where the stack leaves out a clashing tone.
    @Test func touchingCellsAreOneStepApart() {
        var oneStep = 0, pairs = 0, further: [String] = []
        let modes = ColorRing.modes, heights = StackHeight.allCases
        func color(_ s: Int, _ h: Int) -> ChordColor { .grid(heights[h], modes[s]) }
        func check(_ a: (Int, Int), _ b: (Int, Int)) {
            pairs += 1
            if colorSteps(color(a.0, a.1), color(b.0, b.1), key: cMajor, degree: .I) <= 1 { oneStep += 1 }
            else { further.append("\(modes[a.0]) \(heights[a.1]) – \(modes[b.0]) \(heights[b.1])") }
        }
        for s in modes.indices { for h in heights.indices {
            if s + 1 < modes.count { check((s, h), (s + 1, h)) }
            if h + 1 < heights.count { check((s, h), (s, h + 1)) }
        } }
        #expect(pairs == 58)
        #expect(oneStep == 54)
        #expect(Set(further) == [
            "dorian thirteenth – mixolydian thirteenth",
            "mixolydian eleventh – mixolydian thirteenth",
            "ionian eleventh – ionian thirteenth",
            "ionian eleventh – lydian eleventh",
        ])
    }

    @Test func everyMarkIsOneStep() {
        for mode in ColorRing.modes { for height in StackHeight.allCases {
            let plain = markedStack(mode.intervals, height: height, marks: .none)
            for tone in ChordTone.allCases {
                for offset in [1, -1] {
                    var marks = ToneMarks()
                    marks.toggleMove(tone, by: offset)
                    let moved = markedStack(mode.intervals, height: height, marks: marks)
                    #expect(moved == plain || colorSteps(plain, moved) == 1)
                }
                var skip = ToneMarks()
                skip.toggleSkip(tone)
                let skipped = markedStack(mode.intervals, height: height, marks: skip)
                #expect(skipped == plain || colorSteps(plain, skipped) == 1)
            }
        } }
    }
}
