import Testing
@testable import MusicTheoryCore

@Suite("ChordNaming")
struct ChordNamingTests {

    private let cMajor = Key(root: .C, scale: .major)
    private let cMinor = Key(root: .C, scale: .naturalMinor)

    // MARK: – Base quality is scale-driven (not a hardcoded I/IV/V = maj table)

    @Test func majorScaleTriadQualities() {
        #expect(triadBase(key: cMajor, degree: .I)      == .major)
        #expect(triadBase(key: cMajor, degree: .ii)     == .minor)
        #expect(triadBase(key: cMajor, degree: .iii)    == .minor)
        #expect(triadBase(key: cMajor, degree: .IV)     == .major)
        #expect(triadBase(key: cMajor, degree: .V)      == .major)
        #expect(triadBase(key: cMajor, degree: .vi)     == .minor)
        #expect(triadBase(key: cMajor, degree: .viiDim) == .dim)
    }

    @Test func naturalMinorScaleTriadQualities() {
        // i, ii°, III, iv, v, VI, VII — the diatonic triads of natural minor.
        // The old label table assumed major-scale qualities and got these wrong.
        #expect(triadBase(key: cMinor, degree: .I)      == .minor)
        #expect(triadBase(key: cMinor, degree: .ii)     == .dim)
        #expect(triadBase(key: cMinor, degree: .iii)    == .major)
        #expect(triadBase(key: cMinor, degree: .IV)     == .minor)
        #expect(triadBase(key: cMinor, degree: .V)      == .minor)
        #expect(triadBase(key: cMinor, degree: .vi)     == .major)
        #expect(triadBase(key: cMinor, degree: .viiDim) == .major)
    }

    // MARK: – Regressions the old duplicated label table produced

    @Test func rightOnMinorDegreeIsMin7NotMaj7() {
        // ii of C major is D minor; ↗right yields Dm7. The old label said "maj7".
        #expect(chordLabel(key: cMajor, spec: ChordSpec(degree: .ii, color: .joystick(.default, .right))) == "D min7")
    }

    @Test func leftOnMajorDegreeIsMinNotDim() {
        // ↖left lowers the 3rd: I major → C minor. The old label said "dim".
        #expect(chordLabel(key: cMajor, spec: ChordSpec(degree: .I, color: .joystick(.default, .left))) == "C min")
    }

    @Test func labelIsCorrectOnNonMajorScale() {
        // The old center label keyed off degree number, so a natural-minor I read
        // "maj". It is actually minor.
        #expect(chordLabel(key: cMinor, spec: ChordSpec(degree: .I, color: .joystick(.default, .center))) == "C min")
        #expect(chordLabel(key: cMinor, spec: ChordSpec(degree: .ii, color: .joystick(.default, .center))) == "D dim")
    }

    // MARK: – Representative labels

    @Test func defaultLabels() {
        #expect(chordLabel(key: cMajor, spec: ChordSpec(degree: .I, color: .joystick(.default, .center))) == "C maj")
        #expect(chordLabel(key: cMajor, spec: ChordSpec(degree: .I, color: .joystick(.default, .right))) == "C maj7")
        #expect(chordLabel(key: cMajor, spec: ChordSpec(degree: .viiDim, color: .joystick(.default, .center))) == "B dim")
        // vi (Am) flipped to major
        #expect(chordLabel(key: cMajor, spec: ChordSpec(degree: .vi, color: .joystick(.default, .up))) == "A maj")
    }

    // MARK: – The label never disagrees with the notes

