import Testing
@testable import Perfecto

@Suite("EffectsState")
@MainActor
struct EffectsStateTests {

    /// Records the settings the audio layer was handed.
    private final class RecordingAudioEffects: AudioEffects {
        private(set) var chorus: [ChorusSettings] = []
        private(set) var reverb: [ReverbSettings] = []
        private(set) var filter: [FilterSettings] = []
        private(set) var loopEffects: [SoundEffects] = []
        func setFilter(_ settings: FilterSettings) { filter.append(settings) }
        func setLoopEffects(_ effects: SoundEffects) { loopEffects.append(effects) }
        func setChorus(_ settings: ChorusSettings) { chorus.append(settings) }
        func setReverb(_ settings: ReverbSettings) { reverb.append(settings) }
        func reset() { chorus = []; reverb = []; filter = []; loopEffects = [] }
    }

    private func makeState() -> (EffectsState, RecordingAudioEffects, RecordingLogger) {
        let audio = RecordingAudioEffects()
        let logger = RecordingLogger()
        let arpeggiator = Arpeggiator(downstream: RecordingSink(), clock: ManualClock())
        return (EffectsState(arpeggiator: arpeggiator, audio: audio, logger: logger), audio, logger)
    }

    private func switches(_ logger: RecordingLogger) -> [String] {
        logger.events.compactMap {
            if case let .effect_switched(effect, isOn) = $0 { "\(effect.rawValue) \(isOn ? "on" : "off")" } else { nil }
        }
    }

    @Test func everythingStartsOff() {
        let (effects, audio, _) = makeState()
        #expect(!effects.isAnyOn)
        #expect(audio.chorus.isEmpty && audio.reverb.isEmpty)
    }

    @Test func soundEffectChangesReachTheAudioLayer() {
        let (effects, audio, _) = makeState()
        effects.chorus.isOn = true
        effects.chorus.amount = 0.9
        effects.reverb.size = 0.2

        #expect(audio.chorus.last == ChorusSettings(isOn: true, amount: 0.9, rate: ChorusSettings().rate))
        #expect(audio.reverb == [ReverbSettings(isOn: false, mix: ReverbSettings().mix, size: 0.2)])
    }

    @Test func settingTheSameValueAgainSendsNothing() {
        let (effects, audio, _) = makeState()
        effects.reverb.mix = 0.5
        effects.reverb.mix = 0.5
        #expect(audio.reverb.count == 1)
    }

    @Test func anyEffectLightsTheIndicator() {
        let (effects, _, _) = makeState()
        effects.reverb.isOn = true
        #expect(effects.isAnyOn)
        effects.reverb.isOn = false
        effects.arpeggiator.isOn = true
        #expect(effects.isAnyOn)
    }

    /// Dragging a slider must not flood the log: only switches are recorded.
    @Test func onlySwitchesAreLogged() {
        let (effects, _, logger) = makeState()
        effects.arpeggiator.isOn = true
        effects.arpeggiator.cycle = .bar
        effects.chorus.isOn = true
        effects.chorus.amount = 0.1
        effects.reverb.isOn = true
        effects.reverb.isOn = false
        #expect(switches(logger) == ["arpeggiator on", "chorus on", "reverb on", "reverb off"])
    }

    // MARK: – Filter and slide

    /// While a key is held the slide plays the brightness; lifting returns
    /// to the set one.
    @Test func theSlidePlaysTheFiltersBrightnessWhileAKeyIsHeld() {
        let (effects, audio, _) = makeState()
        effects.filter = FilterSettings(isOn: true, brightness: 0.8)
        effects.slide = 0.25
        effects.slide = 0.5
        effects.slide = nil

        #expect(audio.filter.map(\.brightness) == [0.8, 0.25, 0.5, 0.8])
        #expect(audio.filter.allSatisfy { $0.isOn })
    }

    @Test func theSlideDoesNothingWhileTheFilterIsOff() {
        let (effects, audio, _) = makeState()
        effects.slide = 0.25
        effects.slide = 0.5
        #expect(audio.filter.isEmpty)
    }

