import Testing
@testable import MusicTheoryCore

@Suite("KeyDegree")
struct KeyDegreeTests {

    private let cMajor = Key(root: .C, scale: .major)
    private let cMinor = Key(root: .C, scale: .naturalMinor)

    /// The triad on `root` as `key` has it, as pitch classes from the root up.
    private func triad(on root: PitchClass, in key: Key) -> [Int] {
        let chord = KeyDegree(root: root, in: key)
        let notes = computeVoicing(key: chord.key, spec: ChordSpec(degree: chord.degree, color: .base),
                                   inversion: .root, octave: 4, voiceLeading: false,
                                   previousVoicing: nil).notes
        return notes.map { ($0 - notes[0]) % 12 }
    }

    private let major = [0, 4, 7]
    private let minor = [0, 3, 7]
    private let diminished = [0, 3, 6]

    // MARK: – Notes of the key

    @Test func aNoteOfTheKeyIsItsDegree() {
        #expect(KeyDegree(root: .C, in: cMajor) == KeyDegree(key: cMajor, degree: .I))
        #expect(KeyDegree(root: .D, in: cMajor) == KeyDegree(key: cMajor, degree: .ii))
        #expect(KeyDegree(root: .B, in: cMajor) == KeyDegree(key: cMajor, degree: .viiDim))
        let eMinor = Key(root: .E, scale: .naturalMinor)
        #expect(KeyDegree(root: .C, in: eMinor) == KeyDegree(key: eMinor, degree: .vi))
    }

    @Test func aKeyKnowsTheDegreeOfEachOfItsNotes() {
        #expect(cMajor.degree(of: .G) == .V)
        #expect(cMajor.degree(of: .Fs) == nil)
        #expect(Key(root: .A, scale: .major).degree(of: .Cs) == .iii)
    }

    // MARK: – Notes outside the key

    /// The chords a major key borrows: the flat side's are major, and the
    /// raised fourth's is diminished.
    @Test func aMajorKeyBorrowsFromItsParallelModes() {
        #expect(triad(on: .Cs, in: cMajor) == major)
        #expect(triad(on: .Ds, in: cMajor) == major)
        #expect(triad(on: .Fs, in: cMajor) == diminished)
        #expect(triad(on: .Gs, in: cMajor) == major)
        #expect(triad(on: .As, in: cMajor) == major)
    }

    /// The Neapolitan, and the raised sixth and seventh's diminished chords.
    @Test func aMinorKeyBorrowsFromItsParallelModes() {
        #expect(triad(on: .Cs, in: cMinor) == major)
        #expect(triad(on: .A, in: cMinor) == diminished)
        #expect(triad(on: .B, in: cMinor) == diminished)
    }

    @Test func aBorrowedChordKeepsTheTonicWhereAScaleHasItsMode() {
        #expect(KeyDegree(root: .As, in: cMajor)
                == KeyDegree(key: Key(root: .C, scale: .mixolydian), degree: .viiDim))
        #expect(KeyDegree(root: .Ds, in: cMajor)
                == KeyDegree(key: Key(root: .C, scale: .dorian), degree: .iii))
        #expect(KeyDegree(root: .Gs, in: cMajor)
                == KeyDegree(key: Key(root: .C, scale: .naturalMinor), degree: .vi))
        #expect(KeyDegree(root: .Fs, in: cMajor)
                == KeyDegree(key: Key(root: .C, scale: .lydian), degree: .IV))
    }

    /// No scale is Phrygian, so its chord is read in the relative major.
    @Test func aModeWithNoScaleIsItsRelativeMajor() {
        #expect(KeyDegree(root: .Cs, in: cMajor)
                == KeyDegree(key: Key(root: .Gs, scale: .major), degree: .IV))
    }

    // MARK: – Every root, every key

    @Test func everyRootHasAChordBuiltOnItInEveryKey() {
        for scale in ScaleType.allCases where scale.isHeptatonic {
            for tonic in PitchClass.allCases {
                let key = Key(root: tonic, scale: scale)
                for root in PitchClass.allCases {
                    let chord = KeyDegree(root: root, in: key)
                    #expect(chord.root == root, "\(root.name) in \(tonic.name) \(scale.displayName)")
                    // A borrowed chord's key still has the tonic among its notes.
                    #expect(chord.key.degree(of: tonic) != nil)
                }
            }
        }
    }

    @Test func theSameChordsAreBorrowedInEveryKey() {
        for tonic in PitchClass.allCases {
            let key = Key(root: tonic, scale: .major)
            let flatSeven = PitchClass(rawValue: (tonic.rawValue + 10) % 12)!
            #expect(triad(on: flatSeven, in: key) == major)
        }
    }
}
