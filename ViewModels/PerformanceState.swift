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
    /// The live chord color, from whichever input surface is active.
    var color: ChordColor { .joystick(joystickMode, joystickDirection) }
    private(set) var activeDegree: Degree? = nil
    /// Degrees whose buttons are down, oldest first; the last is the active press.
    private(set) var heldDegrees: [Degree] = []
    private(set) var currentVoicing: Voicing? = nil
    /// The context `currentVoicing` was built from; single notes of the active
    /// chord (lead, arpeggio) are sent with it.
    private var currentContext: ChordContext? = nil
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

    /// Switches to the mode of `kind`. Choosing the mode that is already
    /// active does nothing, so a toggle can be tapped again without resetting
    /// the mode (for example, stopping the sequencer).
    func selectMode(_ kind: ModeKind) {
        guard kind != mode.kind else { return }
        setMode(makeMode(kind))
    }

    /// Replaces the active mode unconditionally. Views use `selectMode`; this
    /// is for callers that supply a configured instance (tests).
    func setMode(_ newMode: any PerformanceMode) {
        logger?.log(.mode_changed(from: mode.name, to: newMode.name))
        heldDegrees = []
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

    // The pointer contract lives here, so every mode gets it (see
    // PerformanceMode): presses stack, and a mode hears a release only for the
    // degree pressed most recently.

    func press(degree: Degree) {
        heldDegrees.append(degree)
        mode.onButtonDown(degree: degree, state: self)
    }

    func release(degree: Degree) {
        guard let index = heldDegrees.lastIndex(of: degree) else { return }
        let wasActive = index == heldDegrees.count - 1
        heldDegrees.remove(at: index)
        if wasActive { mode.onButtonUp(degree: degree, state: self) }
    }

    /// One pointer moved from `old` to `new` (either may be nil: touch down,
    /// lift). The new degree is pressed before the old one is released, so a
    /// finger sliding across chords never leaves a gap: the new chord replaces
    /// the old, and the old release is superseded.
    func movePointer(from old: Degree?, to new: Degree?) {
        guard old != new else { return }
        if let new { press(degree: new) }
        if let old { release(degree: old) }
    }

    // MARK: – Joystick (delegates to mode)

    func joystickMoved(to direction: JoystickDirection) {
        guard direction != joystickDirection else { return }
        joystickDirection = direction
        mode.onJoystickChange(direction: direction, state: self)
    }

    // MARK: – Mode-facing API

    func startChord(degree: Degree) {
        let voicing = select(ChordSpec(degree: degree, color: color))
        logger?.log(.chord_button_pressed(
            degree: degree.rawValue,
            key: "\(key.root.name) \(key.scale.displayName)",
            joystick: "\(joystickMode)/\(joystickDirection)",
            resultingNotes: voicing.notes
        ))
        sound(voicing, .block, source: .button)
    }

    /// Sets up voicing state without triggering audio — for clock-driven modes.
    func armChord(degree: Degree) {
        select(ChordSpec(degree: degree, color: color))
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

    /// Plays a single note of the armed chord — for arpeggiator tick playback.
    func playNote(_ midiNote: Int) {
        sound(Voicing(notes: [midiNote]), .block, source: .arpeggio)
    }

    func endChord() {
        let notes = currentVoicing?.notes ?? []
        activeDegree = nil
        activeVoicingText = "—"
        sink.stopChord()
        logger?.log(.chord_stopped(notes: notes, source: .button))
    }

    func strumChord(degree: Degree, interval: Double) {
        let voicing = select(ChordSpec(degree: degree, color: color))
        sound(voicing, .strum(interval: interval), source: .button)
    }

    func leadNote(degree: Degree) {
        select(ChordSpec(degree: degree, color: color))
        let midiNote = key.root.rawValue + (octave + 1) * 12 + key.scale.offset(of: degree)
        let voicing = Voicing(notes: [midiNote])
        currentVoicing = voicing
        sound(voicing, .block, source: .button)
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

    private func makeMode(_ kind: ModeKind) -> any PerformanceMode {
        switch kind {
        case .play:      return PlayMode()
        case .strum:     return StrumMode()
        case .lead:      return LeadMode()
        case .drone:     return DroneMode()
        case .arpeggio:  return ArpeggioMode()
        case .repeat:    return RepeatMode()
        case .sequencer: return SequencerMode(sequencerState)
        case .looper:    return LooperMode(looperState)
        case .micSample: return MicSampleMode(micSampleState, sampler: engine?.micSampler, gate: micGate)
        }
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

    /// Plays a sequencer step, which carries its own chord color rather than
    /// the live one.
    func playSequencerStep(_ spec: ChordSpec) {
        sound(select(spec), .block, source: .sequencer)
    }

    // MARK: – Private

    /// Makes `spec` the active chord: voices it and updates the display.
    /// The OLED text is `chordLabel` of the same spec, which reads the shape
    /// that produces these notes, so the label can never disagree with what sounds.
    @discardableResult
    private func select(_ spec: ChordSpec) -> Voicing {
        let context = performanceContext(key: key, octave: octave, spec: spec)
        let voicing = context.voicing(after: currentVoicing)
        activeDegree = spec.degree
        currentContext = context
        currentVoicing = voicing
        activeVoicingText = chordLabel(key: key, spec: spec)
        return voicing
    }

    /// Sends `voicing` to every sink as part of the active chord.
    private func sound(_ voicing: Voicing, _ articulation: Articulation, source: ChordSource) {
        guard let currentContext else { return }
        sink.playChord(ChordEvent(voicing: voicing, articulation: articulation, context: currentContext))
        logger?.log(.chord_played(notes: voicing.notes, source: source))
    }
}
