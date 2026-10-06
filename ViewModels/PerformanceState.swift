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

/// Which input surface colors the chords. The two ship side by side for
/// on-device comparison; only one is on screen at a time.
enum ColorSurface: CaseIterable {
    case joystick
    case grid

    var displayName: String {
        switch self {
        case .joystick: return "Joystick"
        case .grid:     return "Grid"
        }
    }
}

@Observable
@MainActor
final class PerformanceState {
    var key = Key(root: .C, scale: .major)
    var octave = 4
    var joystickMode: JoystickMode = .default
    private(set) var synthPreset: SynthPreset = .initial
    /// Always within `MusicalTime.tempoRange`; change it with `setBPM`.
    private(set) var bpm: Double = 120

    var chordGridLayout: ChordGridLayout = .circle

    var isExternalSynth: Bool = false {
        didSet { engine?.isExternalSynth = isExternalSynth }
    }

    private(set) var mode: any PerformanceMode = PlayMode()
    /// The surface on screen. Switching resets both surfaces to neutral.
    var colorSurface: ColorSurface = .joystick {
        didSet {
            guard colorSurface != oldValue else { return }
            joystickDirection = .center
            gridPosition = nil
        }
    }
    private(set) var joystickDirection: JoystickDirection = .center
    /// Where a finger is on the chord grid; nil when none is.
    private(set) var gridPosition: GridPosition? = nil

    /// The live chord color for `degree`, from the surface on screen. A grid
    /// position means a different mode for each degree, so the color is
    /// resolved against the degree that plays. No finger on the grid plays
    /// the diatonic triad, as the joystick's centre does.
    func color(for degree: Degree) -> ChordColor {
        switch colorSurface {
        case .joystick:
            return .joystick(joystickMode, joystickDirection)
        case .grid:
            guard let gridPosition else { return .grid(.triad, nil) }
            return ChordGrid.color(at: gridPosition, key: key, degree: degree)
        }
    }
    private(set) var activeDegree: Degree? = nil
    /// Degrees whose buttons are down, oldest first; the last is the active press.
    private(set) var heldDegrees: [Degree] = []
    /// How far up each held key its finger is, 0 at the bottom to 1 at the
    /// top. The active key's is the one that plays the effects (`EffectsState.slide`).
    private var slides: [Degree: Float] = [:]
    private(set) var currentVoicing: Voicing? = nil
    /// The context `currentVoicing` was built from; a single note of the
    /// active chord (lead) is sent with it.
    private var currentContext: ChordContext? = nil
    private(set) var activeVoicingText = "—"

    let sequencerState: SequencerState
    let looperState     = LooperState()
    let micSampleState  = MicSampleState()
    let quickLoopState: QuickLoopState
    let effects: EffectsState

    var looper:      Looper? { engine?.looper }
    var quickLooper: Looper? { engine?.quickLooper }

    private let sink:   any ChordEventSink
    private let engine: AudioSink?
    private let clock:  any ClockTickable
    private let logger: (any Logger)?
    let micGate: any PermissionGate

    /// Designated initializer. Sinks, clock, logger, and micGate are always injected.
    /// Production: pass CompositeSink([audio, midi]) + the announcer + audio engine + FileLogger + MicrophonePermissionGate.
    /// Tests: pass RecordingSink + ManualClock + RecordingLogger + StubPermissionGate; omit engine.
    ///
    /// `sink` sounds the notes, so it sits behind the arpeggiator and hears
    /// one note at a time while that is on. `chordListener` is told which
    /// chord is held, whole, however its notes are being played.
    /// `effectsListener` follows the sound effects beside the audio (MIDI does).
    init(sink: any ChordEventSink,
         chordListener: (any ChordEventSink)? = nil,
         engine: AudioSink? = nil,
         effectsListener: (any EffectsControl)? = nil,
         clock: (any ClockTickable)? = nil,
         logger: (any Logger)? = nil,
         micGate: (any PermissionGate)? = nil) {
        let clock = clock ?? MasterClock()
        let arpeggiator = Arpeggiator(downstream: sink, clock: clock)
        self.sink         = chordListener.map { CompositeSink([arpeggiator, $0]) } ?? arpeggiator
        self.engine       = engine
        self.clock        = clock
        self.logger       = logger
        self.effects      = EffectsState(arpeggiator: arpeggiator, audio: engine,
                                         effectsListener: effectsListener, logger: logger)
        self.sequencerState = SequencerState(logger: logger)
        self.micGate      = micGate ?? NoopPermissionGate()
        self.quickLoopState = QuickLoopState(looper: engine?.quickLooper)
        self.quickLoopState.onWillStopRecording = { [weak self] in self?.endChord() }
        self.clock.bpm = bpm
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
        followSlide()
        clock.stop()
        mode = newMode
        if newMode.requiresClock { clock.start() }
    }

