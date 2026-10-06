import Observation

/// The effects' controls: the arpeggiator, which changes which notes play
/// and when, and the filter, chorus and reverb, which change how they sound.
/// Views edit the settings here; each change is passed straight on to the
/// part that realizes it.
///
/// The effects are also played: while a chord key is held, the finger's
/// place on it (`slide`) stands in for one set value of every effect that
/// follows it (`SlidePlayed`), and the key zone the finger is in (`zones`)
/// holds its effect on. What is passed on is always the effect as played;
/// the settings here stay as they were set.
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

    /// The bands every chord key is divided into, and the effect each plays.
    var zones = KeyZoneSettings() {
        didSet {
            guard zones != oldValue else { return }
            zone = zones.zone(at: slide, from: nil)
            for effect in EffectKind.allCases where (oldValue.zones + zones.zones).contains(where: { $0.effect == effect }) {
                send(effect)
            }
            if zones.isOn != oldValue.isOn { logger?.log(.key_zones_switched(isOn: zones.isOn)) }
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

    /// Every effect as it sounds now, the slide and the key zones applied:
    /// what a chord played now is played with.
    var asPlayed: NoteEffects {
        NoteEffects(arpeggiator: played(arpeggiator), filter: played(filter),
                    chorus: played(chorus), reverb: played(reverb))
    }

    /// Every effect as set, whatever is being played: what a note of a
    /// timeline follows when it has no effects of its own.
    var asSet: NoteEffects {
        NoteEffects(arpeggiator: arpeggiator, filter: filter, chorus: chorus, reverb: reverb)
    }

    var isAnyOn: Bool { arpeggiator.isOn || filter.isOn || chorus.isOn || reverb.isOn || zones.isOn }

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
    private var zoneEffect: EffectKind? { zone.flatMap { zones.zones[$0].effect } }

    /// `set` as it sounds now: held on by the zone under the finger if that
    /// is its zone, played by the slide otherwise.
    private func played<Settings: SlidePlayed>(_ set: Settings) -> Settings {
        guard let zone, zones.zones[zone].effect == Settings.kind else { return set.played(by: slide) }
        return set.held(at: zones.zones[zone].value)
    }

    private func follows(_ effect: EffectKind) -> Bool {
        switch effect {
        case .arpeggiator: return arpeggiator.isPlayed
        case .filter:      return filter.isPlayed
        case .chorus:      return chorus.isPlayed
        case .reverb:      return reverb.isPlayed
        }
    }

    private func send(_ effect: EffectKind) {
        switch effect {
        case .arpeggiator: sendArpeggiator()
        case .filter:      sendFilter()
        case .chorus:      sendChorus()
        case .reverb:      sendReverb()
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

    private func logSwitch(_ effect: EffectKind, from wasOn: Bool, to isOn: Bool) {
        guard isOn != wasOn else { return }
        logger?.log(.effect_switched(effect: effect, isOn: isOn))
    }
}
