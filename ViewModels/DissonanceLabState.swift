import Observation

/// The Dissonance Lab: two notes played together through a sound made of
/// partials, with what makes them smooth or rough exaggerated, picked out
/// and faded back by stages, so a beginner hears it.
///
/// It sounds the two most recent notes held, from a MIDI keyboard or from
/// its own pads; a third note takes the place of the oldest. One note alone
/// is played plainly, with nothing to analyse. What the notes become is
/// worked out by `LabSounding` from them and the settings alone, and
/// `DissonanceSynth` makes it heard: every change of a setting is glided to,
/// so the difference it makes is heard as it is made.
///
/// Like the Trautonium it is a line of its own and no mode knows of it, and
/// it is heard and not sent: its partials and its tuning have no place in
/// the MIDI the app sends. While it is on screen it is what a MIDI keyboard
/// plays (`PerformanceState`'s `ControllerPlayer`).
@Observable
@MainActor
final class DissonanceLabState {

    /// A note held, and how hard it was struck (MIDI's 1...127).
    struct Held: Equatable {
        let note: Int
        let velocity: Int
    }

    /// Whether the lab is on screen. Off it, nothing of its sounds.
    var isShown = false {
        didSet { if !isShown { releaseAll() } }
    }

    /// Every control. A change of any is heard at once.
    var settings = LabLevel.one.settings {
        didSet { if settings != oldValue { sound() } }
    }

    /// The level last chosen, which set the controls; they may have been
    /// changed since (`isAdjusted`).
    private(set) var level: LabLevel? = .one

    /// Whether the controls are other than the level set them.
    var isAdjusted: Bool { level.map { settings != $0.settings } ?? true }

    /// Whether the A/B button is held: equal temperament and no
    /// enhancement, the partials and the voicing as set.
    var isPlain = false {
        didSet {
            guard isPlain != oldValue else { return }
            logger?.log(.lab_bypassed(plain: isPlain))
            sound()
        }
    }

    /// The note the pads' intervals are above (`setPadRoot`).
    private(set) var padRoot = 57
    static let padRoots = 24...96

    /// The notes held, the oldest first: two at most.
    private(set) var held: [Held] = []
    /// The pad held, if one is.
    private(set) var heldPad: Interval?

    /// What the two notes held are sounding, worked out: nil while fewer
    /// than two are.
    private(set) var sounding: LabSounding?

    @ObservationIgnored private let synth: DissonanceSynth
    @ObservationIgnored private let logger: (any Logger)?

    /// A pad is struck this hard.
    static let padVelocity = 100

    init(synth: DissonanceSynth, logger: (any Logger)? = nil) {
        self.synth = synth
        self.logger = logger
    }

    // MARK: – Levels

    /// Sets every control as `level` has them.
    func choose(_ level: LabLevel) {
        self.level = level
        settings = level.settings
        logger?.log(.lab_level_chosen(level: level.rawValue))
    }

    // MARK: – Playing

    /// `note` is struck, `velocity` (1...127) hard. With two held already
    /// it takes the oldest one's place. A pad held is a pad no longer: its
    /// notes are notes like these now, let go by their own keys.
    func press(_ note: Int, velocity: Int) {
        guard isShown, Voicing.midiRange.contains(note) else { return }
        heldPad = nil
        held.removeAll { $0.note == note }
        held.append(Held(note: note, velocity: velocity.clamped(to: 1...127)))
        if held.count > 2 { held.removeFirst(held.count - 2) }
        sound()
        if let sounding {
            logger?.log(.lab_interval_played(low: sounding.keyed.low, high: sounding.keyed.high,
                                             semitones: sounding.interval.semitones, just: sounding.isJust))
        }
    }

    func release(_ note: Int) {
        guard held.contains(where: { $0.note == note }) else { return }
        held.removeAll { $0.note == note }
        sound()
    }

    /// The pad of `interval` is pressed: the pads' root and the note that
    /// interval above it, in place of whatever was held.
    func pressPad(_ interval: Interval) {
        guard isShown else { return }
        held = []
        heldPad = interval
        let top = padRoot + interval.semitones
        guard Voicing.midiRange.contains(top) else { return sound() }
        held = [Held(note: padRoot, velocity: Self.padVelocity), Held(note: top, velocity: Self.padVelocity)]
        sound()
        if let sounding {
            logger?.log(.lab_interval_played(low: sounding.keyed.low, high: sounding.keyed.high,
                                             semitones: interval.semitones, just: sounding.isJust))
        }
    }

    /// The pads' intervals are above `note` from now on, brought into
    /// `padRoots`; a pad held goes there at once.
    func setPadRoot(_ note: Int) {
        let note = note.clamped(to: Self.padRoots)
        guard note != padRoot else { return }
        padRoot = note
        if let interval = heldPad { pressPad(interval) }
    }

    /// The pad held is let go.
    func releasePad() {
        guard heldPad != nil else { return }
        heldPad = nil
        held = []
        sound()
    }

    /// Everything held is let go.
    func releaseAll() {
        held = []
        heldPad = nil
        sound()
    }

    /// Plays `interval` above `root` with the controls as `level` sets
    /// them, until `stop`: for a quiz, or anything else that drives the lab.
    func play(_ interval: Interval, above root: Int, level: LabLevel) {
        choose(level)
        setPadRoot(root)
        pressPad(interval)
    }

    func stop() { releaseAll() }

    // MARK: – Sound

    /// Works out what the notes held sound, and has it sounded.
    private func sound() {
        switch held.count {
        case 2:
            let sounding = LabSounding(held[0].note, held[1].note, settings: settings, plain: isPlain)
            self.sounding = sounding
            synth.sound(sounding.lines(velocity: velocity))
        case 1:
            sounding = nil
            synth.sound(LabSounding.single(held[0].note, settings: settings, velocity: velocity))
        default:
            sounding = nil
            synth.silence()
        }
    }

    /// How hard the notes held were struck, as one: their gain, and nothing
    /// of the analysis.
    private var velocity: Float {
        guard !held.isEmpty else { return 0 }
        return Float(held.map(\.velocity).reduce(0, +)) / Float(held.count) / 127
    }
}

extension DissonanceLabState: ControllerPlayer {
    /// The controller's knobs and buttons play nothing here.
    func control(_ id: ControllerControl.ID, movedTo value: Double) {}

    func keyDown(_ note: Int, velocity: Int) { press(note, velocity: velocity) }

    func keyUp(_ note: Int) { release(note) }
}
