import Foundation

/// What plays a piece's score: stretches of it, one after another and over
/// again if asked, and the moment of it being heard.
@MainActor
protocol PracticePlaying: AnyObject {
    /// Sounds `notes` through `segments` in order, beginning where
    /// `Playback.start` says for the playhead standing at `from`, and again
    /// from the first after the last while `repeats`; anything playing
    /// stops first.
    func play(_ notes: [ScoreNote], _ segments: [Segment], from: Double, repeats: Bool)
    func stop()
    var isPlaying: Bool { get }
    /// The moment of the score being heard, in its seconds.
    var currentTime: Double { get }
    /// Called when the segments have all played, if they do not repeat.
    var onFinish: (() -> Void)? { get set }
    /// `pitch` sounded at once, as a key tapped on the piano is, until it
    /// is let go (`release`); a key pressed again while held is struck again.
    func press(_ pitch: Int)
    func release(_ pitch: Int)
    /// `notes` sounded from now, timed from it, as a step is heard when the
    /// playhead is stepped to it; what was sounded so before is let go.
    func sound(_ notes: [PassNote])
}

/// The score played on the app's own sound, as notes: each pass
/// (`Playback.pass`) is a list of notes timed from its start, which are
/// sent a little ahead of their moments, stamped with them, so the sinks
/// sound each on its exact frame however late the main thread is.
///
/// The moment heard is worked out from the clock's time and the pass, so
/// the piano is lit by the same reckoning the notes are sounded by.
@MainActor
final class ScorePlayer: PracticePlaying {

    var onFinish: (() -> Void)?
    private(set) var isPlaying = false

    private let sinks: [any NoteSink]
    private let clock: any ClockTickable
    private let sound: NoteSound

    private var notes: [ScoreNote] = []
    private var segments: [Segment] = []
    private var repeats = false
    /// The pass playing, and the moment of the clock it began at.
    private var pass = PlayPass(stretches: [], notes: [])
    private var passStart: TimeInterval = 0
    /// How many of the pass's notes have been struck.
    private var struck = 0
    /// The notes sent to sound that have not ended yet: when each is
    /// struck and let go, and whether its end has been sent. An end is
    /// sent only once it is near, as a note is, so the kernel's list of
    /// what is to come stays short.
    private var live: [(id: NoteID, on: TimeInterval, end: TimeInterval, isEndSent: Bool)] = []
    private var pump: ClockCall?
    /// The keys tapped on the piano and held, each with its note.
    private var pressed: [Int: NoteID] = [:]
    /// The notes of the step last stepped to, each with the call that ends it.
    private var stepped: [(id: NoteID, end: ClockCall)] = []

    /// How far ahead of their moments notes are sent, and how often.
    private static let lookahead: TimeInterval = 0.25
    private static let interval: TimeInterval = 0.05
    /// How long after play is asked for its first note sounds, so it is
    /// sent ahead of its moment too.
    private static let lead: TimeInterval = 0.05

    /// The sound the score is played in.
    static let practiceSound = NoteSound(preset: .electricPiano, level: 0.8)

    init(sinks: [any NoteSink], clock: any ClockTickable, sound: NoteSound = ScorePlayer.practiceSound) {
        self.sinks = sinks
        self.clock = clock
        self.sound = sound
    }

    func play(_ notes: [ScoreNote], _ segments: [Segment], from: Double, repeats: Bool) {
        stop()
        // The step last stepped to is let go: the score takes over.
        sound([])
        guard let start = Playback.start(at: from, in: segments) else { return }
        self.notes = notes
        self.segments = segments
        self.repeats = repeats
        begin(Playback.pass(notes, segments, from: start), at: clock.time + Self.lead)
        isPlaying = true
        send()
    }

    func stop() {
        pump?.cancel()
        pump = nil
        guard isPlaying else { return }
        isPlaying = false
        stoppedAt = currentTime(at: clock.time)
        let now = clock.time
        // An end already sent for later is overtaken by this one.
        for note in live { sinks.forEach { $0.noteOff(note.id, at: max(now, note.on)) } }
        live = []
    }

    func press(_ pitch: Int) {
        release(pitch)
        let id = NoteID.next()
        pressed[pitch] = id
        let now = clock.time
        sinks.forEach { $0.noteOn(id, note: pitch, sound: sound, at: now) }
    }

    func release(_ pitch: Int) {
        guard let id = pressed.removeValue(forKey: pitch) else { return }
        let now = clock.time
        sinks.forEach { $0.noteOff(id, at: now) }
    }

    func sound(_ notes: [PassNote]) {
        let now = clock.time
        for note in stepped {
            note.end.cancel()
            sinks.forEach { $0.noteOff(note.id, at: now) }
        }
        stepped = notes.map { note in
            let id = NoteID.next()
            sinks.forEach { $0.noteOn(id, note: note.pitch, sound: sound, at: now + note.start) }
            // Its end is sent when it is due, not ahead: a step stepped to
            // before then lets it go itself, and an end sent ahead could not
            // be called back from MIDI, where it would end the same key
            // struck again.
            let end = clock.after(seconds: note.end) { [weak self] in self?.endStepped(id) }
            return (id, end)
        }
    }

    private func endStepped(_ id: NoteID) {
        stepped.removeAll { $0.id == id }
        let now = clock.time
        sinks.forEach { $0.noteOff(id, at: now) }
    }

    var currentTime: Double {
        isPlaying ? currentTime(at: clock.time) : stoppedAt
    }

    private var stoppedAt = 0.0

    private func currentTime(at time: TimeInterval) -> Double {
        pass.scoreTime(at: time - passStart)
    }

    private func begin(_ pass: PlayPass, at time: TimeInterval) {
        self.pass = pass
        passStart = time
        struck = 0
    }

    /// Every note due before the lookahead sent, the notes ended let go,
    /// the next pass begun when this one is over (or play finished), and
    /// the clock asked to come back.
    private func send() {
        let now = clock.time
        let horizon = now + Self.lookahead
        while true {
            while struck < pass.notes.count, passStart + pass.notes[struck].start < horizon {
                let note = pass.notes[struck]
                let id = NoteID.next()
                let on = passStart + note.start
                sinks.forEach { $0.noteOn(id, note: note.pitch, sound: sound, at: on) }
                live.append((id, on, passStart + note.end, false))
                struck += 1
            }
            let end = passStart + pass.length
            guard struck == pass.notes.count, end < horizon, repeats, let first = segments.first,
                  pass.length > 0 else { break }
            begin(Playback.pass(notes, segments, from: PlayStart(segment: 0, time: first.start)), at: end)
        }
        for i in live.indices where !live[i].isEndSent && live[i].end < horizon {
            let note = live[i]
            sinks.forEach { $0.noteOff(note.id, at: note.end) }
            live[i].isEndSent = true
        }
        live.removeAll { $0.end <= now }
        if !repeats, struck == pass.notes.count, now >= passStart + pass.length {
            stoppedAt = pass.scoreTime(at: pass.length)
            isPlaying = false
            pump = nil
            onFinish?()
            return
        }
        pump = clock.after(seconds: Self.interval) { [weak self] in self?.send() }
    }
}
