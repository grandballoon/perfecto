import Acoustics
import Foundation
import Testing

@Suite("Interval analysis")
struct IntervalAnalyzerTests {

    private static let a3 = 220.0

    /// A note of ten partials falling away as a sawtooth's do.
    private func tone(_ hz: Double, partials: Int = 10) -> Tone {
        Tone(fundamental: hz, partials: partials, brightness: 1)
    }

    private func tempered(_ semitones: Int, over hz: Double = a3) -> Double {
        hz * pow(2, Double(semitones) / 12)
    }

    // MARK: – The measures

    @Test func theCriticalBandIsGlasbergAndMoores() {
        #expect(abs(IntervalAnalyzer.erb(1000) - 132.639) < 1e-9)
        #expect(abs(IntervalAnalyzer.erb(0) - 24.7) < 1e-9)
    }

    /// Two sines at 440 Hz and a semitone over it, worked by hand from
    /// Sethares' formula: s = 0.24 / (0.0207 · 440 + 18.96) and
    /// d = e^(−3.5 s Δf) − e^(−5.75 s Δf), with Δf = 26.16 Hz.
    @Test func roughnessIsPlompAndLeveltsAsSetharesWritesIt() {
        let found = IntervalAnalyzer.roughness(440, 466.16, strengths: (1, 1))
        #expect(abs(found - 0.180758) < 1e-6)
        // The weaker of the two is what is rough.
        #expect(abs(IntervalAnalyzer.roughness(466.16, 440, strengths: (0.5, 2)) - 0.5 * 0.180758) < 1e-6)
        #expect(IntervalAnalyzer.roughness(440, 440, strengths: (1, 1)) == 0)
    }

    /// The curve rises from one pitch to its peak a fraction of a band apart,
    /// and falls again towards the band's edge.
    @Test func roughnessPeaksPartWayAcrossTheBand() {
        let rough = { (apart: Double) in IntervalAnalyzer.roughness(500, 500 + apart, strengths: (1, 1)) }
        #expect(rough(2) < rough(10))
        #expect(rough(10) < rough(25))
        #expect(rough(25) > rough(80))
    }

    // MARK: – The pairs

    /// The fifth over A3: the third partial of A and the second of E are
    /// the pair that beats, slowly in equal temperament (0.74 Hz) and not
    /// at all in just intonation.
    @Test(arguments: [(false, 0.745), (true, 0.0)])
    func aFifthsSpotlightIsTheThirdPartialAgainstTheSecond(just: Bool, beat: Double) {
        let fifth = just ? Self.a3 * 3 / 2 : tempered(7)
        let analysis = IntervalAnalyzer.analyze(low: tone(Self.a3), high: tone(fifth))
        let pair = analysis.spotlight(1).first
        #expect(pair?.low == 3 && pair?.high == 2)
        #expect(abs((pair?.beatRate ?? -1) - beat) < 0.01)
    }

    /// A minor second's pair is the two fundamentals, beating 13 times a
    /// second.
    @Test func aMinorSecondsSpotlightIsTheFundamentals() {
        let analysis = IntervalAnalyzer.analyze(low: tone(Self.a3), high: tone(tempered(1)))
        let pair = analysis.spotlight(1).first
        #expect(pair?.low == 1 && pair?.high == 1)
        #expect(abs((pair?.beatRate ?? 0) - 13.08) < 0.01)
        #expect(analysis.pairs.first == pair)                            // and is the roughest
    }

    @Test func aMinorSecondIsRougherThanAFifthInTheSameRegister() {
        let second = IntervalAnalyzer.analyze(low: tone(Self.a3), high: tone(tempered(1)))
        let fifth = IntervalAnalyzer.analyze(low: tone(Self.a3), high: tone(tempered(7)))
        #expect(second.totalRoughness > 3 * fifth.totalRoughness)
    }

    /// Only partials closer than a critical band collide, the roughest are
    /// first, and the total is theirs added.
    @Test func thePairsAreThoseWithinABandRoughestFirst() {
        let analysis = IntervalAnalyzer.analyze(low: tone(Self.a3), high: tone(tempered(4)))
        #expect(!analysis.pairs.isEmpty)
        for pair in analysis.pairs {
            #expect(pair.beatRate < IntervalAnalyzer.erb((pair.lowHz + pair.highHz) / 2))
            #expect(pair.separation >= 0 && pair.separation < 1)
        }
        let roughness = analysis.pairs.map(\.roughness)
        #expect(roughness == roughness.sorted(by: >))
        #expect(abs(analysis.totalRoughness - roughness.reduce(0, +)) < 1e-12)
    }

