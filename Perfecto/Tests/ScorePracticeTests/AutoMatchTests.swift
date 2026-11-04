import Foundation
import Testing
@testable import ScorePractice

/// A recording made of `score`, each note a piano-like tone (six harmonics
/// dying away) struck at `heard(onset)` seconds, at `rate` samples a
/// second.
func synthesize(_ score: Score, rate: Double = 22_050, length: Double,
                heard: (Double) -> Double) -> [Float] {
    var samples = [Float](repeating: 0, count: Int(length * rate))
    for note in score.notes {
        let start = heard(note.onset)
        let end = heard(note.end) + 0.3
        let f = 440 * pow(2, Double(note.pitch - 69) / 12)
        let first = Int(start * rate), last = min(samples.count, Int(end * rate))
        guard first < last else { continue }
        for s in first..<last {
            let t = Double(s - first) / rate
            let envelope = min(1, t / 0.005) * exp(-t / 0.9)
            var v = 0.0
            for h in 1...6 where f * Double(h) < rate / 2 {
                v += sin(2 * .pi * f * Double(h) * t) / Double(h)
            }
            samples[s] += Float(0.15 * envelope * v)
        }
    }
    return samples
}

/// A melody over a bass, as a piece would have it: a run of eighths up and
/// down a scale in the right hand over half notes in the left, at 1 s a
/// beat, eight bars.
func piece() -> Score {
    let scale = [60, 62, 64, 65, 67, 69, 71, 72, 74, 72, 71, 69, 67, 65, 64, 62]
    let bass = [48, 43, 45, 41, 48, 43, 45, 41]
    var notes: [ScoreNote] = []
    for bar in 0..<8 {
        for k in 0..<8 {
            let i = bar * 8 + k
            notes.append(ScoreNote(pitch: scale[i % scale.count], onset: Double(i) * 0.5, duration: 0.5,
                                   hand: .right))
        }
        notes.append(ScoreNote(pitch: bass[bar], onset: Double(bar) * 4, duration: 2, hand: .left))
        notes.append(ScoreNote(pitch: bass[bar] + 7, onset: Double(bar) * 4 + 2, duration: 2, hand: .left))
    }
    return Score(title: "Piece", notes: notes)
}

@Suite("AutoMatch")
struct AutoMatchTests {

    /// The performance: a second of silence first, slower than written
    /// (1.3 times), with rubato that swells and eases (a quarter second
    /// either way), a sudden pause in the middle (a second held over the
    /// half second either side of the fourth bar's end), and a ritardando
    /// into the last bars.
    static func heard(_ t: Double) -> Double {
        1 + 1.3 * t + 0.25 * sin(t / 3) + min(1, max(0, t - 15.5)) + 0.02 * max(0, t - 26) * max(0, t - 26)
    }

    static let recording: RecordingFeatures = {
        let score = piece()
        let samples = synthesize(score, length: heard(32) + 2, heard: heard)
        return RecordingFeatures.analyze(samples, sampleRate: 22_050)
    }()

    @Test func everyNoteStruckIsFoundWhereItIsHeard() {
        let score = piece()
        let result = AutoMatch.match(score, Self.recording)
        let onsets = Set(score.notes.map(\.onset)).sorted()
        #expect(result.anchors.map(\.score) == onsets)
        let errors = result.anchors.map { abs($0.recording - Self.heard($0.score)) }
        // Within 30 ms, the length of a frame of film, every one.
        #expect(errors.max()! < 0.03, "worst \(errors.max()!) s")
        #expect(result.unsure.isEmpty)
    }

    @Test func thePathPassesThroughEveryPin() {
        let score = piece()
        // A pin a little off where the note is heard: the learner wins.
        let pin = AlignmentAnchor(score: 16, recording: Self.heard(16) + 0.08)
        let result = AutoMatch.match(score, Self.recording, pins: [pin])
        let alignment = Alignment.merged(pins: [pin], matched: result.anchors)
        #expect(Alignment.recordingTime(16, alignment) == pin.recording)
        #expect(!result.anchors.contains { abs($0.score - 16) < Score.sameTime })
        // The music either side still lines up.
        for t in [4.0, 10.0, 22.0, 28.0] {
            #expect(abs(Alignment.recordingTime(t, alignment) - Self.heard(t)) < 0.03)
        }
        #expect(zip(alignment, alignment.dropFirst()).allSatisfy { $0.recording < $1.recording })
    }

    @Test func aStretchThatIsNotInTheScoreIsDoubted() {
        // Four seconds of a cluster the score never has, in the middle.
        let score = piece()
        var samples = synthesize(score, length: Self.heard(32) + 6) { t in
            Self.heard(t) + (t >= 16 ? 4 : 0)
        }
        let noise = Score(title: "", notes: (0..<8).map {
            ScoreNote(pitch: 61 + ($0 % 2) * 5, onset: Double($0) * 0.5, duration: 0.5, hand: .right)
        })
        let extra = synthesize(noise, length: Self.heard(32) + 6) { Self.heard(16) + $0 }
        for i in samples.indices { samples[i] += extra[i] }
        let result = AutoMatch.match(score, RecordingFeatures.analyze(samples, sampleRate: 22_050))
        #expect(result.unsure.contains { abs($0 - Self.heard(16)) < 4.5 })
        // And the music after it is still found.
        let late = result.anchors.first { $0.score == 24 }!
        #expect(abs(late.recording - (Self.heard(24) + 4)) < 0.05)
    }

