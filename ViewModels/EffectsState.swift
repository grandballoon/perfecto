import Observation

/// The effects' controls: the arpeggiator, which changes which notes play
/// and when, and the chorus, reverb, delay and vocoder, which change how
/// they sound.
/// Views edit the settings here; each change is passed straight on to the
/// part that realizes it.
///
/// The effects are also played: while a chord key is held, the finger's
/// place on it (`slide`) stands in for one set value of every effect that
/// follows it (`SlidePlayed`), and the key zone the finger is in (`zones`,
/// or that key's own, `keyZones`) holds its effect on. What is passed on is
/// always the effect as played; the settings here stay as they were set.
///
/// The slide can also play how bright the notes are (`slidePlaysBrightness`,
/// a switch in Setup): dark at the bottom of a key and the whole sound at
/// its top. That is not an effect: it has no settings, no field and no zone.
/// Nor is the chord's inversion, which the slide can play as well
/// (`slidePlaysInversion`, `slideRoll`).
///
/// An arpeggio can also be held on from outside the keys (`heldArpeggio`,
/// the controller's arpeggio wheel, or how hard its keys are struck), over
/// the slide and the zones.
///
/// The play screen has a field for each effect that is on (`slots`), which
/// switches the effects by the same settings.
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
            switched(.arpeggiator, from: oldValue.isOn, to: arpeggiator.isOn)
        }
    }

    var chorus = ChorusSettings() {
        didSet {
            guard chorus != oldValue else { return }
            onSetChange?()
            onPlayedChange?()
            sendChorus()
            switched(.chorus, from: oldValue.isOn, to: chorus.isOn)
        }
    }

    var reverb = ReverbSettings() {
        didSet {
            guard reverb != oldValue else { return }
            onSetChange?()
            onPlayedChange?()
            sendReverb()
            switched(.reverb, from: oldValue.isOn, to: reverb.isOn)
        }
    }

    var delay = DelaySettings() {
        didSet {
            guard delay != oldValue else { return }
            onSetChange?()
            onPlayedChange?()
            sendDelay()
            switched(.delay, from: oldValue.isOn, to: delay.isOn)
        }
    }

    var vocoder = VocoderSettings() {
        didSet {
            guard vocoder != oldValue else { return }
            onSetChange?()
            onPlayedChange?()
            sendVocoder()
            switched(.vocoder, from: oldValue.isOn, to: vocoder.isOn)
        }
    }

    /// Whether the slide plays how bright the notes are. Off, and with no
    /// finger on a key, every note is as bright as its preset makes it.
    var slidePlaysBrightness = false {
        didSet {
            guard slidePlaysBrightness != oldValue else { return }
            sendBrightness()
            onPlayedChange?()
            logger?.log(.slide_brightness_switched(isOn: slidePlaysBrightness))
        }
    }

    /// Whether the slide plays the chord's inversion (`InversionSlide`): the
    /// middle of a key is the inversion as set, and the chord is rolled
    /// further up above it and further down below.
    var slidePlaysInversion = false {
        didSet {
            guard slidePlaysInversion != oldValue else { return }
            slideRoll = rollHeld(from: nil)
            onPlayedChange?()
            logger?.log(.slide_inversion_switched(isOn: slidePlaysInversion))
        }
    }

    /// The steps the finger playing the chord rolls it from the inversion
    /// set, by its place on the key; 0 while the slide does not play the
    /// inversion, no key is held, or the key has no place on it.
    private(set) var slideRoll = 0

    /// The steps the finger rolls the chord where it is now, given the
    /// steps it did before.
    private func rollHeld(from current: Int?) -> Int {
        slidePlaysInversion ? InversionSlide.steps(at: place, from: current) : 0
    }

    /// The bands every chord key is divided into, and the effect each plays.
    /// Its switch is the key zones' as a whole: off, no key has any, its
    /// own (`keyZones`) included.
    var zones = KeyZoneSettings() {
        didSet {
            guard zones != oldValue else { return }
            let switched = zones.isOn != oldValue.isOn
            // The keys' own zones go on and off with the switch.
            zonesChanged(oldValue.zones + zones.zones + (switched ? keyZones.values.flatMap(\.zones) : []))
            if switched { logger?.log(.key_zones_switched(isOn: zones.isOn)) }
            onSetChange?()
        }
    }

    /// The zones of the keys that have their own. While a key's are on it
    /// is divided by them alone, in place of every key's (`zones`), so an
    /// effect can be on one key, or on one part of one key.
    var keyZones: [Degree: KeyZoneSettings] = [:] {
        didSet {
            guard keyZones != oldValue else { return }
            for key in Degree.allCases where keyZones[key] != oldValue[key] {
                let (old, new) = (oldValue[key] ?? .ofOneKey, keyZones[key] ?? .ofOneKey)
                zonesChanged(old.zones + new.zones)
                if new.isOn != old.isOn { logger?.log(.key_own_zones_switched(degree: key.rawValue, isOn: new.isOn)) }
            }
            onSetChange?()
        }
    }

    /// The zones the key for `key` is divided into: its own while they are
    /// on, every key's otherwise (and for no key in particular). While the
    /// key zones are off they are every key's, which are off.
    func zones(of key: Degree?) -> KeyZoneSettings {
        if zones.isOn, let key, let own = keyZones[key], own.isOn { return own }
        return zones
    }

    /// How far up its key the finger playing the chord is, from 0 at the
    /// bottom to 1 at the top; nil while no key is held, and for a key
    /// with no place on it.
    var slide: Float? {
        get { place }
        set { hold(heldKey, at: newValue) }
    }

    /// The chord key being played, whose zones the finger is read against;
    /// nil while none is.
    private(set) var heldKey: Degree?

    private var place: Float?

    /// The chord is now played from `key`, by a finger at `slide` on it
    /// (nil: the key has no place, or no key is held). The two change as
    /// one step, so a finger is never read against another key's zones.
    func hold(_ key: Degree?, at slide: Float?) {
        guard key != heldKey || slide != place else { return }
        let was = heldZone
        // A zone holds on to a finger at its edge, not to one on another key.
        let isSameKey = key == heldKey
        let current = isSameKey ? zone : nil
        heldKey = key
        place = slide
        zone = zoneHeld(from: current)
        slideRoll = rollHeld(from: isSameKey ? slideRoll : nil)
        let zoned = heldZone == was ? [] : [was?.effect?.kind, heldZone?.effect?.kind]
        for effect in EffectKind.allCases where follows(effect) || zoned.contains(effect) {
            send(effect)
        }
        if slidePlaysBrightness { sendBrightness() }
        onPlayedChange?()
    }

    /// The arpeggio held on from outside the keys, which plays in place of
    /// the arpeggiator as set and as the finger plays it; nil while none is.
    private(set) var heldArpeggio: HeldArpeggio?

    func holdArpeggio(_ arpeggio: HeldArpeggio?) {
        guard arpeggio != heldArpeggio else { return }
        heldArpeggio = arpeggio
        sendArpeggiator()
        onPlayedChange?()
    }

    /// The key zone the finger playing the chord is in, counted from the
    /// bottom of the key; nil while the zones are off or no key is held.
    private(set) var zone: Int?

    /// The key zone the finger playing the chord is in, as it is set.
    var heldZone: KeyZone? { zone.map { zones(of: heldKey).zones[$0] } }

    /// The zone of the held key that the finger is in, given the one it
    /// was in before.
    private func zoneHeld(from current: Int?) -> Int? {
        let zones = zones(of: heldKey)
        if place == nil, heldKey != nil { return zones.whole }
        return zones.zone(at: place, from: current)
    }

    /// Zones were set to something new: the finger is read against them
    /// again, and every effect that `changed` (the zones as they were and
    /// as they are) names is passed on.
    private func zonesChanged(_ changed: [KeyZone]) {
        zone = zoneHeld(from: nil)
        for effect in EffectKind.allCases where changed.contains(where: { $0.effect?.kind == effect }) {
            send(effect)
        }
    }

    /// The play screen's effect fields: the effects that are on, each in
    /// its place in the row. They follow the settings, however an effect
    /// is switched.
    private(set) var slots = EffectSlots()

    /// The effect in each slot as it is set; nil is an empty slot.
    var slotChoices: [EffectChoice?] {
        let set = asSet
        return slots.kinds.map { $0.flatMap(set.choice(of:)) }
    }

    /// Changes `slot` to `choice`: the effect it had is switched off and
    /// the chosen one on (nil: none is). A choice whose effect another slot
    /// has is not taken.
    func setSlot(_ slot: Int, to choice: EffectChoice?) {
        guard slots.kinds.indices.contains(slot) else { return }
        let was = slots.kinds[slot]
        slots.put(choice?.kind, in: slot)
        guard slots.kinds[slot] == choice?.kind else { return }
        var set = asSet
        if let was, was != choice?.kind { set.switchOff(was) }
        if let choice { set.switchOn(choice) }
        asSet = set
    }

    /// Adds an empty slot to the row, for one more effect.
    func addSlot() { slots.add() }

    /// The finger changing a slot has lifted: the row closes up over the
    /// slots left empty.
    func settleSlots() { slots.settle() }

    /// Every effect as it sounds now, the slide and the key zones applied:
    /// what a chord played now is played with.
    var asPlayed: NoteEffects {
        NoteEffects(arpeggiator: playedArpeggiator,
                    chorus: played(chorus), reverb: played(reverb), delay: played(delay),
                    vocoder: played(vocoder),
                    brightness: playedBrightness)
    }

    /// How bright a note played now is: where the finger is on its key,
    /// while the slide plays that.
    private var playedBrightness: Float {
        slidePlaysBrightness ? slide ?? 1 : 1
    }

    /// Every effect as set, whatever is being played: what a note of a
    /// timeline follows when it has no effects of its own.
    var asSet: NoteEffects {
        get {
            NoteEffects(arpeggiator: arpeggiator, chorus: chorus, reverb: reverb, delay: delay,
                        vocoder: vocoder)
        }
        set {
            arpeggiator = newValue.arpeggiator
            chorus = newValue.chorus
            reverb = newValue.reverb
            delay = newValue.delay
            vocoder = newValue.vocoder
        }
    }

    /// Whether anything set here needs the mic: the vocoder switched on,
    /// or a key zone that switches it on.
    var hearsTheMic: Bool {
        vocoder.isOn || allZones.contains { $0.zones.contains { $0.effect == .vocoder } }
    }

    var isAnyOn: Bool { asSet.hasAnyOn || zones.isOn }

    /// The zones a key can be divided into now: every key's, and those of
    /// each key that has its own.
    private var allZones: [KeyZoneSettings] {
        zones.isOn ? [zones] + keyZones.values.filter(\.isOn) : []
    }

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

    /// `set` as it sounds now: held on by the zone under the finger if
    /// that is its zone, played by the slide otherwise.
    private func played<Settings: EffectSettings>(_ set: Settings) -> Settings {
        guard let held = heldZone, held.effect?.kind == Settings.kind else { return set.played(by: slide) }
        return set.held(at: held.value)
    }

    /// The arpeggiator as it sounds now. A zone that holds it on also says
    /// which of the two arpeggios it plays, and an arpeggio held on from
    /// outside the keys is played over both.
    private var playedArpeggiator: ArpeggiatorSettings {
        var played = played(arpeggiator)
        if let heldArpeggio {
            played.isOn = true
            played.pattern = heldArpeggio.pattern
            if let cycle = heldArpeggio.cycle { played.cycle = cycle }
            return played
        }
        if let pattern = heldZone?.effect?.pattern { played.pattern = pattern }
        return played
    }

    /// `effect`'s settings, as set.
    private func set(_ effect: EffectKind) -> any EffectSettings {
        switch effect {
        case .arpeggiator: return arpeggiator
        case .chorus:      return chorus
        case .reverb:      return reverb
        case .delay:       return delay
        case .vocoder:     return vocoder
        }
    }

    private func follows(_ effect: EffectKind) -> Bool { set(effect).isPlayed }

    private func send(_ effect: EffectKind) {
        switch effect {
        case .arpeggiator: sendArpeggiator()
        case .chorus:      sendChorus()
        case .reverb:      sendReverb()
        case .delay:       sendDelay()
        case .vocoder:     sendVocoder()
        }
    }

    private func sendArpeggiator() {
        arpeggiatorSink.settings = playedArpeggiator
    }

    private func sendChorus() {
        let played = played(chorus)
        for control in controls { control.setChorus(played) }
    }

    private func sendReverb() {
        let played = played(reverb)
        for control in controls { control.setReverb(played) }
    }

    private func sendDelay() {
        let played = played(delay)
        for control in controls { control.setDelay(played) }
    }

    private func sendVocoder() {
        let played = played(vocoder)
        for control in controls { control.setVocoder(played) }
    }

    private func sendBrightness() {
        let played = playedBrightness
        for control in controls { control.setBrightness(played) }
    }

    /// `effect` was set: if that switched it, its slot follows.
    private func switched(_ effect: EffectKind, from wasOn: Bool, to isOn: Bool) {
        guard isOn != wasOn else { return }
        slots.follow(effect, isOn: isOn)
        logger?.log(.effect_switched(effect: effect, isOn: isOn))
    }
}
