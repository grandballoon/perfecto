import Observation

/// The effects' controls: the arpeggiator, which changes which notes play
/// and when, and the filter, chorus, reverb and vocoder, which change how
/// they sound.
/// Views edit the settings here; each change is passed straight on to the
/// part that realizes it.
///
/// The effects are also played: while a chord key is held, the finger's
/// place on it (`slide`) stands in for one set value of every effect that
/// follows it (`SlidePlayed`), and the key zone the finger is in (`zones`)
/// holds its effect on. A finger on the effect slider (`slider`) plays one
/// effect's control by itself, whatever the key says. What is passed on is
/// always the effect as played; the settings here stay as they were set.
@Observable
@MainActor
final class EffectsState {

    /// Called when an effect is set to something new (not when one is only
    /// played): whatever follows the settings as set reads them again.
    var onSetChange: (() -> Void)?
    /// Called when how the effects are being played may have changed: a
    /// setting, the slide, or the zone under the finger.
    var onPlayedChange: (() -> Void)?

    var arpeggiator = ArpeggiatorSettings() {
        didSet {
            guard arpeggiator != oldValue else { return }
            onSetChange?()
            onPlayedChange?()
            sendArpeggiator()
            logSwitch(.arpeggiator, from: oldValue.isOn, to: arpeggiator.isOn)
        }
    }

    var filter = FilterSettings() {
        didSet {
            guard filter != oldValue else { return }
            onSetChange?()
            onPlayedChange?()
            sendFilter()
            logSwitch(.filter, from: oldValue.isOn, to: filter.isOn)
        }
    }

    var chorus = ChorusSettings() {
        didSet {
            guard chorus != oldValue else { return }
            onSetChange?()
            onPlayedChange?()
            sendChorus()
            logSwitch(.chorus, from: oldValue.isOn, to: chorus.isOn)
        }
    }

    var reverb = ReverbSettings() {
        didSet {
            guard reverb != oldValue else { return }
            onSetChange?()
            onPlayedChange?()
            sendReverb()
            logSwitch(.reverb, from: oldValue.isOn, to: reverb.isOn)
        }
    }

    var vocoder = VocoderSettings() {
        didSet {
            guard vocoder != oldValue else { return }
            onSetChange?()
            onPlayedChange?()
            sendVocoder()
            logSwitch(.vocoder, from: oldValue.isOn, to: vocoder.isOn)
        }
    }

    /// The bands every chord key is divided into, and the effect each plays.
    var zones = KeyZoneSettings() {
        didSet {
            guard zones != oldValue else { return }
            zone = zones.zone(at: slide, from: nil)
            for effect in EffectKind.allCases where (oldValue.zones + zones.zones).contains(where: { $0.effect == effect }) {
                send(effect)
            }
            if zones.isOn != oldValue.isOn { logger?.log(.key_zones_switched(isOn: zones.isOn)) }
            onSetChange?()
        }
    }

    /// How far up its key the finger playing the chord is, from 0 at the
    /// bottom to 1 at the top; nil while no key is held.
    var slide: Float? {
        didSet {
            guard slide != oldValue else { return }
            let left = zoneEffect
            let wasIn = zone
            zone = zones.zone(at: slide, from: zone)
            let zoned = zone == wasIn ? [] : [left, zoneEffect]
            for effect in EffectKind.allCases where follows(effect) || zoned.contains(effect) {
                send(effect)
            }
            onPlayedChange?()
        }
    }

    /// The key zone the finger playing the chord is in, counted from the
    /// bottom of the key; nil while the zones are off or no key is held.
    private(set) var zone: Int?

    /// The key zone the finger playing the chord is in, as it is set.
    var heldZone: KeyZone? { zone.map { zones.zones[$0] } }

    /// Where a finger on the effect slider holds each effect's played
    /// control, as a place on the slide (0...1); an effect with no finger
    /// on its lane has no entry. Change it with `sliderMoved`.
    private(set) var slider: [EffectKind: Float] = [:]

    /// A finger on the effect slider is at `place` (0...1) on `effect`'s
    /// lane (nil: lifted). While it is there it plays the effect's control,
    /// over the slide and the key zones; lifting returns to what they play.
    /// An effect that is off is not switched on by it.
    func sliderMoved(_ effect: EffectKind, to place: Float?) {
        let place = place.map { $0.clamped(to: 0...1) }
        guard place != slider[effect] else { return }
        if slider[effect] == nil { logger?.log(.effect_slider_touched(effect: effect)) }
        slider[effect] = place
        send(effect)
        onPlayedChange?()
    }

