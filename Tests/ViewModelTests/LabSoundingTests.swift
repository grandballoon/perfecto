import Foundation
import Testing
@testable import Perfecto

/// What two keyed notes become in the Dissonance Lab under its settings.
@Suite("LabSounding")
struct LabSoundingTests {

    private let a3 = 57, e4 = 64

    /// Settings with every enhancement off but those asked for.
    private func plain(_ change: (inout LabSettings) -> Void = { _ in }) -> LabSettings {
        var settings = LabSettings()
        settings.spotlight = false
        change(&settings)
        return settings
    }

    private func near(_ a: Double, _ b: Double, within tolerance: Double = 1e-6) -> Bool {
        abs(a - b) <= tolerance
    }

    // MARK: – Pitches

    @Test func closeVoicingPutsTheLowerNoteBetween200And400HzAndTheUpperWithinAnOctave() {
        // A1 and E4: a fifth two octaves wide, keyed far apart.
        let sounding = LabSounding(33, 64, settings: plain())
        #expect(sounding.interval == .perfectFifth)
        #expect(near(sounding.lowHz, 220))
        #expect(near(sounding.highHz, 220 * pow(2, 7.0 / 12)))
    }

    @Test func theOriginalRegisterIsAsKeyed() {
        let sounding = LabSounding(64, 33, settings: plain { $0.voicing = .original })
        #expect(sounding.keyed.low == 33 && sounding.keyed.high == 64)
        #expect(near(sounding.lowHz, 55))
        #expect(near(sounding.highHz, LabSounding.hz(ofMidi: 64)))
    }

    /// Just intonation for consonances only: a fifth is 3/2, and a tritone,
    /// which no ratio settles, stays equal.
    @Test func justForConsonantTunesOnlyTheConsonances() {
        let settings = plain { $0.tuning = .justForConsonant }
        let fifth = LabSounding(a3, e4, settings: settings)
        #expect(fifth.isJust && near(fifth.highHz, 330))
        let tritone = LabSounding(a3, a3 + 6, settings: settings)
        #expect(!tritone.isJust && near(tritone.highHz, 220 * pow(2, 0.5)))
    }

    /// In the original register a compound interval is just by its ratio
    /// and the octaves over it.
    @Test func aJustTenthIsAThirdAnOctaveUp() {
        let sounding = LabSounding(a3, a3 + 16, settings: plain { $0.voicing = .original; $0.tuning = .just })
        #expect(near(sounding.highHz, 220 * 5 / 4 * 2))
    }

    // MARK: – The spotlight

    /// The spotlighted pair's partials are boosted 12 dB, and every other
    /// partial cut 18.
    @Test func theSpotlightBoostsItsPairAndCutsTheRest() {
        let sounding = LabSounding(a3, e4, settings: LabSettings())
        let pair = sounding.spotlit[0].pair
        #expect(pair.low == 3 && pair.high == 2)
        #expect(near(Double(sounding.lowPartials[2].strength), 1.0 / 3 * pow(10, 12.0 / 20), within: 1e-5))
        #expect(near(Double(sounding.highPartials[1].strength), 1.0 / 2 * pow(10, 12.0 / 20), within: 1e-5))
        #expect(near(Double(sounding.lowPartials[0].strength), pow(10, -18.0 / 20), within: 1e-5))
    }

    @Test func withTheSpotlightOffThePartialsFallAwayAsSet() {
        let sounding = LabSounding(a3, e4, settings: plain { $0.partialCount = 8; $0.brightness = 1.5 })
        #expect(sounding.lowPartials.count == 8)
        for (index, partial) in sounding.lowPartials.enumerated() {
            #expect(near(Double(partial.strength), 1 / pow(Double(index + 1), 1.5), within: 1e-6))
        }
    }

    @Test func noTwoSpotlightedPairsShareAPartial() {
        let sounding = LabSounding(a3, a3 + 1, settings: plain { $0.spotlightCount = 3 })
        #expect(sounding.spotlit.count == 3)
        #expect(Set(sounding.spotlit.map(\.pair.low)).count == 3)
        #expect(Set(sounding.spotlit.map(\.pair.high)).count == 3)
    }

    // MARK: – The beat

