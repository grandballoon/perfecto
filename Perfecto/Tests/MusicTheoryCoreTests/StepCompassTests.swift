import Testing
@testable import MusicTheoryCore

@Suite("StepCompass")
struct StepCompassTests {

    private let cMajor = Key(root: .C, scale: .major)
    private let cMinor = Key(root: .C, scale: .naturalMinor)

    private func label(_ tones: ChordTones, on degree: Degree, in key: Key? = nil) -> String {
        chordLabel(key: key ?? cMajor, spec: ChordSpec(degree: degree, color: .tones(tones)))
    }

    private func place(_ place: CompassPlace, on degree: Degree, from tones: ChordTones? = nil,
                       ranking: ColorStepRanking = .theory, in key: Key? = nil) -> String? {
        let key = key ?? cMajor
        let from = tones ?? StepCompass.base(key: key, degree: degree)
        return StepCompass.step(at: place, from: from, key: key, degree: degree, ranking: ranking)
            .map { label($0.tones, on: degree, in: key) }
    }

    // MARK: – Tones and their names

    @Test func tonesAreReadFromAnyColor() {
        #expect(ChordTones(key: cMajor, spec: ChordSpec(degree: .V, color: .grid(.seventh, nil))) == ChordTones([0, 4, 7, 10]))
        #expect(ChordTones(key: cMajor, spec: ChordSpec(degree: .ii, color: .grid(.ninth, nil))) == ChordTones([0, 3, 7, 10, 2]))
        #expect(ChordTones(key: cMajor, spec: ChordSpec(degree: .I, color: .base)) == StepCompass.base(key: cMajor, degree: .I))
    }

    @Test func tonesAreNamedAsTheAppNamesChords() {
        #expect(ChordTones([0, 4, 7]).name == "maj")
        #expect(ChordTones([0, 3, 7, 10]).name == "min7")
        #expect(ChordTones([0, 4, 7, 10, 2]).name == "9")
        #expect(ChordTones([0, 4, 7, 9, 2]).name == "6/9")
        #expect(ChordTones([0, 5, 7]).name == "sus4")
        #expect(ChordTones([0, 5, 7, 10]).name == "7sus4")
        #expect(ChordTones([0, 4, 7, 2]).name == "add9")
        #expect(ChordTones([0, 3, 7, 2]).name == "min add9")
        #expect(ChordTones([0, 4, 7, 10, 1]).name == "7♭9")
        #expect(ChordTones([0, 3, 6, 10]).name == "min7♭5")
        #expect(ChordTones([0, 3, 6, 9]).name == "dim7")
        #expect(ChordTones([0, 4, 8]).name == "aug")
        #expect(ChordTones([0, 7]).name == "5")
        #expect(ChordTones([0, 4]).name == "maj(no5)")
        #expect(ChordTones([0, 4, 7, 11, 9]).name == "maj7(13)")
    }

    /// Every tone in the octave above the root, a tension above the chord
    /// an octave higher, so it stays on top of an inversion.
    @Test func tensionsAreVoicedAnOctaveUp() {
        #expect(ChordTones([0, 4, 7, 10, 2]).intervals == [0, 4, 7, 10, 14])
        #expect(ChordTones([0, 2, 7]).intervals == [0, 2, 7])                  // sus2: the 2nd is the 3rd's place
        #expect(ChordTones([0, 4, 7, 5]).intervals == [0, 4, 7, 17])           // add11
        #expect(ChordTones([0, 4, 7, 10, 9]).intervals == [0, 4, 7, 10, 21])   // 13 over a 7th
        #expect(ChordTones([0, 4, 7, 9]).intervals == [0, 4, 7, 9])            // 6 over none
    }

    @Test func anotherChordOverTheRootIsNamedOverItsBass() {
        #expect(label(ChordTones([0, 3, 8]), on: .iii) == "C/E")
        #expect(label(ChordTones([0, 3, 6, 8]), on: .viiDim) == "G 7/B")
        #expect(label(ChordTones([0, 3, 7, 10]), on: .ii) == "D min7")
    }

    @Test func aToneColorSoundsItsTones() {
        let voicing = computeVoicing(key: cMajor, spec: ChordSpec(degree: .V, color: .tones(ChordTones([0, 4, 7, 10, 2]))),
                                     inversion: .root, octave: 4, voiceLeading: false, previousVoicing: nil)
        #expect(voicing.notes == [67, 71, 74, 77, 81])   // G9
    }

    // MARK: – The places

