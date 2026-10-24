import Foundation
import Observation

enum ChordGridLayout: CaseIterable {
    case grid
    case circle
    case horizontalBar
    case octave

    var displayName: String {
        switch self {
        case .grid:          return "Grid"
        case .circle:        return "Circle"
        case .horizontalBar: return "Horizontal bar"
        case .octave:        return "Piano octave"
        }
    }

    var detail: String {
        switch self {
        case .grid:          return "Default staggered Nashville grid."
        case .circle:        return "Root chord in the centre, six chords arranged clockwise around the edge."
        case .horizontalBar: return "In landscape, one tall row of all seven chords. Portrait uses the grid."
        case .octave:        return "The twelve notes from C to B as a piano has them, each the root of a chord. A note of the key plays its chord in the key; a note outside it plays a chord borrowed from the nearest scale that has it."
        }
    }
}

/// How the chord keys are arranged on screen.
enum ChordKeyArrangement: CaseIterable {
    /// The staggered Nashville grid, four keys over three.
    case grid
    /// The root in the centre, the other six around it.
    case circle
    /// All seven in one row.
    case row
    /// An octave of piano keys, a key to each note: the chords' roots
    /// (`ChordKey.root`), where the others have the seven degrees.
    case octave
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
        case .octave:        return .octave
        }
    }
}

extension ColorStepRanking {
    var displayName: String {
        switch self {
        case .theory: return "Theory"
        case .common: return "Common"
        }
    }
}

@Observable
@MainActor
final class PerformanceState {
    var key = Key(root: .C, scale: .major) {
        didSet {
            guard key != oldValue else { return }
            timelinePlayer?.live = liveSettings
            logger?.log(.key_changed(key: "\(key.root.name) \(key.scale.displayName)"))
        }
    }
    /// How the keys' chords are voiced, as set: the octave and the
    /// inversion. A change reaches the chord being held at once, tied to
    /// it, so only the notes that move are struck.
    var voicing = KeyVoicing(octave: 4, inversion: .root) {
        didSet {
            guard voicing != oldValue else { return }
            timelinePlayer?.live = liveSettings
            if voicing.octave != oldValue.octave { logger?.log(.octave_changed(octave: voicing.octave)) }
            if voicing.inversion != oldValue.inversion {
                logger?.log(.inversion_changed(steps: voicing.inversion.steps))
            }
            mode.onColorChange(state: self)
        }
    }
    /// The octave the keys' chords are built in, as set.
    var octave: Int {
        get { voicing.octave }
        set { voicing.octave = newValue }
    }
    /// The octaves the keys can be set to.
    nonisolated static let octaves = 2...7
    /// How far the keys' chords are rolled from root position, as set
    /// (`Inversion`).
    var inversion: Inversion {
        get { voicing.inversion }
        set { voicing.inversion = newValue }
    }
    /// The inversions the keys can be set to, as steps: two octaves of a
    /// four-note chord either way.
    nonisolated static let inversions = -8...8

    /// The key the chord keys are in now: the key zone's under the finger
    /// if it has one of its own (`KeyZone.key`), the key chosen otherwise.
    var homeKey: Key { effects.heldZone?.key ?? key }
    /// The key a chord played now is in: the key the keys are in, or for a
    /// root outside it the key its chord is borrowed from (`ChordKey.chord`).
    var playedKey: Key { activeKey?.chord(in: homeKey).key ?? homeKey }
    /// Whether the voicing field keeps what it is set to (`VoicingField`).
    /// While it does not, the field is played: the chords are held where
    /// its finger is and go back to the voicing as set when it lifts.
    var keepsVoicing = true {
        didSet {
            guard keepsVoicing != oldValue else { return }
            logger?.log(.voicing_keep_switched(isOn: keepsVoicing))
        }
    }
    /// How far the voicing field's finger holds the chords from the voicing
    /// as set, while the field does not keep it.
    private(set) var voicingBend = VoicingBend.none
    /// The voicing as the voicing field has it: as set, and as far from
    /// that as its finger holds it.
    var heldVoicing: KeyVoicing { voicing.bent(by: voicingBend) }

