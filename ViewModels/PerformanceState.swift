import Observation

enum ChordGridLayout: CaseIterable {
    case grid
    case circle
    case horizontalBar

    var displayName: String {
        switch self {
        case .grid:          return "Grid"
        case .circle:        return "Circle"
        case .horizontalBar: return "Horizontal bar"
        }
    }

    var detail: String {
        switch self {
        case .grid:          return "Default staggered Nashville grid."
        case .circle:        return "Root chord in the centre, six chords arranged clockwise around the edge."
        case .horizontalBar: return "In landscape, one tall row of all seven chords. Portrait uses the grid."
        }
    }
}

@Observable
@MainActor
final class PerformanceState {
    var key = Key(root: .C, scale: .major)
    var octave = 4
    var joystickMode: JoystickMode = .default
    var synthPreset: SynthPreset = .sinePad
    var bpm: Double = 120

    var chordGridLayout: ChordGridLayout = .circle

    /// Which press-and-hold key quick-selector is wired to the KEY button.
    /// Two candidates ship side by side for on-device comparison; see `KeyQuickSelect`.
    var keyQuickStyle: KeyQuickStyle = .wheel

    var isExternalSynth: Bool = false {
        didSet { engine?.isExternalSynth = isExternalSynth }
    }

    private(set) var mode: any PerformanceMode = PlayMode()
    private(set) var joystickDirection: JoystickDirection = .center
    private(set) var activeDegree: Degree? = nil
    private(set) var currentVoicing: Voicing? = nil
    private(set) var activeVoicingText = "—"

    let sequencerState  = SequencerState()
    let looperState     = LooperState()
    let micSampleState  = MicSampleState()
    let quickLoopState: QuickLoopState

    var looper:      Looper? { engine?.looper }
    var quickLooper: Looper? { engine?.quickLooper }

    private let sink:   any ChordEventSink
    private let engine: AudioSink?
    private let clock:  any ClockTickable
    private let logger: (any Logger)?
    let micGate: any PermissionGate

    /// Designated initializer. Sinks, clock, logger, and micGate are always injected.
    /// Production: pass CompositeSink([audio, midi]) + audio engine + FileLogger + MicrophonePermissionGate.
    /// Tests: pass RecordingSink + ManualClock + RecordingLogger + StubPermissionGate; omit engine.
    init(sink: any ChordEventSink,
         engine: AudioSink? = nil,
         clock: (any ClockTickable)? = nil,
         logger: (any Logger)? = nil,
         micGate: (any PermissionGate)? = nil) {
        self.sink         = sink
        self.engine       = engine
        self.clock        = clock ?? MasterClock()
        self.logger       = logger
        self.micGate      = micGate ?? NoopPermissionGate()
        self.quickLoopState = QuickLoopState(looper: engine?.quickLooper)
        self.quickLoopState.onWillStopRecording = { [weak self] in self?.endChord() }
        self.clock.onTick { [weak self] in
            guard let self else { return }
            self.mode.onClockTick(state: self)
        }
    }

    // MARK: – Mode / preset switching

    func setMode(_ newMode: any PerformanceMode) {
        logger?.log(.mode_changed(from: mode.name, to: newMode.name))
        mode.deactivate(state: self)
        clock.stop()
        mode = newMode
        if newMode.requiresClock {
            clock.bpm = bpm
            clock.start()
        }
    }

    func setBPM(_ value: Double) {
        bpm = value
        clock.bpm = value
    }

    /// Clock resolution (ticks per quarter-note beat), surfaced for tempo-aware
    /// modes that schedule musical durations. Sourced from the injected clock so
    /// a change to the clock's resolution propagates to every mode automatically.
    var ticksPerBeat: Int { clock.ticksPerBeat }

    func setSynthPreset(_ preset: SynthPreset) {
        synthPreset = preset
        engine?.setPreset(preset)
    }

    // MARK: – Chord button (delegates to mode)

    func press(degree: Degree) {
        mode.onButtonDown(degree: degree, state: self)
    }

    func release(degree: Degree) {
        mode.onButtonUp(degree: degree, state: self)
    }

    // MARK: – Joystick (delegates to mode)

    func joystickMoved(to direction: JoystickDirection) {
        guard direction != joystickDirection else { return }
        joystickDirection = direction
        mode.onJoystickChange(direction: direction, state: self)
    }

    // MARK: – Mode-facing API

    func startChord(degree: Degree) {
        activeDegree = degree
        let voicing = makeVoicing(for: degree)
        currentVoicing = voicing
        activeVoicingText = displayText(degree: degree)
        logger?.log(.chord_button_pressed(
            degree: degree.rawValue,
            key: "\(key.root.name) \(key.scale.displayName)",
            joystick: "\(joystickMode)/\(joystickDirection)",
            resultingNotes: voicing.notes
        ))
        sink.playChord(voicing)
        logger?.log(.chord_played(notes: voicing.notes, source: .button))
    }

    /// Sets up voicing state without triggering audio — for clock-driven modes.
    func armChord(degree: Degree) {
        activeDegree = degree
        let voicing = makeVoicing(for: degree)
        currentVoicing = voicing
        activeVoicingText = displayText(degree: degree)
    }