    /// The effects that are on, in the order the effect slider shows them:
    /// each has a lane there.
    var slidable: [EffectKind] { EffectKind.allCases.filter { set($0).isOn } }

    /// Where `effect`'s played control is now, as a place on the slide:
    /// under the finger on its lane of the effect slider, or where it is
    /// played from the keys.
    func place(of effect: EffectKind) -> Float {
        slider[effect] ?? played(set(effect)).place
    }

    /// Every effect as it sounds now, the slide, the key zones and the
    /// effect slider applied:
    /// what a chord played now is played with.
    var asPlayed: NoteEffects {
        NoteEffects(arpeggiator: played(arpeggiator), filter: played(filter),
                    chorus: played(chorus), reverb: played(reverb), vocoder: played(vocoder))
    }

    /// Every effect as set, whatever is being played: what a note of a
    /// timeline follows when it has no effects of its own.
    var asSet: NoteEffects {
        get {
            NoteEffects(arpeggiator: arpeggiator, filter: filter, chorus: chorus, reverb: reverb, vocoder: vocoder)
        }
        set {
            arpeggiator = newValue.arpeggiator
            filter = newValue.filter
            chorus = newValue.chorus
            reverb = newValue.reverb
            vocoder = newValue.vocoder
        }
    }

    /// Whether anything set here needs the mic: the vocoder switched on,
    /// or a key zone that switches it on.
    var hearsTheMic: Bool {
        vocoder.isOn || (zones.isOn && zones.zones.contains { $0.effect == .vocoder })
    }

    var isAnyOn: Bool { arpeggiator.isOn || filter.isOn || chorus.isOn || reverb.isOn || vocoder.isOn || zones.isOn }

    private let arpeggiatorSink: Arpeggiator
    private let controls: [any EffectsControl]
    private let logger: (any Logger)?

    /// Production: pass the AudioSink as `audio` and the MidiSink as
    /// `effectsListener`. Tests: omit them (nil → no audio, no MIDI).
    init(arpeggiator: Arpeggiator,
         audio: (any EffectsControl)? = nil,
         effectsListener: (any EffectsControl)? = nil,
         logger: (any Logger)? = nil) {
        self.arpeggiatorSink = arpeggiator
        self.controls = [audio, effectsListener].compactMap { $0 }
        self.logger = logger
    }

    // MARK: – Passing the effects on, as played

    /// The effect the zone under the finger holds on, if it has one.
    private var zoneEffect: EffectKind? { heldZone?.effect }

    /// `set` as it sounds now: played by the finger on its lane of the
    /// effect slider if there is one, held on by the zone under the finger
    /// on the key if that is its zone, played by the slide otherwise.
    private func played<Settings: SlidePlayed>(_ set: Settings) -> Settings {
        if set.isOn, let place = slider[Settings.kind] { return set.playing(place) }
        guard let zone, zones.zones[zone].effect == Settings.kind else { return set.played(by: slide) }
        return set.held(at: zones.zones[zone].value)
    }

    /// `effect`'s settings, as set.
    private func set(_ effect: EffectKind) -> any SlidePlayed {
        switch effect {
        case .arpeggiator: return arpeggiator
        case .filter:      return filter
        case .chorus:      return chorus
        case .reverb:      return reverb
        case .vocoder:     return vocoder
        }
    }

    private func follows(_ effect: EffectKind) -> Bool { set(effect).isPlayed }

    private func send(_ effect: EffectKind) {
        switch effect {
        case .arpeggiator: sendArpeggiator()
        case .filter:      sendFilter()
        case .chorus:      sendChorus()
        case .reverb:      sendReverb()
        case .vocoder:     sendVocoder()
        }
    }

    private func sendArpeggiator() {
        arpeggiatorSink.settings = played(arpeggiator)
    }

    private func sendFilter() {
        let played = played(filter)
        for control in controls { control.setFilter(played) }
    }

    private func sendChorus() {
        let played = played(chorus)
        for control in controls { control.setChorus(played) }
    }

    private func sendReverb() {
        let played = played(reverb)
        for control in controls { control.setReverb(played) }
    }

    private func sendVocoder() {
        let played = played(vocoder)
        for control in controls { control.setVocoder(played) }
    }

    private func logSwitch(_ effect: EffectKind, from wasOn: Bool, to isOn: Bool) {
        guard isOn != wasOn else { return }
        logger?.log(.effect_switched(effect: effect, isOn: isOn))
    }
}