    /// The octave a chord of the key the keys are in is built in now: the
    /// key zone's under the finger if it has one of its own, or else the
    /// octave chosen, as far up or down as the voicing field holds it.
    private var builtOctave: Int {
        (effects.heldZone?.octave ?? octave) + voicingBend.octaves
    }
    /// The octave a chord played now is in: the one chords are built in,
    /// moved as the key played moves it (`ChordKey.octaveShift`).
    var playedOctave: Int {
        builtOctave + (activeKey?.octaveShift(in: homeKey) ?? 0)
    }
    /// The inversion a chord played now is in: the key zone's under the
    /// finger if it has one of its own, the inversion chosen otherwise,
    /// rolled as far as the slide plays it (`EffectsState.slideRoll`) and
    /// the voicing field holds it.
    var playedInversion: Inversion {
        (effects.heldZone?.inversion ?? inversion).rolled(by: effects.slideRoll + voicingBend.steps)
    }
    private(set) var synthPreset: SynthPreset = .initial
    /// Always within `MusicalTime.tempoRange`; change it with `setBPM`.
    private(set) var bpm = MusicalTime.defaultTempo

    var chordGridLayout: ChordGridLayout = .circle
    /// Whether the play screen has the key strip (`KeyStrip`): the key and
    /// the voicing.
    var showsKeyStrip = true
    var isExternalSynth: Bool = false {
        didSet { output?.isExternalSynth = isExternalSynth }
    }

    private(set) var mode: any PerformanceMode = PlayMode()
    /// The order the step compass's choices are in (`ColorStepRanking`).
    var compassRanking = ColorStepRanking.theory {
        didSet {
            guard compassRanking != oldValue else { return }
            logger?.log(.compass_ranking_switched(ranking: compassRanking.displayName))
            compassColorChanged()
        }
    }
    /// Whether the step compass keeps what it is set to. While it does not,
    /// a place plays while a finger is on it, a step from the plain chord,
    /// and can come down before the chord, so the chord starts colored.
    /// While it does, each place tapped is a step from the last (two adds
    /// are a 9th chord), kept for every chord until the middle clears it.
    var keepsCompassColor = false {
        didSet {
            guard keepsCompassColor != oldValue else { return }
            logger?.log(.compass_keep_switched(isOn: keepsCompassColor))
            heldPlace = nil
            compassWalk = []
            compassColorChanged()
        }
    }
    /// Whether the compass names each place by the chord it plays on the
    /// chord held. Off, its places keep their own names ("+ tone", "raise"),
    /// whatever chord is held. It changes nothing that sounds.
    var compassShowsChords = true
    /// The compass's place a finger is on while it does not keep.
    private(set) var heldPlace: CompassPlace? = nil
    /// The places tapped while the compass keeps, in order: each a step
    /// from where the last led, so each degree takes the walk as its own.
    private(set) var compassWalk: [CompassPlace] = []
    /// The places the compass's color is made by: the walk kept, or the
    /// place held.
    var compassPlaces: [CompassPlace] { keepsCompassColor ? compassWalk : heldPlace.map { [$0] } ?? [] }

    /// The live chord color for `degree`: the compass's places, each a step
    /// resolved against the degree that plays in `key` (the key being
    /// played, unless another is given). With no place, the diatonic triad
    /// plays.
    func color(for degree: Degree, in key: Key? = nil) -> ChordColor {
        let places = compassPlaces
        guard !places.isEmpty else { return .base }
        return .tones(StepCompass.walk(places, key: key ?? playedKey, degree: degree, ranking: compassRanking))
    }
    private(set) var activeDegree: Degree? = nil
    /// The chord keys that are down, oldest first; the last is the active press.
    private(set) var heldKeys: [ChordKey] = []
    /// The key whose press is the active one; nil while none is down.
    var activeKey: ChordKey? { heldKeys.last }
    /// How far up each held key its finger is, 0 at the bottom to 1 at the
    /// top. The active key's is the one that plays the effects (`EffectsState.slide`).
    private var slides: [ChordKey: Float] = [:]
    private(set) var currentVoicing: Voicing? = nil
    /// The context `currentVoicing` was built from; a single note of the
    /// active chord (lead) is sent with it.
    private var currentContext: ChordContext? = nil
    private(set) var activeVoicingText = "—"

