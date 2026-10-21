import MusicTheoryCore
import Testing

@Suite("Intervals")
struct IntervalTests {

    @Test func anIntervalIsTheSemitonesBetweenTwoNotesWithinAnOctave() {
        #expect(Interval(from: 57, to: 64) == .perfectFifth)
        #expect(Interval(from: 64, to: 57) == .perfectFifth)
        #expect(Interval(from: 60, to: 76) == .majorThird)        // a tenth
        #expect(Interval(from: 60, to: 72) == .octave)
        #expect(Interval(from: 60, to: 84) == .octave)
        #expect(Interval(from: 60, to: 60) == .unison)
    }

    @Test func justIntonationTunesEachIntervalToTheSpecsRatios() {
        let ratios = Interval.allCases.dropFirst().map(\.justRatio.description)
        #expect(ratios == ["16/15", "9/8", "6/5", "5/4", "4/3", "45/32", "3/2", "8/5", "5/3", "16/9",
                           "15/8", "2/1"])
    }

    /// Each just ratio is within a sixth of a semitone of its interval in
    /// equal temperament, and the ratios rise with the intervals.
    @Test func eachJustRatioIsNearItsInterval() {
        var last = 0.0
        for interval in Interval.allCases {
            let ratio = Double(interval.justRatio.numerator) / Double(interval.justRatio.denominator)
            #expect(ratio > last)
            last = ratio
            // 2^(1/6 of a semitone) ≈ 1.0097.
            let tempered = (0..<interval.semitones).reduce(1.0) { value, _ in value * 1.0594630943592953 }
            #expect(ratio / tempered < 1.0097 && tempered / ratio < 1.0097, "\(interval)")
        }
    }

    @Test func aRatioIsInLowestTerms() {
        #expect(Ratio(6, 4) == Ratio(3, 2))
        #expect(Ratio(6, 4).description == "3/2")
    }

    @Test func theConsonancesAreThePerfectIntervalsThirdsAndSixths() {
        #expect(Interval.allCases.filter(\.isConsonant).map(\.shortName)
                == ["P1", "m3", "M3", "P4", "P5", "m6", "M6", "P8"])
    }
}
