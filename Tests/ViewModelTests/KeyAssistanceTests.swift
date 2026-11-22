import Testing
@testable import Perfecto

/// The key assistance as values: how a choice in the key or out of it is
/// drawn and whether it sounds, and the walk that leaves out a step out of
/// the key while assisting.
@Suite("KeyAssistance")
struct KeyAssistanceTests {
    private let key = Key(root: .C, scale: .major)
    private var triad: ChordTones { StepCompass.base(key: key, degree: .I) }
    /// On I in C major: 3→♭3, C minor, out of the key.
    private let minorThird = CompassPlace(.lower, 1)
    /// On I in C major: 3→4, C sus4, in the key.
    private let sus4 = CompassPlace(.raise, 1)

    @Test func eachAssistanceMarksTheKeyItsOwnWay() {
        #expect(KeyAssistance.none.mark(isInKey: true) == .plain)
        #expect(KeyAssistance.none.mark(isInKey: false) == .plain)
        #expect(KeyAssistance.colorCode.mark(isInKey: true) == .inKey)
        #expect(KeyAssistance.colorCode.mark(isInKey: false) == .outOfKey)
        #expect(KeyAssistance.assist.mark(isInKey: true) == .plain)
        #expect(KeyAssistance.assist.mark(isInKey: false) == .silent)
    }

    /// With no chord held there is no telling what is in the key.
    @Test func nothingIsMarkedWhenItCannotBeTold() {
        for assistance in KeyAssistance.allCases {
            #expect(assistance.mark(isInKey: nil) == .plain)
        }
    }

    @Test func onlyAssistingSilencesWhatIsOutOfTheKey() {
        #expect(KeyAssistance.none.sounds(isInKey: false))
        #expect(KeyAssistance.colorCode.sounds(isInKey: false))
        #expect(!KeyAssistance.assist.sounds(isInKey: false))
        #expect(KeyAssistance.allCases.allSatisfy { $0.sounds(isInKey: true) })
    }

    @Test func anAssistedWalkLeavesOutAStepOutOfTheKey() {
        #expect(KeyAssistance.none.walk([minorThird], from: triad, key: key, degree: .I, ranking: .theory)
                == ChordTones([0, 3, 7]))
        #expect(KeyAssistance.assist.walk([minorThird], from: triad, key: key, degree: .I, ranking: .theory)
                == triad)
        // The steps in the key on either side are still taken.
        #expect(KeyAssistance.assist.walk([minorThird, sus4], from: triad, key: key, degree: .I, ranking: .theory)
                == ChordTones([0, 5, 7]))
    }

    @Test func aPathOutOfTheKeyDoesNotSoundWhileAssisting() {
        #expect(KeyAssistance.assist.sounds([sus4], from: triad, key: key, degree: .I, ranking: .theory))
        #expect(!KeyAssistance.assist.sounds([minorThird], from: triad, key: key, degree: .I, ranking: .theory))
        #expect(KeyAssistance.colorCode.sounds([minorThird], from: triad, key: key, degree: .I, ranking: .theory))
    }
}
