/// The stretch of the recording the practice screen's timelines show: the
/// recording's outline and the score's notes, one above the other, on the
/// same seconds of the recording.
///
/// It is moved and sized as a value, so the screen only draws it: dragged
/// along (`panned`), pinched about a moment (`zoomed`), brought to a moment
/// out of view (`revealing`), or turned like a page by the playhead while
/// the recording plays (`paging`). Every result is kept within the
/// recording and never shorter than `shortest`.
struct RecordingWindow: Equatable, Sendable {
    /// Recording seconds.
    let start: Double
    let length: Double

    /// The shortest stretch shown, in seconds: a few hundredths of a second
    /// to a point of the screen, close enough to set a note by.
    static let shortest = 0.25
    /// Room either side of a stretch shown whole, as a share of its length,
    /// and at least `leastRoom` seconds.
    static let room = 0.08
    static let leastRoom = 0.5
    /// How near either end a moment revealed may be, as a share of the
    /// window.
    static let margin = 0.1

    var end: Double { start + length }

    init(start: Double, length: Double) {
        self.start = start
        self.length = length
    }

    /// `span` with a little room either side, within a recording of
    /// `recording` seconds; the whole recording for a span too short to
    /// show by itself.
    init(showing span: ClosedRange<Double>, in recording: Double) {
        let pad = max(Self.leastRoom, (span.upperBound - span.lowerBound) * Self.room)
        let low = max(0, span.lowerBound - pad)
        let high = min(recording, span.upperBound + pad)
        self = high - low >= Self.shortest
            ? RecordingWindow(start: low, length: high - low)
            : RecordingWindow(start: 0, length: recording).clamped(to: recording)
    }

    /// `seconds` either side of `time`, within the recording.
    init(around time: Double, reach seconds: Double, in recording: Double) {
        self = RecordingWindow(start: time - seconds, length: 2 * seconds).clamped(to: recording)
    }

    /// The moment at `share` of the way across (0 at the start, 1 at the
    /// end).
    func time(at share: Double) -> Double {
        start + share * length
    }

    /// How far across `time` is (0 at the start, 1 at the end; outside
    /// those when it is out of view).
    func share(of time: Double) -> Double {
        (time - start) / length
    }

    func contains(_ time: Double) -> Bool {
        time >= start && time <= end
    }

    /// Moved `seconds` later (earlier for less than 0), within the
    /// recording.
    func panned(by seconds: Double, in recording: Double) -> RecordingWindow {
        RecordingWindow(start: start + seconds, length: length).clamped(to: recording)
    }

    /// `factor` times closer (farther for less than 1), with `time` staying
    /// where it is on the screen: a pinch about it.
    func zoomed(by factor: Double, around time: Double, in recording: Double) -> RecordingWindow {
        guard factor > 0 else { return self }
        let longest = max(recording, Self.shortest)
        let next = min(max(length / factor, Self.shortest), longest)
        let share = self.share(of: time)
        return RecordingWindow(start: time - share * next, length: next).clamped(to: recording)
    }

    /// Centred on `time`, keeping its length.
    func centred(on time: Double, in recording: Double) -> RecordingWindow {
        RecordingWindow(start: time - length / 2, length: length).clamped(to: recording)
    }

    /// Itself if `time` is in view and not at its very edge (`margin`), and
    /// otherwise centred on it.
    func revealing(_ time: Double, in recording: Double) -> RecordingWindow {
        let share = self.share(of: time)
        return share >= Self.margin && share <= 1 - Self.margin ? self : centred(on: time, in: recording)
    }

    /// The page of its length that holds `time`, counted from where it
    /// starts, so a playhead that runs off its end turns it over a whole
    /// page and never drags it along a frame at a time.
    func paging(to time: Double, in recording: Double) -> RecordingWindow {
        guard !contains(time), length > 0 else { return self }
        let pages = ((time - start) / length).rounded(.down)
        return RecordingWindow(start: start + pages * length, length: length).clamped(to: recording)
    }

    /// Within a recording of `recording` seconds: no longer than it, and
    /// moved, not shortened, to lie inside it.
    func clamped(to recording: Double) -> RecordingWindow {
        let total = max(recording, Self.shortest)
        let length = min(max(self.length, Self.shortest), total)
        let start = min(max(self.start, 0), total - length)
        return RecordingWindow(start: start, length: length)
    }
}
