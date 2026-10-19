import Foundation
import Observation

/// What the pads need from whatever plays the chords.
@MainActor
protocol PadsHost: AnyObject {
    /// What a pad is given: the chord the keys played last, in the key,
    /// octave, sound and effects chosen now.
    var padSound: PadSound { get }
    /// Whether the pads hear the mic may have changed (`PadsState.hearsTheMic`).
    func padsChanged()
}

/// The pads: a grid of sounds (`PadGrid`), each a chord with a key, octave,
/// sound and effects of its own.
///
/// They are played two ways. A pad pressed sounds for as long as it is held,
/// and each has a voice of its own, so any number sound together. The
/// sequence (`isRunning`) plays the grid a pad at a time on the clock, row
/// by row from the first to the last and round again, through one more
/// voice, so the pads can be played over it. A pad with no sound is a rest.
/// The sequence goes on while another screen is shown.
///
/// While they are edited (`isEditing`), a press also chooses the pad the
/// editor changes, and a change is heard at once in a pad that is held.
@Observable
@MainActor
final class PadsState {

    private(set) var grid = PadGrid() {
        didSet {
            guard grid != oldValue else { return }
            save()
            if grid.rate != oldValue.rate, isRunning { arm() }
        }
    }

    /// Whether the pads are on screen (`PerformanceState.deskPane`). Off
    /// screen no pad is held.
    var isShown = false {
        didSet {
            guard isShown != oldValue else { return }
            if !isShown { letGo() }
            host?.padsChanged()
        }
    }

    /// Whether a press chooses the pad to edit as well as sounding it.
    var isEditing = false {
        didSet {
            guard isEditing != oldValue else { return }
            letGo()
            if isEditing, selected == nil { selected = grid.places.first }
        }
    }

    /// The pad the editor changes.
    private(set) var selected: PadPlace?

    /// The pad being edited, while there is one.
    var edited: PadPlace? { isShown && isEditing ? selected : nil }

    /// The pads that are down, oldest first. One held twice (a finger, and
    /// the editor trying it out) is here twice.
    private(set) var held: [PadPlace] = []

    /// Whether the grid is being played in sequence.
    var isRunning = false {
        didSet {
            guard isRunning != oldValue else { return }
            logger?.log(.pads_sequence_switched(isOn: isRunning))
            if isRunning { run() } else { halt() }
            host?.padsChanged()
        }
    }

    /// The pad the sequence is at.
    private(set) var step: PadPlace?

    /// Whether anything that can sound now needs the mic: a pad with the
    /// vocoder on, while the pads are on screen or playing in sequence.
    var hearsTheMic: Bool {
        (isShown || isRunning) && grid.places.contains { grid[$0]?.effects.vocoder.isOn == true }
    }

    @ObservationIgnored weak var host: (any PadsHost)?

    /// The voice of each pad that has been played.
    private var voices: [PadPlace: any TimelineVoice] = [:]
    private let makeVoice: (() -> any TimelineVoice)?
    private let sequenceVoice: (any TimelineVoice)?
    private let clock: any ClockTickable
    private let defaults: UserDefaults?
    private let logger: (any Logger)?

    /// The sequence's steps, and the end of the step that is sounding.
    private var steps: ClockCall?
    private var gate: ClockCall?
    /// The pad the editor is trying out.
    private var auditioned: PadPlace?

    private static let storageKey = "pads.grid.v1"

    /// `makeVoice` makes the voice of a pad, a new one each time, so pads
    /// sound together; `sequenceVoice` sounds the sequence. Without them
    /// the pads are silent. The grid is kept in `defaults`; with none it is
    /// not saved (tests).
    init(makeVoice: (() -> any TimelineVoice)? = nil,
         sequenceVoice: (any TimelineVoice)? = nil,
         clock: any ClockTickable,
         defaults: UserDefaults? = nil,
         logger: (any Logger)? = nil) {
        self.makeVoice = makeVoice
        self.sequenceVoice = sequenceVoice
        self.clock = clock
        self.defaults = defaults
        self.logger = logger
        if let saved = defaults?.data(forKey: Self.storageKey),
           let grid = try? JSONDecoder().decode(PadGrid.self, from: saved) {
            self.grid = grid
        }
    }

    // MARK: – Playing

    /// A pad came down: it sounds, beside whatever else is sounding. While
    /// the pads are edited it is also the one the editor changes.
    func press(_ place: PadPlace) {
        guard grid.contains(place) else { return }
        if isEditing { selected = place }
        held.append(place)
        guard !held.dropLast().contains(place), let sound = grid[place] else { return }
        start(sound, at: place)
    }

