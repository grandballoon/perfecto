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
        #expect(chordLabel(key: cMajor, degree: .ii,
                           joystickMode: .default, joystickDirection: .right) == "D min7")
    }

    @Test func leftOnMajorDegreeIsMinNotDim() {
        // ↖left lowers the 3rd: I major → C minor. The old label said "dim".
        #expect(chordLabel(key: cMajor, degree: .I,
                           joystickMode: .default, joystickDirection: .left) == "C min")
    }

    @Test func labelIsCorrectOnNonMajorScale() {
        // The old center label keyed off degree number, so a natural-minor I read
        // "maj". It is actually minor.
        #expect(chordLabel(key: cMinor, degree: .I,
                           joystickMode: .default, joystickDirection: .center) == "C min")
        #expect(chordLabel(key: cMinor, degree: .ii,
                           joystickMode: .default, joystickDirection: .center) == "D dim")
    }

    // MARK: – Representative labels

    @Test func defaultLabels() {
        #expect(chordLabel(key: cMajor, degree: .I,
                           joystickMode: .default, joystickDirection: .center) == "C maj")
        #expect(chordLabel(key: cMajor, degree: .I,
                           joystickMode: .default, joystickDirection: .right) == "C maj7")
        #expect(chordLabel(key: cMajor, degree: .viiDim,
                           joystickMode: .default, joystickDirection: .center) == "B dim")
        // vi (Am) flipped to major
        #expect(chordLabel(key: cMajor, degree: .vi,
                           joystickMode: .default, joystickDirection: .up) == "A maj")
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
                let name = chordQualityName(key: cMajor, degree: .ii,   // ii = minor base
                                            joystickMode: mode, joystickDirection: dir)
                guard name.hasPrefix("min") else { continue }
                let notes = computeVoicing(key: cMajor, degree: .ii,
                                           joystickMode: mode, joystickDirection: dir,
                                           inversion: .root, octave: 4,
                                           voiceLeading: false, previousVoicing: nil).notes
                let root = notes.min()!
                let intervals = Set(notes.map { ($0 - root) % 12 })
                #expect(intervals.contains(3), "\(mode)/\(dir) named \(name) but has no minor third")
                #expect(!intervals.contains(4), "\(mode)/\(dir) named \(name) but has a major third")
            }
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