    /// The hardest kind of piece to match: a melody held over the same
    /// chord struck again and again, changing a note at a time, played with
    /// the pedal down (every note rings on) and with rubato. One repeated
    /// chord sounds like the next, so only the strikes and the pace tell
    /// them apart. (A sudden pause in the middle of such a run can still
    /// put the chords after it one out: that is for a nudge.)
    @Test func repeatedChordsUnderAHeldMelodyAreFoundOneByOne() {
        // Eighths a half second apart for forty seconds; a chord changes one
        // note every second chord, the melody a note every four seconds.
        var chord = [52, 55, 59]
        var notes: [ScoreNote] = []
        for k in 0..<80 {
            if k > 0, k % 2 == 0 {
                let voice = (k / 2) % 3
                chord[voice] -= 1
            }
            for pitch in chord {
                notes.append(ScoreNote(pitch: pitch, onset: Double(k) * 0.5, duration: 0.5, hand: .left))
            }
            if k % 8 == 0 {
                notes.append(ScoreNote(pitch: 71 - (k / 8) % 4, onset: Double(k) * 0.5, duration: 4, hand: .right))
            }
        }
        let score = Score(title: "Held", notes: notes)
        func heard(_ t: Double) -> Double {
            1.5 + 1.15 * t + 0.5 * sin(t / 7)
        }
        let pedalled = Score(title: "", notes: notes.map {
            ScoreNote(pitch: $0.pitch, onset: $0.onset, duration: $0.duration + 1.2, hand: $0.hand)
        })
        let samples = synthesize(pedalled, length: heard(40) + 3, heard: heard)
        let result = AutoMatch.match(score, RecordingFeatures.analyze(samples, sampleRate: 22_050))
        let errors = result.anchors.map { abs($0.recording - heard($0.score)) }
        let close = errors.filter { $0 < 0.03 }.count
        #expect(Double(close) >= 0.95 * Double(errors.count), "\(close) of \(errors.count) within 30 ms")
        #expect(errors.max()! < 0.3, "worst \(errors.max()!) s")
        #expect(result.unsure.isEmpty)
    }

    @Test func silenceIsNotMatched() {
        let result = AutoMatch.match(piece(), RecordingFeatures.analyze([Float](repeating: 0, count: 22_050),
                                                                        sampleRate: 22_050))
        #expect(result.anchors.allSatisfy { $0.recording >= 0 })
    }

    @Test func aPureToneLandsOnItsPitchClass() {
        let samples = (0..<22_050).map { Float(sin(2 * Double.pi * 440 * Double($0) / 22_050)) }
        let features = RecordingFeatures.analyze(samples, sampleRate: 22_050)
        let middle = Array(features.frame(features.frames / 2))
        #expect(middle.firstIndex(of: middle.max()!) == 9)
    }
}

@Suite("Alignment merged")
struct AlignmentMergedTests {

    @Test func pinsWinAndMatchedAnchorsThatDisagreeGo() {
        let matched = (0...8).map { AlignmentAnchor(score: Double($0), recording: Double($0) + 1) }
        // A pin at score 4 heard at 7.5: anchors 5 and 6 (heard at 6 and 7)
        // are now heard before it, so they go.
        let merged = Alignment.merged(pins: [AlignmentAnchor(score: 4, recording: 7.5)], matched: matched)
        #expect(merged.map(\.score) == [0, 1, 2, 3, 4, 7, 8])
        #expect(merged[4].recording == 7.5)
    }

    @Test func withNoPinsTheMatchIsTheAlignment() {
        let matched = [AlignmentAnchor(score: 0, recording: 1)]
        #expect(Alignment.merged(pins: [], matched: matched) == matched)
    }
}

@Suite("Nudge points")
struct NudgePointTests {

    @Test func aMomentIsTaggedOnceAndUntagged() {
        var practice = Practice(score: piece())
        practice = practice.tagging(5).tagging(2).tagging(5.1)
        #expect(practice.nudges == [2, 5])
        practice = practice.untagging(5.2)
        #expect(practice.nudges == [2])
    }

    @Test func theMatchsDoubtsAreNudgePointsToo() {
        let practice = Practice(score: piece())
            .matching(AutoMatch.Result(anchors: [], unsure: [3]))
            .tagging(1)
        #expect(practice.nudgePoints == [1, 3])
        #expect(practice.untagging(3).nudgePoints == [1])
    }

    @Test func aPracticeSavedBeforeTheMatchIsReadWithNone() throws {
        let old = #"{"right":{"id":1,"first":0,"last":3,"children":[]},"anchors":[],"nextID":2}"#
        let practice = try JSONDecoder().decode(Practice.self, from: Data(old.utf8))
        #expect(practice.matched.isEmpty)
        #expect(practice.nudges.isEmpty)
        #expect(practice.root(.right)?.steps == 0...3)
        let again = try JSONDecoder().decode(Practice.self, from: JSONEncoder().encode(practice.tagging(2)))
        #expect(again.nudges == [2])
    }
}