    /// V in C major, by theory: up adds its own next tones (the 7th, then
    /// the 9th), right raises the 3rd to sus4 then the 5th (borrowed), left
    /// lowers (both borrowed, the 3rd first), down takes the 5th then the 3rd.
    @Test func theDominantsPlaces() {
        #expect(place(CompassPlace(.add, 1), on: .V) == "G 7")
        #expect(place(CompassPlace(.add, 2), on: .V) == "G add9")
        #expect(place(CompassPlace(.raise, 1), on: .V) == "G sus4")
        #expect(place(CompassPlace(.raise, 2), on: .V) == "G aug")
        #expect(place(CompassPlace(.lower, 1), on: .V) == "G min")
        #expect(place(CompassPlace(.lower, 2), on: .V) == "G maj(♭5)")
        #expect(place(CompassPlace(.takeAway, 1), on: .V) == "G maj(no5)")
        #expect(place(CompassPlace(.takeAway, 2), on: .V) == "G 5")
    }

    /// The same place is each degree's own: up is its diatonic 7th.
    @Test func upAddsEachDegreesOwnSeventh() {
        let sevenths = Degree.allCases.map { place(CompassPlace(.add, 1), on: $0) }
        #expect(sevenths == ["C maj7", "D min7", "E min7", "F maj7", "G 7", "A min7", "B min7♭5"])
    }

    @Test func aStepIsFittedToTheKey() {
        let steps = StepCompass.steps(from: StepCompass.base(key: cMajor, degree: .I), key: cMajor, degree: .I, ranking: .theory)
        let add11 = steps[.add]!.first { $0.to == 5 }!
        let addFlat7 = steps[.add]!.first { $0.to == 10 }!
        #expect(add11.fit == .avoid)        // F a semitone over E
        #expect(addFlat7.fit == .borrowed)  // B♭ is not in C major
        #expect(steps[.raise]!.first!.fit == .inKey)   // sus4
        #expect(add11.editName == "+4" && steps[.raise]!.first!.editName == "3→4")
    }

    /// Each kind's choices are its in-key ones first, so a place filled
    /// from outside the key is one that has nothing in it.
    @Test func inKeyComesFirstByTheory() {
        for degree in Degree.allCases {
            let steps = StepCompass.steps(from: StepCompass.base(key: cMajor, degree: degree), key: cMajor,
                                          degree: degree, ranking: .theory)
            for (_, list) in steps {
                #expect(list.map(\.fit) == list.map(\.fit).sorted())
            }
        }
    }

    @Test func commonRankingPutsTheCommonestChordFirst() {
        #expect(place(CompassPlace(.add, 1), on: .I, ranking: .common) == "C 7")
        #expect(place(CompassPlace(.add, 2), on: .I, ranking: .common) == "C maj7")
        #expect(place(CompassPlace(.add, 1), on: .I, ranking: .theory) == "C maj7")
    }

    @Test func aTwoNoteChordHasNothingToTakeAway() {
        let fifth = ChordTones([0, 7])
        #expect(StepCompass.step(at: CompassPlace(.takeAway, 1), from: fifth, key: cMajor, degree: .I, ranking: .theory) == nil)
    }

    /// Every step is one step (`colorSteps`) from the chord it is from.
    @Test func everyStepIsOneStep() {
        for key in [cMajor, cMinor] {
            for degree in Degree.allCases {
                let base = StepCompass.base(key: key, degree: degree)
                for (_, list) in StepCompass.steps(from: base, key: key, degree: degree, ranking: .theory) {
                    for step in list { #expect(colorSteps(base.pitchClasses, step.tones.pitchClasses) == 1) }
                }
            }
        }
    }

    // MARK: – Walks

    /// A walk is of places, so it is each degree's own: two adds are the
    /// 9th chord on V and on ii.
    @Test func aWalkIsEachDegreesOwn() {
        let twoAdds = [CompassPlace(.add, 1), CompassPlace(.add, 1)]
        #expect(label(StepCompass.walk(twoAdds, key: cMajor, degree: .V, ranking: .theory), on: .V) == "G 9")
        #expect(label(StepCompass.walk(twoAdds, key: cMajor, degree: .ii, ranking: .theory), on: .ii) == "D min9")
        #expect(StepCompass.walk([], key: cMajor, degree: .I, ranking: .theory) == ChordTones([0, 4, 7]))
    }

    @Test func aMinorKeysPlacesAreItsOwn() {
        #expect(place(CompassPlace(.add, 1), on: .I, in: cMinor) == "C min7")
        #expect(place(CompassPlace(.lower, 1), on: .I, in: cMinor) == "C sus2")
    }
}
