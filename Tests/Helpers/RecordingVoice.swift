@testable import Perfecto

/// Recording double for TimelineVoice: what a layer was asked to play, and
/// whether it is sounding.
@MainActor
final class RecordingVoice: TimelineVoice {

    enum Call: Equatable {
        case play(TimedChord)
        case change(TimedChord)
        case stop
    }

    private(set) var calls: [Call] = []

    /// The chords played, in order.
    var played: [TimedChord] { calls.compactMap { if case let .play(chord) = $0 { chord } else { nil } } }
    /// The degrees of the chords played, in order.
    var degrees: [Degree] { played.map(\.event.context.spec.degree) }
    var stopCount: Int { calls.filter { $0 == .stop }.count }
    /// The chord sounding now.
    var sounding: TimedChord? {
        if case let .play(chord) = calls.last { chord } else { nil }
    }

    func play(_ chord: TimedChord) { calls.append(.play(chord)) }
    func change(to chord: TimedChord) { calls.append(.change(chord)) }
    func stop() { calls.append(.stop) }
    func reset() { calls = [] }
}