    /// Pads lifted. One still held another way carries on.
    func release(_ places: [PadPlace]) {
        for place in places {
            guard let index = held.lastIndex(of: place) else { continue }
            held.remove(at: index)
            if !held.contains(place) { voices[place]?.stop() }
        }
    }

    /// One change under a finger: `old` went up and `new` came down (either
    /// may be nil), the new pad first, so sliding across the pads leaves no gap.
    func movePointer(from old: PadPlace?, to new: PadPlace?) {
        guard old != new else { return }
        if let new { press(new) }
        if let old { release([old]) }
    }

    private func start(_ sound: PadSound, at place: PadPlace) {
        guard let voice = voices[place] ?? makeVoice?() else { return }
        voices[place] = voice
        voice.play(sound.played)
        logger?.log(.pad_played(row: place.row, column: place.column, notes: sound.played.event.voicing.notes))
    }

    /// Every pad that is down is let go.
    private func letGo() {
        auditioned = nil
        release(held)
    }

    // MARK: – The sequence

    /// Starts the sequence from the first pad, at the step set now.
    private func run() {
        halt()
        advance()
        arm()
    }

    /// Asks the clock for the steps to come, each one step after the last.
    /// A new step length is taken up from the pad the sequence is at.
    private func arm() {
        steps?.cancel()
        steps = clock.every(beats: grid.rate.beats) { [weak self] in self?.advance() }
    }

    private func halt() {
        steps?.cancel()
        steps = nil
        gate?.cancel()
        gate = nil
        step = nil
        sequenceVoice?.stop()
    }

    /// Moves the sequence to its next pad and sounds it for a share of the
    /// step, as a chord entered on a step of the sequencer is.
    private func advance() {
        gate?.cancel()
        gate = nil
        let place = grid.place(after: step)
        step = place
        guard let sound = grid[place] else {
            sequenceVoice?.stop()
            return
        }
        sequenceVoice?.play(sound.played)
        gate = clock.after(beats: grid.rate.beats * TimelineNote.enteredGate) { [weak self] in
            self?.sequenceVoice?.stop()
        }
    }

    // MARK: – Editing

    func select(_ place: PadPlace) {
        guard grid.contains(place) else { return }
        selected = place
    }

    /// Changes the sound of the pad chosen. One with no sound starts from
    /// what the keys play (`PadsHost.padSound`).
    func edit(_ change: (inout PadSound) -> Void) {
        guard let selected, var sound = grid[selected] ?? host?.padSound else { return }
        change(&sound)
        set(sound, at: selected)
    }

    /// Gives the pad chosen what the keys play, all of it.
    func takeFromKeys() {
        guard let selected, let sound = host?.padSound else { return }
        set(sound, at: selected)
    }

    /// Leaves the pad chosen with no sound.
    func clearSelected() {
        guard let selected else { return }
        set(nil, at: selected)
    }

    /// The editor sounds the pad chosen while a finger is on one of its
    /// controls, so a change is heard as it is made.
    func audition() {
        guard auditioned == nil, let selected else { return }
        auditioned = selected
        press(selected)
    }

    func endAudition() {
        guard let auditioned else { return }
        self.auditioned = nil
        release([auditioned])
    }

    /// A pad that is held takes the change up at once: its effects under
    /// the chord sounding, and anything else by sounding again.
    private func set(_ sound: PadSound?, at place: PadPlace) {
        let old = grid[place]
        guard grid.contains(place), sound != old else { return }
        grid[place] = sound
        logger?.log(.pad_assigned(row: place.row, column: place.column, chord: sound?.label))
        if held.contains(place) {
            if let sound, var same = old {
                same.effects = sound.effects
                if same == sound { voices[place]?.change(to: sound.played) } else { start(sound, at: place) }
            } else if let sound {
                start(sound, at: place)
            } else {
                voices[place]?.stop()
            }
        }
        host?.padsChanged()
    }

    // MARK: – The grid's size

    func setRows(_ rows: Int) { resize(rows: rows, columns: grid.columns) }
    func setColumns(_ columns: Int) { resize(rows: grid.rows, columns: columns) }

    func setRate(_ rate: PadRate) { grid.rate = rate }

    /// Pads the grid no longer has are let go, and the editor is left at
    /// one it does have.
    private func resize(rows: Int, columns: Int) {
        var resized = grid
        resized.resize(rows: rows, columns: columns)
        guard resized != grid else { return }
        release(held.filter { !resized.contains($0) })
        grid = resized
        if let selected, !grid.contains(selected) { self.selected = grid.places.first }
        logger?.log(.pads_resized(rows: grid.rows, columns: grid.columns))
        host?.padsChanged()
    }

    private func save() {
        guard let defaults, let data = try? JSONEncoder().encode(grid) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
