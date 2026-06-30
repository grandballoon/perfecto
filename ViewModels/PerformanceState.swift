import Observation

@Observable
@MainActor
final class PerformanceState {
    var key = Key(root: .C, scale: .major)
    var octave = 4
    var joystickMode: JoystickMode = .default
    var synthPreset: SynthPreset = .sinePad
    var bpm: Double = 120

    /// When enabled, landscape shows the seven chord buttons in one tall,
    /// uniform-width horizontal row on the right instead of the staggered grid.
    var horizontalLandscapeChords = false

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
        activeVoicingText = displayText(degree: degree, voicing: voicing)
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
        activeVoicingText = displayText(degree: degree, voicing: voicing)
    }

    /// Stop audio without touching the OLED display — for rhythmic retriggering.
    func stopAudioOnly() {
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
        activeVoicingText = displayText(degree: degree, voicing: voicing)
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
        activeVoicingText = displayText(degree: degree, voicing: voicing)
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

    func playSequencerStep(degree: Degree, joystickMode: JoystickMode, joystickDirection: JoystickDirection) {
        activeDegree = degree
        let voicing = makeVoicing(for: degree, joystickMode: joystickMode, joystickDirection: joystickDirection)
        currentVoicing = voicing
        activeVoicingText = displayText(degree: degree, voicing: voicing)
        sink.playChord(voicing)
        logger?.log(.chord_played(notes: voicing.notes, source: .sequencer))
    }

    // MARK: – Private

    private func makeVoicing(for degree: Degree,
                              joystickMode: JoystickMode? = nil,
                              joystickDirection: JoystickDirection? = nil) -> Voicing {
        computeVoicing(
            key: key,
            degree: degree,
            joystickMode: joystickMode ?? self.joystickMode,
            joystickDirection: joystickDirection ?? self.joystickDirection,
            inversion: .root,
            octave: octave,
            voiceLeading: false,
            previousVoicing: currentVoicing
        )
    }

    private func displayText(degree: Degree, voicing: Voicing) -> String {
        let intervals = key.scale.intervals
        let degreeOffset = intervals[degree.index % intervals.count]
        let root = PitchClass(rawValue: (key.root.rawValue + degreeOffset) % 12)!
        let quality = qualityLabel(for: degree, direction: joystickDirection, mode: joystickMode)
        return "\(root.name) \(quality)"
    }

    private func qualityLabel(for degree: Degree,
                               direction: JoystickDirection,
                               mode: JoystickMode) -> String {
        guard direction != .center else {
            switch degree {
            case .I, .IV, .V:    return "maj"
            case .ii, .iii, .vi: return "min"
            case .viiDim:        return "dim"
            }
        }
        switch mode {
        case .default:
            switch direction {
            case .up:        return "flip 3rd"
            case .upRight:   return "dom7"
            case .right:     return "maj7"
            case .downRight: return "add9"
            case .down:      return "sus4"
            case .downLeft:  return "6/sus2"
            case .left:      return "dim"
            case .upLeft:    return "aug"
            case .center:    return "maj"
            }
        case .extended:
            switch direction {
            case .up:        return "flip 3rd"
            case .upRight:   return "dom9"
            case .right:     return "add11"
            case .downRight: return "min11"
            case .down:      return "7♯9"
            case .downLeft:  return "add9"
            case .left:      return "sus4 7"
            case .upLeft:    return "½dim7"
            case .center:    return "maj"
            }
        case .chromatic:
            switch direction {
            case .up:        return "minmaj7"
            case .upRight:   return "dom13"
            case .right:     return "6/9"
            case .downRight: return "7alt"
            case .down:      return "maj13"
            case .downLeft:  return "7♭9"
            case .left:      return "½dim7"
            case .upLeft:    return "maj7♯11"
            case .center:    return "maj"
            }
        }
    }
}
