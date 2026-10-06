/// The order an arpeggio visits a chord's notes.
enum ArpeggioPattern: String, CaseIterable, Identifiable, Sendable {
    case up, down, upDown, random

    var id: Self { self }

    var label: String {
        switch self {
        case .up:     return "Up"
        case .down:   return "Down"
        case .upDown: return "Up/Down"
        case .random: return "Random"
        }
    }

    /// One pass over a chord of `count` notes: their positions (0 is the
    /// lowest) in playing order. Up/Down turns round without repeating the
    /// top or bottom note; Random plays every note once, in a new order each
    /// pass.
    func pass(count: Int) -> [Int] {
        let ascending = Array(0..<count)
        switch self {
        case .up:     return ascending
        case .down:   return ascending.reversed()
        case .upDown: return ascending + ascending.dropFirst().dropLast().reversed()
        case .random: return ascending.shuffled()
        }
    }
}

/// How long one pass over a chord takes. The notes share it evenly, so a
/// chord with more notes plays them faster, not for longer.
enum ArpeggioCycle: String, CaseIterable, Identifiable, Sendable {
    case halfBeat, beat, twoBeats, bar

    var id: Self { self }

    /// The cycle in beats, for a control that says its values are beats.
    var label: String {
        switch self {
        case .halfBeat: return "½"
        case .beat:     return "1"
        case .twoBeats: return "2"
        case .bar:      return "Bar"
        }
    }

    var beats: Double {
        switch self {
        case .halfBeat: return 0.5
        case .beat:     return 1
        case .twoBeats: return 2
        case .bar:      return Double(MusicalTime.beatsPerBar)
        }
    }

    /// The cycles in the order the slide plays them, from the bottom of the key.
    private static var slowToFast: [ArpeggioCycle] { allCases.sorted { $0.beats > $1.beats } }

    /// The cycle a slide (0...1) plays: the slowest at the bottom of the key,
    /// the fastest at the top, each with an equal share of the slide.
    static func played(by slide: Float) -> ArpeggioCycle {
        let step = Int(slide.clamped(to: 0...1) * Float(slowToFast.count))
        return slowToFast[min(step, slowToFast.count - 1)]
    }

    /// A slide that plays this cycle: the middle of its share.
    var slide: Float {
        let step = Self.slowToFast.firstIndex(of: self) ?? 0
        return (Float(step) + 0.5) / Float(Self.slowToFast.count)
    }
}

struct ArpeggiatorSettings: Equatable, Sendable, SlidePlayed {
    static var kind: EffectKind { .arpeggiator }

    var isOn = false
    var pattern: ArpeggioPattern = .up
    var cycle: ArpeggioCycle = .beat
    /// The slide plays the cycle.
    var followsSlide = false

    func playing(_ slide: Float) -> ArpeggiatorSettings {
        var played = self
        played.cycle = .played(by: slide)
        return played
    }
}

/// Plays chords one note at a time, in tempo. It sits between whatever
/// produces chord events and the sinks that sound them, so it works the same
/// under every mode, and every sink downstream hears the same notes.
///
/// While off, events pass through untouched. While on:
/// - A chord starts its pattern the moment it arrives: the first note sounds
///   at once and the rest follow evenly, one pass of the pattern every cycle,
///   whatever the chord's own articulation and however many notes it has.
///   A chord that replaces a held one starts the pattern again.
/// - Each note replaces the one before, and carries its chord's context.
/// - `stopChord` ends the pattern.
/// - Switching it on or off, or changing the pattern, re-sounds the held
///   chord the new way. Changing the cycle only changes the speed: the note
///   that is due still comes when it was due, and the ones after it follow at
///   the new spacing, so a cycle that is being played never stalls the notes.
@MainActor
final class Arpeggiator: ChordEventSink {

    var settings = ArpeggiatorSettings() {
        didSet {
            guard let held, settings.isOn || oldValue.isOn else { return }
            if settings.isOn != oldValue.isOn || settings.pattern != oldValue.pattern { begin(held) }
        }
    }

    private let downstream: any ChordEventSink
    private let clock: any ClockTickable

    /// The chord being held, arpeggiated or not.
    private var held: ChordEvent?
    /// The note positions still to play in the current pass, in order.
    private var pass: [Int] = []
    /// The clock's calls for the notes after the first.
    private var noteRepeat: ClockCall?
    /// The spacing `noteRepeat` calls at, in beats.
    private var repeatSpacing = 0.0

    init(downstream: any ChordEventSink, clock: any ClockTickable) {
        self.downstream = downstream
        self.clock = clock
    }

    func playChord(_ event: ChordEvent) {
        held = event
        begin(event)
    }

    func stopChord() {
        held = nil
        noteRepeat?.cancel()
        noteRepeat = nil
        downstream.stopChord()
    }

    // MARK: – Private

    /// Sounds `chord` from its beginning: whole when off, from the first note
    /// of a fresh pass when on.
    private func begin(_ chord: ChordEvent) {
        noteRepeat?.cancel()
        noteRepeat = nil
        let notes = chord.voicing.notes
        guard settings.isOn, !notes.isEmpty else {
            downstream.playChord(chord)
            return
        }
        pass = []
        playNextNote()
        scheduleNotes(spacing: noteSpacing(of: chord))
    }

    /// Beats from one note of `chord` to the next, as the settings stand.
    private func noteSpacing(of chord: ChordEvent) -> Double {
        let notesPerPass = settings.pattern.pass(count: chord.voicing.notes.count).count
        return settings.cycle.beats / Double(notesPerPass)
    }

    private func scheduleNotes(spacing: Double) {
        noteRepeat?.cancel()
        repeatSpacing = spacing
        noteRepeat = clock.every(beats: spacing) { [weak self] in self?.noteDue() }
    }

    /// The clock's call for a note. If the spacing has changed since the
    /// calls were set up (a new cycle, or a held chord with more notes), the
    /// notes after this one follow at the new one.
    private func noteDue() {
        guard let held else { return }
        playNextNote()
        let spacing = noteSpacing(of: held)
        if spacing != repeatSpacing { scheduleNotes(spacing: spacing) }
    }

    private func playNextNote() {
        guard let held else { return }
        let notes = held.voicing.notes
        if pass.isEmpty { pass = settings.pattern.pass(count: notes.count) }
        let note = notes[pass.removeFirst()]
        downstream.playChord(ChordEvent(voicing: Voicing(notes: [note]),
                                        articulation: .block,
                                        context: held.context))
    }
}