    /// A partial set to nothing is not there to collide.
    @Test func aSilentPartialCollidesWithNothing() {
        var low = tone(Self.a3)
        low.strengths[2] = 0
        let analysis = IntervalAnalyzer.analyze(low: low, high: tone(Self.a3 * 3 / 2))
        #expect(!analysis.pairs.contains { $0.low == 3 })
    }

    // MARK: – Shaping a beat

    @Test func theUpperPartialIsMovedToBeatAtTheRateAsked() {
        let analysis = IntervalAnalyzer.analyze(low: tone(Self.a3), high: tone(tempered(7)))
        let pair = analysis.spotlight(1)[0]
        let offset = pair.offset(toBeatAt: 5)
        #expect(abs(abs(pair.highHz + offset - pair.lowHz) - 5) < 1e-9)
        // It stays on the side it was on: the tempered fifth's E is flat.
        #expect(pair.highHz + offset < pair.lowHz)
        // Two partials at one pitch are pulled apart upwards.
        let just = IntervalAnalyzer.analyze(low: tone(Self.a3), high: tone(Self.a3 * 3 / 2)).spotlight(1)[0]
        #expect(abs(just.offset(toBeatAt: 45) - 45) < 1e-9)
    }

    @Test func theBeatsEnvelopeSwingsFromTheDifferenceToTheSum() {
        let pair = IntervalAnalyzer.analyze(low: tone(Self.a3), high: tone(tempered(1))).spotlight(1)[0]
        #expect(abs(pair.envelope(at: 0) - (pair.lowStrength + pair.highStrength)) < 1e-9)
        let trough = pair.envelope(at: 0.5 / pair.beatRate)
        #expect(abs(trough - abs(pair.lowStrength - pair.highStrength)) < 1e-9)
    }

    // MARK: – The implied root

    @Test func aJustFifthImpliesTheRootAnOctaveUnderItsLowerNote() {
        let root = IntervalAnalyzer.impliedRoot(low: Self.a3, high: Self.a3 * 3 / 2)
        #expect(root == ImpliedRoot(numerator: 3, denominator: 2, hz: 110))
    }

    /// Equal temperament's thirds are some way off 5/4 and 6/5, and are
    /// still heard as them.
    @Test func aTemperedThirdImpliesTheJustThirdsRoot() {
        let major = IntervalAnalyzer.impliedRoot(low: Self.a3, high: tempered(4))
        #expect(major?.numerator == 5 && major?.denominator == 4)
        let minor = IntervalAnalyzer.impliedRoot(low: Self.a3, high: tempered(3))
        #expect(minor?.numerator == 6 && minor?.denominator == 5)
    }

    /// Just intonation's tritone is 45/32, past the denominators a root is
    /// heard by; the nearest it comes to a simple one (7/5) has a root far
    /// under both notes.
    @Test func aJustTritoneImpliesNoClearRootOrAVeryLowOne() {
        let root = IntervalAnalyzer.impliedRoot(low: Self.a3, high: Self.a3 * 45 / 32)
        if let root { #expect(root.hz <= Self.a3 / 4) }
    }

    /// A root under 20 Hz is not heard as a pitch: a minor second's.
    @Test func aMinorSecondImpliesNoClearRoot() {
        #expect(IntervalAnalyzer.impliedRoot(low: Self.a3, high: Self.a3 * 16 / 15) == nil)
        #expect(IntervalAnalyzer.impliedRoot(low: Self.a3, high: tempered(1)) == nil)
    }

    @Test func aUnisonAndAnOctaveImplyTheLowerNote() {
        #expect(IntervalAnalyzer.impliedRoot(low: Self.a3, high: Self.a3)?.hz == Self.a3)
        #expect(IntervalAnalyzer.impliedRoot(low: Self.a3, high: Self.a3 * 2)?.hz == Self.a3)
    }

    // MARK: – The meter

    @Test func theMeterIsOneForAMinorSecondAndLessForAFifth() {
        let low = tone(Self.a3)
        #expect(abs(IntervalAnalyzer.roughnessBesideMinorSecond(low: low, high: tone(tempered(1))) - 1) < 1e-9)
        let fifth = IntervalAnalyzer.roughnessBesideMinorSecond(low: low, high: tone(tempered(7)))
        #expect(fifth > 0 && fifth < 0.3)
    }
}