    /// Stop the sounding chord on *every* sink — audio note-off, MIDI note-off,
    /// and a ChordLink release all fire — while leaving the OLED display and the
    /// active-gesture state (`activeDegree`, `currentVoicing`) untouched, so a
    /// tempo-aware mode can retrigger. Contrast `endChord()`, which also clears
    /// the display and ends the gesture. (The old name "stopAudioOnly" hid that
    /// this reaches MIDI and ChordLink, not just audio.)
    func stopSounding() {
        sink.stopChord()
    }

    /// Plays a single MIDI note — for arpeggiator tick playback.
    func playNote(_ midiNote: Int) {
        sink.playChord(Voicing(notes: [midiNote]))
        logger?.log(.chord_played(notes: [midiNote], source: .arpeggio))
    }

    func endChord() {
        let notes = currentVoicing?.notes ?? []
        activeDegree = nil
        activeVoicingText = "—"
        sink.stopChord()
        logger?.log(.chord_stopped(notes: notes, source: .button))
    }

    func strumChord(degree: Degree) {
        let voicing = makeVoicing(for: degree)
        activeDegree = degree
        currentVoicing = voicing
        activeVoicingText = displayText(degree: degree)
        if let engine {
            engine.strumChord(voicing)
        } else {
            sink.playChord(voicing)
        }
        logger?.log(.chord_played(notes: voicing.notes, source: .button))
    }

    func leadNote(degree: Degree) {
        let intervals = key.scale.intervals
        let offset = intervals[degree.index % intervals.count]
        let midiNote = key.root.rawValue + (octave + 1) * 12 + offset
        let voicing = Voicing(notes: [midiNote])
        activeDegree = degree
        currentVoicing = voicing
        activeVoicingText = displayText(degree: degree)
        sink.playChord(voicing)
        logger?.log(.chord_played(notes: voicing.notes, source: .button))
    }

    // MARK: – Mic Sample mode actions (called from MicSampleView buttons)

    func startMicRecording() {
        switch micGate.state {
        case .undetermined: micSampleState.permissionFlow = .prePrompt
        case .denied:       micSampleState.permissionFlow = .settingsRedirect
        case .restricted:   micSampleState.permissionFlow = .restricted
        case .granted:
            guard let sampler = engine?.micSampler else { return }
            sampler.startRecording()
            micSampleState.isRecording = true
        }
    }

    func stopMicRecording() {
        guard let sampler = engine?.micSampler else { return }
        sampler.stopRecording()
        micSampleState.isRecording = false
        micSampleState.hasContent  = sampler.hasContent
    }

    func makeMicSampleMode() -> MicSampleMode {
        MicSampleMode(micSampleState,
                      sampler: engine?.micSampler,
                      gate:    micGate)
    }

    /// The sequencer pattern exactly as playback runs through it, in the
    /// current key, octave and tempo — ready to share as a MIDI file.
    var sequencerMidiExport: SequencerMidiExport {
        let pattern = SequencerPattern(steps: sequencerState.playedSteps,
                                       key: key,
                                       octave: octave,
                                       bpm: bpm,
                                       stepsPerBeat: ticksPerBeat)
        return SequencerMidiExport(pattern: pattern) { [weak self] noteCount, byteCount in
            self?.logger?.log(.sequencer_midi_exported(stepCount: pattern.steps.count,
                                                       noteCount: noteCount,
                                                       byteCount: byteCount))
        }
    }

    func playSequencerStep(degree: Degree, joystickMode: JoystickMode, joystickDirection: JoystickDirection) {
        activeDegree = degree
        let voicing = makeVoicing(for: degree, joystickMode: joystickMode, joystickDirection: joystickDirection)
        currentVoicing = voicing
        activeVoicingText = displayText(degree: degree, mode: joystickMode, direction: joystickDirection)
        sink.playChord(voicing)
        logger?.log(.chord_played(notes: voicing.notes, source: .sequencer))
    }

    // MARK: – Private

    private func makeVoicing(for degree: Degree,
                              joystickMode: JoystickMode? = nil,
                              joystickDirection: JoystickDirection? = nil) -> Voicing {
        performanceVoicing(
            key: key,
            octave: octave,
            degree: degree,
            joystickMode: joystickMode ?? self.joystickMode,
            joystickDirection: joystickDirection ?? self.joystickDirection,
            previousVoicing: currentVoicing
        )
    }

    /// The chord name shown on the OLED display. Derived entirely from the core
    /// (`chordLabel`), which reads the same base quality and JoystickMap entry
    /// that produce the notes — so the label can never disagree with what sounds.
    /// `mode`/`direction` default to the live joystick but are passed explicitly
    /// for sequencer steps, which carry their own per-step joystick selection.
    private func displayText(degree: Degree,
                             mode: JoystickMode? = nil,
                             direction: JoystickDirection? = nil) -> String {
        chordLabel(key: key,
                   degree: degree,
                   joystickMode: mode ?? joystickMode,
                   joystickDirection: direction ?? joystickDirection)
    }
}