    let sequencerState: SequencerState
    let quickLoopState: QuickLoopState
    let effects: EffectsState
    /// The computer keyboard, as a way to play the keys and the compass.
    let keyboard: KeyboardState
    /// A game controller, as one more way to play them.
    let gamepad: GamepadState
    /// The piano along the bottom of the screen, lit with what is sounding.
    let piano: PianoState
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
    /// What is told the tempo, to keep time with it.
    private let tempoListener: (any TempoControl)?
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
    /// `micGate` says whether the mic sample may be recorded.
    /// `sequencer` is the app's sequencer and its saved timeline; tests pass
    /// one with a store of its own.
    /// `keyboard` is the computer keyboard and its saved map, likewise,
    /// and `gamepad` a game controller and its.
    /// `piano` is the piano whose lines the sinks above were made with
    /// (`PianoState.line`); without one the piano stays dark.
    init(sink: any ChordEventSink,
         chordListener: (any ChordEventSink)? = nil,
         layerSink: (() -> any ChordEventSink)? = nil,
         layerLead: Double = 0,
         sequencer: SequencerState? = nil,
         keyboard: KeyboardState? = nil,
         gamepad: GamepadState? = nil,
         piano: PianoState? = nil,
         liveSound: (any SoundControl & EffectsControl)? = nil,
         output: AudioOutput? = nil,
         micGate: any PermissionGate = NoopPermissionGate(),
         effectsListener: (any EffectsControl)? = nil,
         tempoListener: (any TempoControl)? = nil,
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
        self.keyboard     = keyboard ?? KeyboardState(logger: logger)
        self.gamepad      = gamepad ?? GamepadState(logger: logger)
        self.piano        = piano ?? PianoState(logger: logger)
        self.sequencerState = sequencer ?? SequencerState(logger: logger)
        self.quickLoopState = QuickLoopState(logger: logger)
        self.micAccess = MicAccess(gate: micGate)
        self.micSample = MicSampleState(recorder: output?.sampleRecorder, access: micAccess)
        self.tempoListener = tempoListener
        self.clock.bpm = bpm
        tempoListener?.setTempo(bpm)
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
        self.keyboard.host = self
        self.gamepad.host = self
        // A sample just recorded is what the keys play next.
        self.micSample.onRecorded = { [weak self] in self?.setSynthPreset(.micSample) }
        attach(sequencerState)
        self.clock.onTick { [weak self] in
            guard let self else { return }
            self.mode.onClockTick(state: self)
        }
    }

    // MARK: – Mode / preset switching

    /// Replaces the active mode. The app has Play mode alone; this is for
    /// callers that supply a configured instance (tests).
    func setMode(_ newMode: any PerformanceMode) {
        logger?.log(.mode_changed(from: mode.name, to: newMode.name))
        heldKeys = []
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
        tempoListener?.setTempo(bpm)
    }

    /// Whether anything that can be played now sends notes to the vocoder:
    /// the keys' effects as set.
    private var hearsTheMic: Bool { effects.hearsTheMic }