    func setBPM(_ value: Double) {
        bpm = value.clamped(to: MusicalTime.tempoRange)
        clock.bpm = bpm
    }

    /// Clock resolution (ticks per quarter-note beat), surfaced for tempo-aware
    /// modes that schedule musical durations. Sourced from the injected clock so
    /// a change to the clock's resolution propagates to every mode automatically.
    var ticksPerBeat: Int { clock.ticksPerBeat }

    /// Switches the synth sound. It is heard on the next chord played.
    func setSynthPreset(_ preset: SynthPreset) {
        synthPreset = preset
        engine?.setPreset(preset)
        logger?.log(.sound_changed(preset: preset.rawValue))
    }

    // MARK: – Chord button (delegates to mode)

    // The pointer contract lives here, so every mode gets it (see
    // PerformanceMode): presses stack, the most recent one is active, and
    // lifting it hands the chord back to the press beneath it.

    func press(degree: Degree) {
        heldDegrees.append(degree)
        followSlide()
        mode.onButtonDown(degree: degree, state: self)
    }

    func release(degree: Degree) {
        release([degree])
    }

    /// Keys lifted together (several fingers at once, or the chord surface
    /// going away). They leave as one step, so the chord is handed back only
    /// to a key that is still down afterwards.
    func release(_ degrees: [Degree]) {
        guard let active = heldDegrees.last else { return }
        var activeLifted = false
        for degree in degrees {
            guard let index = heldDegrees.lastIndex(of: degree) else { continue }
            if index == heldDegrees.count - 1 { activeLifted = true }
            heldDegrees.remove(at: index)
        }
        // The last key up ends its chord before its slide: an effect the
        // finger was holding on (a key zone) must not switch off under a
        // chord that is about to stop, which would sound it once more.
        if activeLifted, heldDegrees.isEmpty { mode.onButtonUp(degree: active, state: self) }
        followSlide()
        // Two presses of the same degree: it is still held, nothing changes.
        if activeLifted, let resumed = heldDegrees.last, resumed != active {
            mode.onButtonDown(degree: resumed, state: self)
        }
    }

    /// One key change: `old` went up and `new` came down (either may be nil: touch down,
    /// lift). The new degree is pressed before the old one is released, so a
    /// finger sliding across chords never leaves a gap: the new chord replaces
    /// the old, and the old release is superseded.
    func movePointer(from old: Degree?, to new: Degree?) {
        guard old != new else { return }
        if let new { press(degree: new) }
        if let old { release(degree: old) }
    }

    // MARK: – Key slide

    /// The finger on the key for `degree` is `height` of the way up it (0 at
    /// the bottom, 1 at the top). Report it before pressing the key, so the
    /// chord starts where the finger landed. Like the chord, the slide that
    /// is heard is the most recent press's, and lifting that press hands it
    /// back to the key held beneath.
    func slide(on degree: Degree, to height: Float) {
        slides[degree] = height
        if degree == heldDegrees.last { followSlide() }
    }

    /// Makes the active key's slide the one that is heard, and forgets the
    /// slides of keys no longer held.
    private func followSlide() {
        slides = slides.filter { heldDegrees.contains($0.key) }
        effects.slide = heldDegrees.last.flatMap { slides[$0] }
    }

    // MARK: – Color surfaces (delegate to mode)

    func joystickMoved(to direction: JoystickDirection) {
        guard direction != joystickDirection else { return }
        joystickDirection = direction
        mode.onColorChange(state: self)
    }

    /// A finger moved on the chord grid (nil: lifted).
    func gridMoved(to position: GridPosition?) {
        guard position != gridPosition else { return }
        gridPosition = position
        mode.onColorChange(state: self)
    }

    // MARK: – Mode-facing API

    func startChord(degree: Degree) {
        let spec = ChordSpec(degree: degree, color: color(for: degree))
        let voicing = select(spec)
        logger?.log(.chord_button_pressed(
            degree: degree.rawValue,
            key: "\(key.root.name) \(key.scale.displayName)",
            color: colorActionLabel(spec.color),
            resultingNotes: voicing.notes
        ))
        sound(voicing, .block, source: .button)
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

    func endChord() {
        let notes = currentVoicing?.notes ?? []
        activeDegree = nil
        activeVoicingText = "—"
        sink.stopChord()
        logger?.log(.chord_stopped(notes: notes, source: .button))
    }

    func strumChord(degree: Degree, interval: Double) {
        let voicing = select(ChordSpec(degree: degree, color: color(for: degree)))
        sound(voicing, .strum(interval: interval), source: .button)
    }

    func leadNote(degree: Degree) {
        select(ChordSpec(degree: degree, color: color(for: degree)))
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
                                       stepsPerBeat: MusicalTime.stepsPerBeat)
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