    @Test func minorFlagInNameImpliesMinorThirdInVoicing() {
        // For every mode/direction, if the quality name for a minor-base degree
        // starts with "min", the sounding voicing must actually contain a minor
        // (not major) third — the label and the notes come from one source, so
        // this holds by construction; the test guards against future drift.
        let directions: [JoystickDirection] = [
            .center, .up, .upRight, .right, .downRight, .down, .downLeft, .left, .upLeft,
        ]
        for mode in [JoystickMode.default, .extended, .chromatic] {
            for dir in directions {
                let spec = ChordSpec(degree: .ii, color: .joystick(mode, dir))  // ii = minor base
                let name = chordQualityName(key: cMajor, spec: spec)
                guard name.hasPrefix("min") else { continue }
                let notes = computeVoicing(key: cMajor, spec: spec,
                                           inversion: .root, octave: 4,
                                           voiceLeading: false, previousVoicing: nil).notes
                let root = notes.min()!
                let intervals = Set(notes.map { ($0 - root) % 12 })
                #expect(intervals.contains(3), "\(mode)/\(dir) named \(name) but has no minor third")
                #expect(!intervals.contains(4), "\(mode)/\(dir) named \(name) but has a major third")
            }
        }
    }

    // MARK: – Degree numerals follow the key's triad qualities

    private func numerals(_ key: Key) -> [String] {
        Degree.allCases.map { degreeNumeral(key: key, degree: $0) }
    }

    @Test func majorKeyNumerals() {
        #expect(numerals(cMajor) == ["I", "ii", "iii", "IV", "V", "vi", "vii°"])
    }

    @Test func naturalMinorNumeralsAgreeWithChordLabels() {
        // The buttons used to read "ii" and "vii°" here while the display said
        // "D dim" and "B♭ maj".
        #expect(numerals(cMinor) == ["i", "ii°", "III", "iv", "v", "VI", "VII"])
    }

    @Test func numeralCaseMatchesTheSoundingTriad() {
        for scale in ScaleType.allCases where scale.isHeptatonic {
            let key = Key(root: .C, scale: scale)
            for degree in Degree.allCases {
                let numeral = degreeNumeral(key: key, degree: degree)
                let label = chordLabel(key: key, spec: ChordSpec(degree: degree, color: .base))
                if label.hasSuffix(" maj") {
                    #expect(numeral == numeral.uppercased(), "\(scale) \(degree): \(numeral) vs \(label)")
                } else {
                    #expect(numeral == numeral.lowercased(), "\(scale) \(degree): \(numeral) vs \(label)")
                    #expect(numeral.hasSuffix("°") == label.hasSuffix(" dim"),
                            "\(scale) \(degree): \(numeral) vs \(label)")
                }
            }
        }
    }

    // MARK: – Key quality

    @Test func keyQuality() {
        let minor: Set<ScaleType> = [.naturalMinor, .harmonicMinor, .melodicMinor, .dorian,
                                     .minorPentatonic, .blues]
        for scale in ScaleType.allCases {
            #expect(Key(root: .D, scale: scale).isMinor == minor.contains(scale), "\(scale)")
        }
    }

    @Test func keyQualityMatchesTheTonicTriadOnSevenNoteScales() {
        for scale in ScaleType.allCases where scale.isHeptatonic {
            let key = Key(root: .D, scale: scale)
            #expect(key.isMinor == (triadBase(key: key, degree: .I) != .major), "\(scale)")
        }
    }

    // MARK: – Ring action legend

    @Test func actionLabelsAreBaseIndependent() {
        #expect(joystickActionLabel(mode: .default, direction: .upRight) == "Dom 7")
        #expect(joystickActionLabel(mode: .default, direction: .center) == "Base")
        #expect(joystickActionLabel(mode: .chromatic, direction: .upLeft) == "Maj7♯11")
    }

    // MARK: – Every entry is populated (no missing names)

    @Test func everyDirectionHasNames() {
        let directions: [JoystickDirection] = [
            .center, .up, .upRight, .right, .downRight, .down, .downLeft, .left, .upLeft,
        ]
        for mode in [JoystickMode.default, .extended, .chromatic] {
            for dir in directions {
                let outcome = JoystickMap.outcome(mode: mode, direction: dir)
                #expect(!outcome.action.isEmpty)
                for base in [TriadBase.major, .minor, .dim] {
                    let shape = outcome.shape(for: base)
                    #expect(!shape.name.isEmpty)
                    #expect(!shape.intervals.isEmpty)
                }
            }
        }
    }
}
