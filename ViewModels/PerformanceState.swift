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

/// How the seven chord keys are arranged on screen.
enum ChordKeyArrangement: CaseIterable {
    /// The staggered Nashville grid, four keys over three.
    case grid
    /// The root in the centre, the other six around it.
    case circle
    /// All seven in one row.
    case row
}

extension ChordGridLayout {
    /// The arrangement this layout gives a screen held upright or on its
    /// side. Every screen that shows the chord keys asks here, so they all
    /// show the layout chosen.
    func arrangement(isLandscape: Bool) -> ChordKeyArrangement {
        switch self {
        case .grid:          return .grid
        case .circle:        return .circle
        case .horizontalBar: return isLandscape ? .row : .grid
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

extension ColorSurface {
    /// The shape the surface takes on the play screen.
    var shape: SurfaceShape {
        switch self {
        case .joystick: return .bar
        case .grid:     return .grid
        }
    }
}

/// What the play screen's input surface, the one beside the chord keys, is
/// for. The effect slider takes the chord colors' place for now, so only
/// one of them can be played at a time.
enum PlaySurface: CaseIterable {
    /// Colors the chords (`ColorSurface`).
    case color
    /// Plays the effects that are on (`EffectsState.slider`).
    case effects

    var displayName: String {
        switch self {
        case .color:   return "Chord color"
        case .effects: return "Effect slider"
        }
    }
}

/// The two shapes the play screen's input surface comes in: a strip, or a
/// taller pad. They are the chord colors' shapes (the joystick bar and the
/// chord grid), which the effect slider borrows.
enum SurfaceShape: CaseIterable {
    case bar
    case grid

    var displayName: String {
        switch self {
        case .bar:  return "Bar"
        case .grid: return "Grid"
        }
    }
}

@Observable
@MainActor
final class PerformanceState {
    var key = Key(root: .C, scale: .major) {
        didSet { timelinePlayer?.live = liveSettings }
    }
    var octave = 4 {
        didSet { timelinePlayer?.live = liveSettings }
    }
    var joystickMode: JoystickMode = .default
    private(set) var synthPreset: SynthPreset = .initial
    /// Always within `MusicalTime.tempoRange`; change it with `setBPM`.
    private(set) var bpm: Double = 120

    var chordGridLayout: ChordGridLayout = .circle

    var isExternalSynth: Bool = false {
        didSet { output?.isExternalSynth = isExternalSynth }
    }

    private(set) var mode: any PerformanceMode = PlayMode()
    /// What the play screen's input surface is for. Switching leaves the
    /// chord colors neutral, since a finger on them may have gone with them.
    var playSurface: PlaySurface = .color {
        didSet {
            guard playSurface != oldValue else { return }
            clearColor()
        }
    }
    /// The shape of the effect slider while it is the play surface.
    var effectSliderShape: SurfaceShape = .bar
    /// The shape of whatever the play surface is showing. The solo strip
    /// in the colors' place is a bar.
    var surfaceShape: SurfaceShape {
        if solo.takesColorsPlace { return .bar }
        switch playSurface {
        case .color:   return colorSurface.shape
        case .effects: return effectSliderShape
        }
    }
    /// The chord-color surface on screen. Switching resets both surfaces to neutral.
    var colorSurface: ColorSurface = .joystick {
        didSet {
            guard colorSurface != oldValue else { return }
            clearColor()
        }
    }

    /// Leaves both color surfaces neutral.
    private func clearColor() {
        joystickDirection = .center
        gridPosition = nil
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
    let quickLoopState: QuickLoopState
    let effects: EffectsState
    /// The solo strip: notes that fit the chord, played over it.
    let solo: SoloState
    /// The computer keyboard, as a way to play the keys, the joystick and
    /// the solo strip.
    let keyboard: KeyboardState
    let micSample: MicSampleState
    /// Whether the app may use the mic, for the sample and the vocoder.
    let micAccess: MicAccess

    private let sink:   any ChordEventSink
    /// Hears the chord that is held, whole (ChordLink).
    private let chordListener: (any ChordEventSink)?
    /// Makes the sink a layer of the timeline sounds its notes through.
    private let layerSink: () -> any ChordEventSink
    /// The sequencer whose timeline is playing.
    private var playingSequencer: SequencerState?
    /// Plays the sequencer's timeline against the clock, under whatever mode is on.
    private var timelinePlayer: TimelinePlayer?
    /// How long after the clock's time the layers' sinks sound their notes.
    let layerLead: Double
    /// The sound of the notes the keys play.
    private let liveSound: (any SoundControl)?
    private let output: AudioOutput?
    private let clock:  any ClockTickable
    private let logger: (any Logger)?

    /// Designated initializer. Sinks, clock and logger are always injected.
    /// Production: pass a NotePlayer on the audio and MIDI sinks, the same
    /// player as `liveSound`, the same clock, the announcer, the audio
    /// output and a FileLogger.
    /// Tests: pass RecordingSink + ManualClock + RecordingLogger; omit the output.
    ///
    /// `sink` sounds the notes, so it sits behind the arpeggiator and hears
    /// one note at a time while that is on. `chordListener` is told which
    /// chord is held, whole, however its notes are being played.
    /// `liveSound` is given the preset and the sound effects as they are
    /// played, for the notes the keys start; `effectsListener` follows the
    /// effects beside it (MIDI does).
    /// `layerSink` makes a sink for each layer of the timeline, so layers
    /// sound together: production passes a new `NotePlayer` on the same note
    /// sinks each time, and a sink that is a `SoundControl` is given each of
    /// its chords' own sound. Without one, layers share `sink`.
    /// `layerLead` is the lead those sinks were made with (see
    /// `NotePlayer`), so a loop recorded over them lands where it was heard.
    /// `soloSink` sounds the solo strip's notes beside the keys' chord:
    /// production passes a `NotePlayer` of its own on the same note sinks.
    /// Without one the strip is silent.
    /// `micGate` says whether the mic sample may be recorded.
    /// `sequencer` is the app's sequencer and its saved timeline; tests pass
    /// one with a store of its own.
    /// `keyboard` is the computer keyboard and its saved map, likewise.
    init(sink: any ChordEventSink,
         chordListener: (any ChordEventSink)? = nil,
         layerSink: (() -> any ChordEventSink)? = nil,
         layerLead: Double = 0,
         soloSink: (any ChordEventSink)? = nil,
         sequencer: SequencerState? = nil,
         keyboard: KeyboardState? = nil,
         liveSound: (any SoundControl & EffectsControl)? = nil,
         output: AudioOutput? = nil,
         micGate: any PermissionGate = NoopPermissionGate(),
         effectsListener: (any EffectsControl)? = nil,
         clock: (any ClockTickable)? = nil,
         logger: (any Logger)? = nil) {
        let clock = clock ?? MasterClock()
        let arpeggiator = Arpeggiator(downstream: sink, clock: clock)
        self.sink         = chordListener.map { CompositeSink([arpeggiator, $0]) } ?? arpeggiator
        self.chordListener = chordListener
        self.layerSink    = layerSink ?? { sink }
        self.layerLead    = layerLead
        self.liveSound    = liveSound
        self.output       = output
        self.clock        = clock
        self.logger       = logger
        self.effects      = EffectsState(arpeggiator: arpeggiator, audio: liveSound,
                                         effectsListener: effectsListener, logger: logger)
        self.solo         = SoloState(sink: soloSink, logger: logger)
        self.keyboard     = keyboard ?? KeyboardState(logger: logger)
        self.sequencerState = sequencer ?? SequencerState(logger: logger)
        self.quickLoopState = QuickLoopState(logger: logger)
        self.micAccess = MicAccess(gate: micGate)
        self.micSample = MicSampleState(recorder: output?.sampleRecorder, access: micAccess)
        self.clock.bpm = bpm
        self.timelinePlayer = TimelinePlayer(live: liveSettings, clock: clock) { [weak self] layer in
            let sink = self?.layerSink() ?? CompositeSink([])
            return LayerVoice(sink: sink, sound: sink as? any SoundControl, clock: clock) { chord in
                self?.layerSounded(layer, chord)
            }
        }
        self.effects.onSetChange = { [weak self] in
            guard let self else { return }
            timelinePlayer?.live = liveSettings
            hearTheMicIfWanted()
        }
        self.effects.onPlayedChange = { [weak self] in self?.quickLoopState.effectsChanged() }
        self.quickLoopState.host = self
        self.solo.host = self
        self.keyboard.host = self
        // The strip may have taken the colors' place, and a finger on them
        // gone with them.
        self.solo.onArrange = { [weak self] in self?.clearColor() }
        // A sample just recorded is what the keys play next.
        self.micSample.onRecorded = { [weak self] in self?.setSynthPreset(.micSample) }
        attach(sequencerState)
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
        newMode.activate(state: self)
    }

    func setBPM(_ value: Double) {
        bpm = value.clamped(to: MusicalTime.tempoRange)
        clock.bpm = bpm
    }

    /// Clock resolution (ticks per quarter-note beat), surfaced for tempo-aware
    /// modes that schedule musical durations. Sourced from the injected clock so
    /// a change to the clock's resolution propagates to every mode automatically.
    var ticksPerBeat: Int { clock.ticksPerBeat }

    /// Calls `handler` once, `beats` beats from now on the clock, unless the
    /// returned call is cancelled first. For modes that time what they play.
    func after(beats: Double, _ handler: @escaping @MainActor () -> Void) -> ClockCall {
        clock.after(beats: beats, handler)
    }

    /// Calls `handler` once, `seconds` from now on the clock.
    func after(seconds: Double, _ handler: @escaping @MainActor () -> Void) -> ClockCall {
        clock.after(seconds: seconds, handler)
    }

    /// Opens the mic to the vocoder while an effect set wants it, asking
    /// for the mic first if need be; a refusal switches the vocoder back
    /// off, since it would have nothing to hear.
    private func hearTheMicIfWanted() {
        guard let output else { return }
        guard effects.hearsTheMic else {
            output.isVocoding = false
            return
        }
        guard !output.isVocoding else { return }
        micAccess.ask(then: { [weak self] in
            guard let self, effects.hearsTheMic else { return }
            output.isVocoding = true
        }, refused: { [weak self] in
            self?.effects.vocoder.isOn = false
        })
    }

    /// Switches the synth sound. It is heard on the next chord played.
    func setSynthPreset(_ preset: SynthPreset) {
        synthPreset = preset
        liveSound?.sound.preset = preset
        timelinePlayer?.live = liveSettings
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
        quickLoopState.chordEnded()
    }

    func endChord() {
        let notes = currentVoicing?.notes ?? []
        activeDegree = nil
        activeVoicingText = "—"
        sink.stopChord()
        quickLoopState.chordEnded()
        logger?.log(.chord_stopped(notes: notes, source: .button))
    }

    func strumChord(degree: Degree, interval: Double) {
        let voicing = select(ChordSpec(degree: degree, color: color(for: degree)))
        sound(voicing, .strum(interval: interval), source: .button)
    }

    func leadNote(degree: Degree) {
        select(ChordSpec(degree: degree, color: color(for: degree)))
        let voicing = Voicing(notes: [leadPitch(key: key, octave: octave, degree: degree)])
        currentVoicing = voicing
        sound(voicing, .block, pitch: .lead, source: .button)
    }

    private func makeMode(_ kind: ModeKind) -> any PerformanceMode {
        switch kind {
        case .play:      return PlayMode()
        case .strum:     return StrumMode()
        case .lead:      return LeadMode()
        case .drone:     return DroneMode()
        case .repeat:    return RepeatMode()
        case .sequencer: return SequencerMode(sequencerState)
        }
    }

    /// The sequencer pattern exactly as playback runs through it, in the
    /// current key, octave and tempo — ready to share as a MIDI file.
    var sequencerMidiExport: SequencerMidiExport {
        let pattern = SequencerPattern(timeline: sequencerState.timeline, live: liveSettings, bpm: bpm)
        return SequencerMidiExport(pattern: pattern) { [weak self] noteCount, byteCount in
            self?.logger?.log(.sequencer_midi_exported(stepCount: pattern.stepCount,
                                                       noteCount: noteCount,
                                                       byteCount: byteCount))
        }
    }

    /// Everything the timeline plays, the loops and the sequence together,
    /// as it sounds in the current key, sound and tempo: ready to share as
    /// an audio file.
    var timelineAudioExport: TimelineAudioExport {
        let timeline = sequencerState.timeline
        return TimelineAudioExport(timeline: timeline, live: liveSettings, bpm: bpm,
                                   sample: output?.sampleRecorder.recording) { [weak self] seconds in
            self?.logger?.log(.timeline_audio_exported(seconds: seconds, layerCount: timeline.layers.count))
        }
    }

    // MARK: – The timeline

    /// What a timeline's notes follow where they have no settings of their own.
    private var liveSettings: LiveSettings {
        LiveSettings(key: key, octave: octave, preset: synthPreset, effects: effects.asSet)
    }

    /// Makes `sequencer`'s timeline the one that plays, in place of
    /// whichever was. The app has one sequencer and it is attached from the
    /// start; this is for a caller that brings its own (tests).
    func attach(_ sequencer: SequencerState) {
        guard let timelinePlayer, playingSequencer !== sequencer else { return }
        playingSequencer?.detach(timelinePlayer)
        playingSequencer = sequencer
        sequencer.attach(timelinePlayer)
    }

    /// A layer of the timeline started `chord`, or fell silent (nil). Its
    /// notes are already sounding through the layer's own sink. The layer
    /// on screen in the sequencer is also shown and announced as the chord
    /// being played, while no key is held to say otherwise.
    private func layerSounded(_ layer: Layer.ID, _ chord: TimedChord?) {
        guard layer == playingSequencer?.layerID, heldDegrees.isEmpty else { return }
        guard let chord else {
            chordListener?.stopChord()
            return
        }
        let context = chord.event.context
        activeDegree = context.spec.degree
        currentContext = context
        currentVoicing = chord.event.voicing
        activeVoicingText = chordLabel(key: context.key, spec: context.spec)
        chordListener?.playChord(chord.event)
        logger?.log(.chord_played(notes: chord.event.voicing.notes, source: .sequencer))
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

    /// Sends `voicing` to every sink as part of the active chord. `pitch`
    /// says what of the chord it is, for a loop being recorded.
    private func sound(_ voicing: Voicing, _ articulation: Articulation, pitch: NotePitch = .chord,
                       source: ChordSource) {
        guard let currentContext else { return }
        let event = ChordEvent(voicing: voicing, articulation: articulation, context: currentContext)
        sink.playChord(event)
        quickLoopState.chordStarted(event, pitch: pitch)
        logger?.log(.chord_played(notes: voicing.notes, source: source))
    }
}

extension PerformanceState: SoloHost {
    /// The chord that is sounding, as it sounds. With none, the last one
    /// played, read in the key and octave set now (the tonic's triad before
    /// any has been), so the strip can still be played once the keys are let go.
    var soloChord: ChordContext {
        if activeDegree != nil, let currentContext { return currentContext }
        let spec = currentContext?.spec ?? ChordSpec(degree: .I, color: .base)
        return performanceContext(key: key, octave: octave, spec: spec)
    }

    /// The keys' preset, with the effects as they are set: a slide on a
    /// chord key plays that chord, not the run over it.
    var soloSound: NoteSound {
        NoteSound(preset: synthPreset, effects: effects.asSet)
    }
}

extension PerformanceState: LoopHost {
    var loopSequencer: SequencerState? { playingSequencer }

    var clockBeats: Double { clock.beats }

    var playedNow: NotePlaying {
        NotePlaying(key: key, octave: octave, preset: synthPreset, effects: effects.asPlayed)
    }
}

extension PerformanceState: KeyboardHost {}