    /// Switched on under a held key, the filter starts where the finger is.
    @Test func switchingTheFilterOnPicksUpTheSlide() {
        let (effects, audio, _) = makeState()
        effects.slide = 0.25
        effects.filter.isOn = true
        #expect(audio.filter == [FilterSettings(isOn: true, brightness: 0.25)])
    }

    /// The set brightness is unchanged by playing.
    @Test func theSlideLeavesTheSetBrightnessAlone() {
        let (effects, _, _) = makeState()
        effects.filter = FilterSettings(isOn: true, brightness: 0.8)
        effects.slide = 0.1
        #expect(effects.filter.brightness == 0.8)
        #expect(effects.filter.played(by: effects.slide).brightness == 0.1)
    }

    @Test func theFilterReachesItsListenerToo() {
        let listener = RecordingAudioEffects()
        let arpeggiator = Arpeggiator(downstream: RecordingSink(), clock: ManualClock())
        let effects = EffectsState(arpeggiator: arpeggiator, effectsListener: listener)
        effects.filter.isOn = true
        effects.slide = 0.3
        #expect(listener.filter.map(\.brightness) == [1, 0.3])
    }

    /// Sliding must not flood the log: only the switch is recorded.
    @Test func onlyTheFiltersSwitchIsLogged() {
        let (effects, _, logger) = makeState()
        effects.filter.isOn = true
        effects.filter.brightness = 0.4
        effects.slide = 0.2
        effects.slide = nil
        #expect(switches(logger) == ["filter on"])
        #expect(effects.isAnyOn)
    }

    // MARK: – Every effect and the slide

    /// The slide plays one control of each effect that follows it, and
    /// leaves the others' alone.
    @Test func theSlidePlaysEveryEffectThatFollowsIt() {
        let (effects, audio, _) = makeState()
        effects.chorus = ChorusSettings(isOn: true, amount: 0.6, rate: 0.2, followsSlide: true)
        effects.reverb = ReverbSettings(isOn: true, mix: 0.3, size: 0.9, followsSlide: true)
        effects.slide = 0.75
        effects.slide = nil

        #expect(audio.chorus.map(\.amount) == [0.6, 0.75, 0.6])
        #expect(audio.chorus.allSatisfy { $0.rate == 0.2 })
        #expect(audio.reverb.map(\.mix) == [0.3, 0.75, 0.3])
        #expect(audio.reverb.allSatisfy { $0.size == 0.9 })
    }

