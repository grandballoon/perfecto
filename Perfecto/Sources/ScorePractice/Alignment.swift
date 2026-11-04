/// A score put to the timing of a recording of it, as harmonicland puts
/// one: by anchors, each a moment of the score and where the recording has
/// it, and evenly in between.
///
/// The score moves, not the recording: a recording is listened to for its
/// rubato, so the score's seconds are bent to the recording's and the
/// recording is never stretched.
///
/// The anchors are the piece's, not a hand's: both hands are played in the
/// one recording, so a run of the right hand matched to the recording
/// also places the left hand's notes at that moment. An anchor is set
/// wherever a run begins or ends (`Practice.settingStart`, `settingEnd`), and the
/// notes between two anchors share out the recording's time in the
/// proportions the score gives them. Before the first anchor and after
/// the last, the recording keeps the pace of the nearest stretch between
/// two, or the score's own with only one.
struct AlignmentAnchor: Equatable, Codable, Sendable {
    /// Score seconds.
    let score: Double
    /// Recording seconds.
    let recording: Double
}

enum Alignment {

    /// `anchors` with `anchor` set: the old anchor at its moment of the
    /// score goes, and so does any it now contradicts, one of the score
    /// before it heard after it or one after it heard before it.
    static func set(_ anchor: AlignmentAnchor, in anchors: [AlignmentAnchor]) -> [AlignmentAnchor] {
        let kept = anchors.filter {
            ($0.score < anchor.score - Score.sameTime && $0.recording < anchor.recording)
                || ($0.score > anchor.score + Score.sameTime && $0.recording > anchor.recording)
        }
        return (kept + [anchor]).sorted { $0.score < $1.score }
    }

    /// Where the recording has `score` seconds of the score.
    static func recordingTime(_ score: Double, _ anchors: [AlignmentAnchor]) -> Double {
        map(score, anchors, from: \.score, to: \.recording)
    }

    /// The moment of the score the recording has at `recording` seconds.
    static func scoreTime(_ recording: Double, _ anchors: [AlignmentAnchor]) -> Double {
        map(recording, anchors, from: \.recording, to: \.score)
    }

    private static func map(_ t: Double, _ anchors: [AlignmentAnchor],
                            from: KeyPath<AlignmentAnchor, Double>, to: KeyPath<AlignmentAnchor, Double>) -> Double {
        guard let first = anchors.first else { return t }
        guard anchors.count > 1 else { return t - first[keyPath: from] + first[keyPath: to] }
        // The stretch that holds `t`, or the nearest one at either end.
        let after = anchors.firstIndex { $0[keyPath: from] > t } ?? anchors.count
        let k = min(max(after - 1, 0), anchors.count - 2)
        let a = anchors[k], b = anchors[k + 1]
        let pace = (b[keyPath: to] - a[keyPath: to]) / (b[keyPath: from] - a[keyPath: from])
        return a[keyPath: to] + (t - a[keyPath: from]) * pace
    }
}
