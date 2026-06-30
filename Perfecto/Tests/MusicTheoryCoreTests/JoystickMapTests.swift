import Testing
@testable import MusicTheoryCore

@Suite("JoystickMap")
struct JoystickMapTests {

    private let cMajor = Key(root: .C, scale: .major)

    private func notes(
        key: Key? = nil,
        degree: Degree = .I,
        mode: JoystickMode,
        dir: JoystickDirection
    ) -> [Int] {
        computeVoicing(
            key: key ?? Key(root: .C, scale: .major),
            degree: degree,
            joystickMode: mode,
            joystickDirection: dir,
            inversion: .root,
            octave: 4,
            voiceLeading: false,
            previousVoicing: nil
        ).notes
    }

    // MARK: – Default mode

    @Test func defaultCenter() {
        #expect(notes(mode: .default, dir: .center) == [60, 64, 67])  // C major
    }

    @Test func defaultUpFlipsMajorToMinor() {
        #expect(notes(mode: .default, dir: .up) == [60, 63, 67])  // Cm
    }

    @Test func defaultUpFlipsMinorToMajor() {
        // vi of C major = Am; up should flip to A major
        #expect(notes(degree: .vi, mode: .default, dir: .up) == [69, 73, 76])  // A-C#-E
    }

    @Test func defaultUpRightDom7() {
        #expect(notes(mode: .default, dir: .upRight) == [60, 64, 67, 70])  // C7
    }

    @Test func defaultRightMaj7() {
        // Spec example §4.4: C-E-G-B = Cmaj7
        #expect(notes(mode: .default, dir: .right) == [60, 64, 67, 71])
    }

    @Test func defaultRightMin7OnMinor() {
        // vi = Am; right should give Am7 = A-C-E-G
        #expect(notes(degree: .vi, mode: .default, dir: .right) == [69, 72, 76, 79])
    }

    @Test func defaultDownRightAdd9() {
        // Cadd9 = C-E-G-D(+oct)
        #expect(notes(mode: .default, dir: .downRight) == [60, 64, 67, 74])
    }

    @Test func defaultDownSus4() {
        // Csus4 = C-F-G
        #expect(notes(mode: .default, dir: .down) == [60, 65, 67])
    }

    @Test func defaultDownLeftSixthOnMajor() {
        // C6 = C-E-G-A
        #expect(notes(mode: .default, dir: .downLeft) == [60, 64, 67, 69])
    }

    @Test func defaultDownLeftSus2OnMinor() {
        // ii = Dm; downLeft should give Dsus2 = D-E-A
        #expect(notes(degree: .ii, mode: .default, dir: .downLeft) == [62, 64, 69])
    }

    @Test func defaultLeftMakesMinorFromMajor() {
        #expect(notes(mode: .default, dir: .left) == [60, 63, 67])  // Cm
    }

    @Test func defaultLeftMakesDimFromMinor() {
        // ii = Dm; left should give Ddim = D-F-Ab
        #expect(notes(degree: .ii, mode: .default, dir: .left) == [62, 65, 68])
    }

    @Test func defaultUpLeftAug() {
        // Caug = C-E-G#
        #expect(notes(mode: .default, dir: .upLeft) == [60, 64, 68])
    }

    @Test func defaultCenterOnDiminished() {
        // vii° of C major = Bdim = B-D-F
        #expect(notes(degree: .viiDim, mode: .default, dir: .center) == [71, 74, 77])
    }

    // MARK: – Extended mode

    @Test func extendedUpRightDom9() {
        // C9 = C-E-G-Bb-D
        #expect(notes(mode: .extended, dir: .upRight) == [60, 64, 67, 70, 74])
    }

    @Test func extendedRightAdd11() {
        // Cadd11 = C-E-G-F(+oct)
        #expect(notes(mode: .extended, dir: .right) == [60, 64, 67, 77])
    }

    @Test func extendedDownHendrix() {
        // C7#9 = C-E-G-Bb-D#
        #expect(notes(mode: .extended, dir: .down) == [60, 64, 67, 70, 75])
    }

    @Test func extendedUpLeftHalfDim7() {
        // Cø7 = C-Eb-Gb-Bb
        #expect(notes(mode: .extended, dir: .upLeft) == [60, 63, 66, 70])
    }

    @Test func extendedDownRightMin11ForcesMinor() {
        // Even on degree I (major), min11 forces minor quality
        #expect(notes(mode: .extended, dir: .downRight) == [60, 63, 67, 70, 77])
    }

    @Test func extendedLeftSus4Plus7() {
        // Csus4+7 = C-F-G-Bb
        #expect(notes(mode: .extended, dir: .left) == [60, 65, 67, 70])
    }

    // MARK: – Chromatic mode

    @Test func chromaticUpMinMaj7() {
        // CminMaj7 = C-Eb-G-B; forces minor regardless of major base chord
        #expect(notes(mode: .chromatic, dir: .up) == [60, 63, 67, 71])
    }

    @Test func chromaticRightSixNine() {
        // C6/9 = C-E-G-A-D
        #expect(notes(mode: .chromatic, dir: .right) == [60, 64, 67, 69, 74])
    }

    @Test func chromaticUpLeftMaj7Sharp11() {
        // Cmaj7#11 = C-E-G-B-F#(+oct)
        #expect(notes(mode: .chromatic, dir: .upLeft) == [60, 64, 67, 71, 78])
    }

    @Test func chromaticDownLeftDom7b9() {
        // C7b9 = C-E-G-Bb-Db
        #expect(notes(mode: .chromatic, dir: .downLeft) == [60, 64, 67, 70, 73])
    }

    @Test func chromaticLeftHalfDim7() {
        // Cø7 = C-Eb-Gb-Bb
        #expect(notes(mode: .chromatic, dir: .left) == [60, 63, 66, 70])
    }
}