    /// The filter follows the slide unless told not to; the others only when told to.
    @Test func anEffectThatDoesNotFollowTheSlideIsLeftAlone() {
        let (effects, audio, _) = makeState()
        effects.filter = FilterSettings(isOn: true, brightness: 0.8, followsSlide: false)
        effects.chorus.isOn = true
        effects.reverb.isOn = true
        effects.slide = 0.1

        #expect(audio.filter.map(\.brightness) == [0.8])
        #expect(audio.chorus.count == 1 && audio.reverb.count == 1)
        #expect(FilterSettings().followsSlide)
        #expect(!ChorusSettings().followsSlide && !ReverbSettings().followsSlide
                && !ArpeggiatorSettings().followsSlide)
    }

    @Test func switchingAnEffectsSlideOnPicksUpTheSlide() {
        let (effects, audio, _) = makeState()
        effects.reverb.isOn = true
        effects.slide = 0.9
        effects.reverb.followsSlide = true
        #expect(audio.reverb.last?.mix == 0.9)
    }

    /// A loop keeps the chorus and reverb that were set, not the ones a
    /// finger happened to be playing when it closed.
    @Test func loopsAreGivenTheEffectsAsSet() {
        let (effects, audio, _) = makeState()
        effects.reverb = ReverbSettings(isOn: true, mix: 0.3, size: 0.4, followsSlide: true)
        effects.slide = 0.9
        effects.chorus.isOn = true

        #expect(audio.loopEffects.count == 2)
        #expect(audio.loopEffects.last == SoundEffects(chorus: effects.chorus, reverb: effects.reverb))
        #expect(audio.loopEffects.last?.reverb.mix == 0.3)
    }

    // MARK: – Key zones

    /// A finger in a zone switches the zone's effect on at the zone's value;
    /// in a plain zone, and once lifted, the effect is as set.
    @Test func aZoneSwitchesItsEffectOnAtItsValue() {
        let (effects, audio, _) = makeState()
        effects.chorus.rate = 0.2
        effects.zones = KeyZoneSettings(isOn: true, zones: [KeyZone(), KeyZone(effect: .chorus, value: 0.9)])
        effects.slide = 0.2
        effects.slide = 0.8
        effects.slide = 0.2
        effects.slide = 0.8
        effects.slide = nil

        let set = ChorusSettings(rate: 0.2)
        let held = ChorusSettings(isOn: true, amount: 0.9, rate: 0.2)
        #expect(audio.chorus == [set, set, held, set, held, set])
        #expect(effects.chorus == set)
    }

    /// One effect at a different value in every zone.
    @Test func zonesCanHoldOneEffectAtDifferentValues() {
        let (effects, audio, _) = makeState()
        effects.zones = KeyZoneSettings(isOn: true, zones: [
            KeyZone(effect: .reverb, value: 0.1),
            KeyZone(effect: .reverb, value: 0.5),
            KeyZone(effect: .reverb, value: 1),
        ])
        audio.reset()
        for slide: Float in [0.1, 0.5, 0.9] { effects.slide = slide }

        #expect(audio.reverb.map(\.mix) == [0.1, 0.5, 1])
        #expect(audio.reverb.allSatisfy { $0.isOn })
    }

    /// A different effect in every zone: each sounds only from its own.
    @Test func zonesCanMixEffects() {
        let (effects, audio, _) = makeState()
        effects.zones = KeyZoneSettings(isOn: true, zones: [
            KeyZone(effect: .filter, value: 0.3),
            KeyZone(effect: .chorus, value: 0.7),
        ])
        audio.reset()
        effects.slide = 0.1
        #expect(audio.filter == [FilterSettings(isOn: true, brightness: 0.3)])
        #expect(audio.chorus.isEmpty)

        effects.slide = 0.9
        #expect(audio.filter.last == FilterSettings())
        #expect(audio.chorus == [ChorusSettings(isOn: true, amount: 0.7)])
    }

    /// A zone holds its effect's control still; the slide still plays every
    /// other effect that follows it, and this one again outside the zone.
    @Test func aZoneHoldsItsEffectAgainstTheSlide() {
        let (effects, audio, _) = makeState()
        effects.filter = FilterSettings(isOn: true, brightness: 0.8)
        effects.reverb = ReverbSettings(isOn: true, followsSlide: true)
        effects.zones = KeyZoneSettings(isOn: true, zones: [KeyZone(), KeyZone(effect: .filter, value: 0.4)])
        audio.reset()
        for slide: Float in [0.6, 0.9, 0.2] { effects.slide = slide }

        #expect(audio.filter.map(\.brightness) == [0.4, 0.4, 0.2])
        #expect(audio.reverb.map(\.mix) == [0.6, 0.9, 0.2])
    }

    /// A finger resting on the line between two zones stays in the one it
    /// was in until it is clearly past the line.
    @Test func aFingerOnAZonesEdgeStaysInItsZone() {
        let zones = KeyZoneSettings(isOn: true, zones: [KeyZone(), KeyZone(), KeyZone(), KeyZone()])
        let hold = KeyZoneSettings.hold
        #expect([0, 0.24, 0.26, 0.5, 0.99, 1].map { zones.zone(at: $0, from: nil) } == [0, 0, 1, 2, 3, 3])
        #expect(zones.zone(at: 0.5 + hold / 2, from: 1) == 1)
        #expect(zones.zone(at: 0.25 - hold / 2, from: 1) == 1)
        #expect(zones.zone(at: 0.5 + hold * 2, from: 1) == 2)
        #expect(zones.zone(at: 0.25 - hold * 2, from: 1) == 0)
        #expect(zones.zone(at: nil, from: 1) == nil)
        #expect(KeyZoneSettings(isOn: false).zone(at: 0.5, from: nil) == nil)
    }

    @Test func aWaveringFingerDoesNotSwitchZones() {
        let (effects, audio, _) = makeState()
        effects.zones = KeyZoneSettings(isOn: true, zones: [KeyZone(), KeyZone(effect: .chorus)])
        effects.slide = 0.6
        audio.reset()
        for step in 0..<10 { effects.slide = step.isMultiple(of: 2) ? 0.49 : 0.51 }
        #expect(audio.chorus.isEmpty)
        #expect(effects.zone == 1)
    }

    /// Changing a zone under a held finger is heard at once.
    @Test func changingTheZoneUnderAFingerIsHeard() {
        let (effects, audio, _) = makeState()
        effects.slide = 0.9
        effects.zones.isOn = true
        effects.zones.zones[1] = KeyZone(effect: .reverb, value: 0.2)
        effects.zones.zones[1].value = 0.6
        effects.zones.isOn = false

        #expect(audio.reverb.map(\.isOn) == [true, true, false])
        #expect(audio.reverb.map(\.mix).prefix(2) == [0.2, 0.6])
    }

    @Test func theNumberOfZonesKeepsTheOnesThatStay() {
        var zones = KeyZoneSettings()
        #expect(zones.zones == [KeyZone(), KeyZone(effect: .arpeggiator)])
        zones.count = 4
        #expect(zones.zones == [KeyZone(), KeyZone(effect: .arpeggiator), KeyZone(), KeyZone()])
        zones.count = 1
        #expect(zones.count == 2)
        zones.count = 9
        #expect(zones.count == 4)
        #expect(zones.edges.isEmpty)
        zones.isOn = true
        #expect(zones.edges == [0.25, 0.5, 0.75])
    }

    /// A loop keeps the effects as set, not the ones a zone was holding on.
    @Test func loopsAreNotGivenWhatAZoneHolds() {
        let (effects, audio, _) = makeState()
        effects.zones = KeyZoneSettings(isOn: true, zones: [KeyZone(effect: .reverb, value: 1), KeyZone()])
        effects.slide = 0.1
        effects.chorus.rate = 0.9
        #expect(audio.loopEffects.last?.reverb == ReverbSettings())
    }

    @Test func onlyTheZonesSwitchIsLogged() {
        let (effects, _, logger) = makeState()
        effects.zones.isOn = true
        effects.zones.count = 3
        effects.slide = 0.9
        effects.zones.isOn = false
        let logged = logger.events.compactMap { if case let .key_zones_switched(isOn) = $0 { isOn } else { nil } }
        #expect(logged == [true, false])
        #expect(switches(logger).isEmpty)
    }

    /// Every cycle's own slide plays it, so a zone can name a cycle.
    @Test func everyCycleHasASlideThatPlaysIt() {
        for cycle in ArpeggioCycle.allCases {
            #expect(ArpeggioCycle.played(by: cycle.slide) == cycle)
        }
    }

    /// The slide plays the arpeggiator's cycle in steps: slow at the bottom
    /// of the key, fast at the top.
    @Test func theSlidePlaysTheArpeggiatorsCycleInSteps() {
        #expect([0, 0.2, 0.3, 0.6, 0.8, 1].map { ArpeggioCycle.played(by: $0) }
                == [.bar, .bar, .twoBeats, .beat, .halfBeat, .halfBeat])
        let settings = ArpeggiatorSettings(isOn: true, pattern: .down, cycle: .beat, followsSlide: true)
        #expect(settings.played(by: 0) == ArpeggiatorSettings(isOn: true, pattern: .down, cycle: .bar, followsSlide: true))
        #expect(settings.played(by: nil) == settings)
    }
}