    /// A wobble moves the spotlighted upper partial alone so its pair beats
    /// five times a second; the rest of the note is where it was.
    @Test func aWobbleMakesTheSpotlightedPairBeatFiveTimesASecond() {
        let sounding = LabSounding(a3, a3 + 1, settings: plain { $0.beatShaping = .wobble })
        let lit = sounding.spotlit[0]
        #expect(lit.beatRate == 5)
        let moved = lit.pair.highHz + Double(sounding.highPartials[lit.pair.high - 1].offset)
        #expect(near(abs(moved - lit.pair.lowHz), 5, within: 1e-3))
        #expect(sounding.highPartials.enumerated().allSatisfy { index, partial in
            index == lit.pair.high - 1 || partial.offset == 0
        })
    }

    /// A just consonance does not beat, and a shaping does not make it.
    @Test func aJustFifthStaysBeatlessUnderAWobble() {
        let sounding = LabSounding(a3, e4, settings: LabLevel.one.settings)
        #expect(sounding.isJust)
        #expect(sounding.spotlit[0].beatRate < LabSounding.beatless)
        #expect(sounding.highPartials.allSatisfy { $0.offset == 0 && $0.depth == 0 })
    }

    @Test func theSwingIsOnBothPartialsOfThePairAtItsBeat() {
        let sounding = LabSounding(a3, a3 + 1, settings: plain { $0.crutch = .modulation; $0.beatShaping = .grit })
        let pair = sounding.spotlit[0].pair
        for partial in [sounding.lowPartials[pair.low - 1], sounding.highPartials[pair.high - 1]] {
            #expect(near(Double(partial.depth), 0.6, within: 1e-6) && partial.rate == 45)
        }
        #expect(sounding.spotlit[0].swing == 0.6)
    }

    @Test func theDifferenceToneIsAtTheBeat() {
        let sounding = LabSounding(a3, a3 + 1, settings: plain { $0.crutch = .differenceTone })
        let tone = sounding.differenceTone
        #expect(tone.map { near($0.hz, sounding.spotlit[0].beatRate) } == true)
        #expect(sounding.lines(velocity: 1)[.difference] != nil)
    }

    // MARK: – The root tone

    /// The root is raised by octaves until it is heard: a major second's
    /// 27.5 Hz is sounded at 55.
    @Test func theRootToneIsRaisedToAtLeast40Hz() {
        let fifth = LabSounding(a3, e4, settings: plain { $0.rootTone = true; $0.tuning = .just })
        #expect(fifth.rootToneHz == 110)
        let second = LabSounding(a3, a3 + 2, settings: plain { $0.rootTone = true; $0.tuning = .just })
        #expect(second.rootToneHz == 55)
        let semitone = LabSounding(a3, a3 + 1, settings: plain { $0.rootTone = true })
        #expect(semitone.rootToneHz == nil)                      // no clear root
        #expect(fifth.lines(velocity: 1)[.root].map { near(LabSounding.hz(ofMidi: $0.pitch), 110) } == true)
    }

    // MARK: – Hearing

    @Test func dichoticIsTheLowNoteLeftAndTheHighRightWithNoSpotlightOrSwing() {
        let sounding = LabSounding(a3, a3 + 1, settings: LabSettings().with {
            $0.isDichotic = true
            $0.crutch = .modulation
        })
        let lines = sounding.lines(velocity: 1)
        #expect(lines[.keyed(a3)]?.pan == -1 && lines[.keyed(a3 + 1)]?.pan == 1)
        #expect(!sounding.settings.spotlight && sounding.settings.crutch == .off)
    }

    /// The A/B button: equal temperament and nothing else, the partials and
    /// the voicing as set.
    @Test func plainIsEqualTemperamentWithNoEnhancement() {
        let sounding = LabSounding(33, 64, settings: LabLevel.one.settings, plain: true)
        #expect(!sounding.isJust)
        #expect(near(sounding.lowHz, 220))                            // still close
        #expect(sounding.lowPartials.count == 12)
        #expect(sounding.rootToneHz == nil && sounding.differenceTone == nil)
        #expect(sounding.lowPartials.allSatisfy { $0.depth == 0 && $0.offset == 0 })
        #expect(near(Double(sounding.lowPartials[0].strength), 1))    // no cut
    }

    @Test func aStruckLevelSoundsThePianosEnvelope() {
        let sounding = LabSounding(a3, e4, settings: LabLevel.five.settings)
        #expect(sounding.lines(velocity: 1).values.allSatisfy { $0.sound == .struck })
        #expect(LabSounding(a3, e4, settings: LabLevel.four.settings).lines(velocity: 1)
            .values.allSatisfy { $0.sound == .held })
    }

    // MARK: – Levels

    @Test func theLevelsFadeTheCrutchesAway() {
        let levels = LabLevel.allCases.map(\.settings)
        #expect(levels.map(\.voicing) == [.close, .close, .close, .close, .original])
        #expect(levels.map(\.partialCount) == [12, 12, 10, 8, 8])
        #expect(levels.map(\.spotlight) == [true, true, true, false, false])
        #expect(levels.map(\.beatShaping) == [.wobble, .grit, .natural, .natural, .natural])
        #expect(levels.map(\.crutch) == [.modulation, .modulation, .off, .off, .off])
        #expect(levels.map(\.rootTone) == [true, true, true, false, false])
        #expect(levels.map(\.tuning) == [.justForConsonant, .equal, .equal, .equal, .equal])
        #expect(levels[4].brightness == 1.5 && levels[4].isStruck)
    }

    @Test func oneNoteAloneIsAsKeyedAndPlain() {
        let lines = LabSounding.single(a3, settings: LabLevel.one.settings, velocity: 0.5)
        #expect(lines.count == 1)
        #expect(lines[.keyed(a3)]?.pitch == Double(a3))
        #expect(lines[.keyed(a3)]?.partials.map(\.strength) == (1...12).map { 1 / Float($0) })
    }
}

extension LabSettings {
    /// These settings with `change` made.
    func with(_ change: (inout LabSettings) -> Void) -> LabSettings {
        var settings = self
        change(&settings)
        return settings
    }
}