    /// Opens the mic to the vocoder while something wants it, asking for
    /// the mic first if need be; a refusal switches the keys' vocoder back
    /// off, since it would have nothing to hear.
    private func hearTheMicIfWanted() {
        guard let output else { return }
        guard hearsTheMic else {
            output.isVocoding = false
            return
        }
        guard !output.isVocoding else { return }
        micAccess.ask(then: { [weak self] in
            guard let self, hearsTheMic else { return }
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

    func press(_ key: ChordKey) {
        heldKeys.append(key)
        followSlide()
        mode.onButtonDown(key: key, state: self)
    }

    func release(_ key: ChordKey) {
        release([key])
    }

    /// Keys lifted together (several fingers at once, or the chord surface
    /// going away). They leave as one step, so the chord is handed back only
    /// to a key that is still down afterwards.
    func release(_ keys: [ChordKey]) {
        guard let active = heldKeys.last else { return }
        var activeLifted = false
        for key in keys {
            guard let index = heldKeys.lastIndex(of: key) else { continue }
            if index == heldKeys.count - 1 { activeLifted = true }
            heldKeys.remove(at: index)
        }
        // The last key up ends its chord before its slide: an effect the
        // finger was holding on (a key zone) must not switch off under a
        // chord that is about to stop, which would sound it once more.
        if activeLifted, heldKeys.isEmpty { mode.onButtonUp(key: active, state: self) }
        followSlide()
        // Two presses of the same key: it is still held, nothing changes.
        if activeLifted, let resumed = heldKeys.last, resumed != active {
            mode.onButtonDown(key: resumed, state: self)
        }
    }

    /// One key change: `old` went up and `new` came down (either may be nil: touch down,
    /// lift). The new key is pressed before the old one is released, so a
    /// finger sliding across chords never leaves a gap: the new chord replaces
    /// the old, and the old release is superseded.
    func movePointer(from old: ChordKey?, to new: ChordKey?) {
        guard old != new else { return }
        if let new { press(new) }
        if let old { release(old) }
    }

    // MARK: – Key slide

    /// The finger on `key` is `height` of the way up it (0 at the bottom,
    /// 1 at the top). Report it before pressing the key, so the chord
    /// starts where the finger landed. Like the chord, the slide that is
    /// heard is the most recent press's, and lifting that press hands it
    /// back to the key held beneath.
    ///
    /// A finger that moves into a key zone with another key, octave or
    /// inversion changes the chord it is holding, as a change of color
    /// does, and so does one that moves to another inversion while the
    /// slide plays that.
    func slide(on key: ChordKey, to height: Float) {
        slides[key] = height
        guard key == heldKeys.last else { return }
        let was = (playedKey, playedOctave, playedInversion)
        followSlide()
        if (playedKey, playedOctave, playedInversion) != was { mode.onColorChange(state: self) }
    }

    /// Makes the active key and its slide the ones that are heard, and
    /// forgets the slides of keys no longer held.
    private func followSlide() {
        slides = slides.filter { heldKeys.contains($0.key) }
        let active = heldKeys.last
        effects.hold(active.flatMap(zonedDegree), at: active.flatMap { slides[$0] })
    }

    /// The degree whose zones `key` is divided by: a degree's key has that
    /// degree's, and so has the octave's key for a note of the key chosen.
    /// A root outside the key has every key's (`EffectsState.zones(of:)`),
    /// and is read against them by its finger's place, which a touch
    /// always has.
    func zonedDegree(of key: ChordKey) -> Degree? {
        key.degree(in: self.key)
    }

    // MARK: – Chord colors (delegate to mode)

    /// A finger came down on the compass's `place`. Played, it is a step
    /// from the plain chord until it lifts (`compassLifted`), the latest
    /// place if several are down; kept, it is one more step of the walk.
    func compassPressed(_ place: CompassPlace) {
        if keepsCompassColor {
            compassWalk.append(place)
        } else {
            guard place != heldPlace else { return }
            heldPlace = place
        }
        compassColorChanged()
    }

    /// A finger lifted from the compass's `place`: if it was the place
    /// playing, the chord is plain again. A walk kept is not changed.
    func compassLifted(_ place: CompassPlace) {
        guard !keepsCompassColor, heldPlace == place else { return }
        heldPlace = nil
        compassColorChanged()
    }

    /// The compass's middle: back to the plain chord.
    func compassCleared() {
        guard heldPlace != nil || !compassWalk.isEmpty else { return }
        heldPlace = nil
        compassWalk = []
        compassColorChanged()
    }

    /// The chord the compass's places step from for `degree`: the plain
    /// chord while it plays, the walk so far while it keeps.
    func compassOrigin(for degree: Degree) -> ChordTones {
        keepsCompassColor
            ? StepCompass.walk(compassWalk, key: playedKey, degree: degree, ranking: compassRanking)
            : StepCompass.base(key: playedKey, degree: degree)
    }

    private func compassColorChanged() {
        let degree = activeDegree ?? .I
        logger?.log(.compass_color_changed(
            places: compassPlaces.map { "\($0.kind)\($0.rank)" },
            color: chordLabel(key: playedKey, spec: ChordSpec(degree: degree, color: color(for: degree)))))
        mode.onColorChange(state: self)
    }

    // MARK: – Mode-facing API

    func startChord(_ key: ChordKey) {
        let sounding = activeDegree == nil ? nil : currentContext
        let voicing = select(key)
        if let context = currentContext {
            logger?.log(.chord_button_pressed(
                degree: context.spec.degree.rawValue,
                key: "\(context.key.root.name) \(context.key.scale.displayName)",
                color: colorActionLabel(context.spec.color),
                resultingNotes: voicing.notes
            ))
        }
        // A chord voiced another way keeps the notes it has in common with
        // the one sounding: only those that moved are struck.
        let isRevoiced = sounding.map { currentContext?.isRevoiced(from: $0) == true } ?? false
        sound(voicing, isRevoiced ? .tied : .block, source: .button)
    }

    // MARK: – The voicing field

    /// The voicing field's finger is at `voicing`. It is set, if the field
    /// keeps what it is set to; if not it is played, and the voicing as set
    /// is left as it was. Either way the chord being held takes it up.
    func holdVoicing(at voicing: KeyVoicing) {
        if keepsVoicing {
            self.voicing = voicing
        } else {
            bendVoicing(by: self.voicing.bend(to: voicing))
        }
    }

    /// The voicing field's finger has lifted: what it played and did not
    /// set is over, and the chord being held goes back to the voicing as
    /// set.
    func releaseVoicing() {
        bendVoicing(by: .none)
    }

    private func bendVoicing(by bend: VoicingBend) {
        guard bend != voicingBend else { return }
        voicingBend = bend
        logger?.log(.voicing_bent(octaves: bend.octaves, steps: bend.steps))
        mode.onColorChange(state: self)
    }

    func endChord() {
        let notes = currentVoicing?.notes ?? []
        activeDegree = nil
        activeVoicingText = "—"
        sink.stopChord()
        quickLoopState.chordEnded()
        logger?.log(.chord_stopped(notes: notes, source: .button))
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
        LiveSettings(key: key, octave: octave, inversion: inversion, preset: synthPreset, effects: effects.asSet)
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
        guard layer == playingSequencer?.layerID, heldKeys.isEmpty else { return }
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

    /// Makes the chord `key` plays the active one: voices it and updates
    /// the display. The chord is the key's in the key the keys are in now,
    /// in the color on the surface, whichever key's press is the active
    /// one. The OLED text is `chordLabel` of the same spec, which reads the
    /// shape that produces these notes, so the label can never disagree
    /// with what sounds.
    @discardableResult
    private func select(_ key: ChordKey) -> Voicing {
        let chord = key.chord(in: homeKey)
        let spec = ChordSpec(degree: chord.degree, color: color(for: chord.degree, in: chord.key))
        let octave = builtOctave + key.octaveShift(in: homeKey)
        let context = performanceContext(key: chord.key, octave: octave, spec: spec, inversion: playedInversion)
        let voicing = context.voicing(after: currentVoicing)
        activeDegree = spec.degree
        currentContext = context
        currentVoicing = voicing
        activeVoicingText = chordLabel(key: chord.key, spec: spec)
        return voicing
    }

    /// Sends `voicing` to every sink as part of the active chord. `pitch`
    /// says what of the chord it is, for a loop being recorded.
    private func sound(_ voicing: Voicing, _ articulation: Articulation, pitch: NotePitch = .chord,
                       source: ChordSource) {
        guard let currentContext else { return }
        let event = ChordEvent(voicing: voicing, articulation: articulation, context: currentContext)
        sink.playChord(event)
        // A loop keeps the chord in the key, octave and inversion it was built in.
        let playing = NotePlaying(key: currentContext.key, octave: currentContext.octave,
                                  inversion: currentContext.inversion,
                                  preset: synthPreset, effects: effects.asPlayed)
        quickLoopState.chordStarted(event, pitch: pitch, playing: playing)
        logger?.log(.chord_played(notes: voicing.notes, source: source))
    }
}

extension PerformanceState: LoopHost {
    var loopSequencer: SequencerState? { playingSequencer }

    var clockBeats: Double { clock.beats }

    var playedNow: NotePlaying {
        NotePlaying(key: playedKey, octave: playedOctave, inversion: playedInversion, preset: synthPreset,
                    effects: effects.asPlayed)
    }
}

extension PerformanceState: KeyboardHost {
    func tap(_ button: KeyboardButton) {
        switch button {
        case .loop:     quickLoopState.triggerTapped()
        case .midi:     isExternalSynth.toggle()
        case .playStop: quickLoopState.toggleRunning()
        }
    }
}
