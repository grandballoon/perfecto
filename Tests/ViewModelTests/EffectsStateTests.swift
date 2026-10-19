import Foundation
import Testing
@testable import Perfecto

@Suite("EffectsState")
@MainActor
struct EffectsStateTests {

    /// Records the settings the audio layer was handed.
    private final class RecordingAudioEffects: EffectsControl {
        private(set) var chorus: [ChorusSettings] = []
        private(set) var reverb: [ReverbSettings] = []
        private(set) var vocoder: [VocoderSettings] = []
        func setChorus(_ settings: ChorusSettings) { chorus.append(settings) }
        func setReverb(_ settings: ReverbSettings) { reverb.append(settings) }
        private(set) var brightness: [Float] = []
        private(set) var delay: [DelaySettings] = []
        func setDelay(_ settings: DelaySettings) { delay.append(settings) }
        func setVocoder(_ settings: VocoderSettings) { vocoder.append(settings) }
        func setBrightness(_ played: Float) { brightness.append(played) }
        func reset() { chorus = []; reverb = []; vocoder = []; brightness = []; delay = [] }
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
        #expect(audio.chorus.isEmpty && audio.reverb.isEmpty && audio.vocoder.isEmpty)
    }

    @Test func soundEffectChangesReachTheAudioLayer() {
        let (effects, audio, _) = makeState()
        effects.chorus.isOn = true
        effects.vocoder.amount = 0.2

        #expect(audio.chorus == [ChorusSettings(isOn: true)])
        #expect(audio.vocoder == [VocoderSettings(isOn: false, amount: 0.2)])
        #expect(audio.reverb.isEmpty)
    }

    @Test func settingTheSameValueAgainSendsNothing() {
        let (effects, audio, _) = makeState()
        effects.reverb.isOn = true
        effects.reverb.isOn = true
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
        effects.vocoder.isOn = true
        effects.vocoder.amount = 0.1
        effects.slide = 0.2
        effects.slide = nil
        effects.reverb.isOn = true
        effects.reverb.isOn = false
        #expect(switches(logger) == ["arpeggiator on", "vocoder on", "reverb on", "reverb off"])
    }

    // MARK: – The slide

    /// While a key is held the slide plays the control of an effect that
    /// follows it; lifting returns to the set one.
    @Test func theSlidePlaysAnEffectsControlWhileAKeyIsHeld() {
        let (effects, audio, _) = makeState()
        effects.vocoder = VocoderSettings(isOn: true, amount: 0.8, followsSlide: true)
        effects.slide = 0.25
        effects.slide = 0.5
        effects.slide = nil

        #expect(audio.vocoder.map(\.amount) == [0.8, 0.25, 0.5, 0.8])
        #expect(audio.vocoder.allSatisfy { $0.isOn })
    }

    /// With its switch on, the slide plays how bright the notes are, and
    /// lifting gives the whole sound back.
    @Test func theSlidePlaysTheBrightnessWhileItsSwitchIsOn() {
        let (effects, audio, logger) = makeState()
        effects.slide = 0.25
        #expect(audio.brightness.isEmpty)
        #expect(effects.asPlayed.brightness == 1)

        effects.slidePlaysBrightness = true
        effects.slide = 0.5
        #expect(effects.asPlayed.brightness == 0.5)
        effects.slide = nil
        #expect(audio.brightness == [0.25, 0.5, 1])
        #expect(effects.asPlayed.brightness == 1)
        #expect(effects.asSet.brightness == 1)

        effects.slide = 0.1
        effects.slidePlaysBrightness = false
        #expect(audio.brightness.last == 1)
        let logged = logger.events.compactMap {
            if case let .slide_brightness_switched(isOn) = $0 { isOn } else { nil }
        }
        #expect(logged == [true, false])
    }

    /// With its switch on, the slide rolls the chord: not at all in the
    /// middle of the key, up above it and down below, and a finger resting
    /// on the edge between two steps stays in the one it was in.
    @Test func theSlideRollsTheChordWhileItsSwitchIsOn() {
        let (effects, _, logger) = makeState()
        effects.hold(.I, at: 1)
        #expect(effects.slideRoll == 0)

        effects.slidePlaysInversion = true
        #expect(effects.slideRoll == InversionSlide.reach)
        effects.hold(.I, at: 0.5)
        #expect(effects.slideRoll == 0)
        effects.hold(.I, at: 0)
        #expect(effects.slideRoll == -InversionSlide.reach)

        // The middle band ends 5/9 of the way up the key.
        let edge: Float = 5.0 / 9
        effects.hold(.I, at: 0.5)
        effects.hold(.I, at: edge + SlideBands.hold / 2)
        #expect(effects.slideRoll == 0)
        effects.hold(.I, at: edge + SlideBands.hold * 2)
        #expect(effects.slideRoll == 1)
        effects.hold(.I, at: edge - SlideBands.hold / 2)
        #expect(effects.slideRoll == 1)

        // A key with no place on it, or none held, is not rolled.
        effects.hold(.I, at: nil)
        #expect(effects.slideRoll == 0)
        effects.hold(nil, at: nil)
        #expect(effects.slideRoll == 0)

        effects.slidePlaysInversion = false
        let logged = logger.events.compactMap {
            if case let .slide_inversion_switched(isOn) = $0 { isOn } else { nil }
        }
        #expect(logged == [true, false])
    }

    /// A key with no place on it (the computer keyboard) is fully bright.
    @Test func aKeyWithNoPlaceIsFullyBright() {
        let (effects, audio, _) = makeState()
        effects.slidePlaysBrightness = true
        effects.hold(.I, at: nil)
        #expect(audio.brightness.allSatisfy { $0 == 1 })
        #expect(effects.asPlayed.brightness == 1)
    }

    @Test func theSlideDoesNothingWhileTheEffectIsOff() {
        let (effects, audio, _) = makeState()
        effects.vocoder.followsSlide = true
        audio.reset()
        effects.slide = 0.25
        effects.slide = 0.5
        #expect(audio.vocoder.isEmpty)
    }

    /// Switched on under a held key, an effect starts where the finger is.
    @Test func switchingAnEffectOnPicksUpTheSlide() {
        let (effects, audio, _) = makeState()
        effects.vocoder.followsSlide = true
        effects.slide = 0.25
        effects.vocoder.isOn = true
        #expect(audio.vocoder.last == VocoderSettings(isOn: true, amount: 0.25, followsSlide: true))
    }

    @Test func switchingAnEffectsSlideOnPicksUpTheSlide() {
        let (effects, audio, _) = makeState()
        effects.vocoder.isOn = true
        effects.slide = 0.9
        effects.vocoder.followsSlide = true
        #expect(audio.vocoder.last?.amount == 0.9)
    }

    /// The set amount is unchanged by playing.
    @Test func theSlideLeavesTheSetValueAlone() {
        let (effects, _, _) = makeState()
        effects.vocoder = VocoderSettings(isOn: true, amount: 0.8, followsSlide: true)
        effects.slide = 0.1
        #expect(effects.vocoder.amount == 0.8)
        #expect(effects.vocoder.played(by: effects.slide).amount == 0.1)
    }

    @Test func aPlayedEffectReachesItsListenerToo() {
        let listener = RecordingAudioEffects()
        let arpeggiator = Arpeggiator(downstream: RecordingSink(), clock: ManualClock())
        let effects = EffectsState(arpeggiator: arpeggiator, effectsListener: listener)
        effects.vocoder = VocoderSettings(isOn: true, followsSlide: true)
        effects.slide = 0.3
        #expect(listener.vocoder.map(\.amount) == [1, 0.3])
    }

    /// An effect follows the slide only when told to, and the chorus and
    /// the reverb have nothing for it to play.
    @Test func anEffectThatDoesNotFollowTheSlideIsLeftAlone() {
        let (effects, audio, _) = makeState()
        effects.vocoder = VocoderSettings(isOn: true, amount: 0.8)
        effects.chorus.isOn = true
        effects.reverb.isOn = true
        effects.slide = 0.1

        #expect(audio.vocoder.map(\.amount) == [0.8])
        #expect(audio.chorus.count == 1 && audio.reverb.count == 1)
        #expect(!VocoderSettings().followsSlide && !ArpeggiatorSettings().followsSlide)
        #expect(!ChorusSettings(isOn: true).isPlayed && !ReverbSettings(isOn: true).isPlayed)
    }

    /// The effects can be read both ways: as set, which a note of the
    /// timeline follows, and as played, which a loop being recorded keeps.
    @Test func theEffectsCanBeReadAsSetAndAsPlayed() {
        let (effects, _, _) = makeState()
        effects.vocoder = VocoderSettings(isOn: true, amount: 0.3, followsSlide: true)
        effects.slide = 0.9

        #expect(effects.asSet.vocoder.amount == 0.3)
        #expect(effects.asPlayed.vocoder.amount == 0.9)
        #expect(effects.asPlayed.chorus == effects.asSet.chorus)
    }

    /// Whatever follows the effects is told when they change: as set only
    /// by a setting, as played by the slide too.
    @Test func changesAreToldToWhoeverFollowsTheEffects() {
        let (effects, _, _) = makeState()
        var set = 0, played = 0
        effects.onSetChange = { set += 1 }
        effects.onPlayedChange = { played += 1 }

        effects.reverb.isOn = true
        #expect(set == 1 && played == 1)
        effects.slide = 0.4
        #expect(set == 1 && played == 2)
        effects.reverb.isOn = true                   // no change
        #expect(set == 1 && played == 2)
    }

    // MARK: – Key zones

    /// A finger in a zone switches the zone's effect on; in a plain zone,
    /// and once lifted, the effect is as set.
    @Test func aZoneSwitchesItsEffectOn() {
        let (effects, audio, _) = makeState()
        effects.zones = KeyZoneSettings(isOn: true, zones: [KeyZone(), KeyZone(effect: .chorus)])
        effects.slide = 0.2
        effects.slide = 0.8
        effects.slide = 0.2
        effects.slide = 0.8
        effects.slide = nil

        #expect(audio.chorus.map(\.isOn) == [false, true, false, true, false])
        #expect(effects.chorus == ChorusSettings())
    }

    /// One effect at a different value in every zone.
    @Test func zonesCanHoldOneEffectAtDifferentValues() {
        let (effects, audio, _) = makeState()
        effects.zones = KeyZoneSettings(isOn: true, zones: [
            KeyZone(effect: .vocoder, value: 0.1),
            KeyZone(effect: .vocoder, value: 0.5),
            KeyZone(effect: .vocoder, value: 1),
        ])
        audio.reset()
        for slide: Float in [0.1, 0.5, 0.9] { effects.slide = slide }

        #expect(audio.vocoder.map(\.amount) == [0.1, 0.5, 1])
        #expect(audio.vocoder.allSatisfy { $0.isOn })
    }

    /// A different effect in every zone: each sounds only from its own.
    @Test func zonesCanMixEffects() {
        let (effects, audio, _) = makeState()
        effects.zones = KeyZoneSettings(isOn: true, zones: [
            KeyZone(effect: .vocoder, value: 0.3),
            KeyZone(effect: .chorus),
        ])
        audio.reset()
        effects.slide = 0.1
        #expect(audio.vocoder == [VocoderSettings(isOn: true, amount: 0.3)])
        #expect(audio.chorus.isEmpty)

        effects.slide = 0.9
        #expect(audio.vocoder.last == VocoderSettings())
        #expect(audio.chorus == [ChorusSettings(isOn: true)])
    }

    /// The two arpeggios are two effects to a zone: each zone says which
    /// it plays, and at what cycle, whatever is set.
    @Test func aZoneSaysWhichArpeggioItPlays() {
        let (effects, _, _) = makeState()
        effects.arpeggiator.cycle = .beat
        effects.zones = KeyZoneSettings(isOn: true, zones: [
            KeyZone(effect: .arpeggio(.down), value: ArpeggioCycle.bar.slide),
            KeyZone(effect: .arpeggio(.up), value: ArpeggioCycle.halfBeat.slide),
            KeyZone(),
        ])
        effects.slide = 0.1
        #expect(effects.asPlayed.arpeggiator == ArpeggiatorSettings(isOn: true, pattern: .down, cycle: .bar))
        effects.slide = 0.5
        #expect(effects.asPlayed.arpeggiator == ArpeggiatorSettings(isOn: true, pattern: .up, cycle: .halfBeat))
        effects.slide = 0.9
        #expect(effects.asPlayed.arpeggiator == ArpeggiatorSettings(cycle: .beat))
        #expect(effects.asSet.arpeggiator == ArpeggiatorSettings(cycle: .beat))
    }

    /// A zone holds its effect's control still; the slide plays it again
    /// outside the zone.
    @Test func aZoneHoldsItsEffectAgainstTheSlide() {
        let (effects, audio, _) = makeState()
        effects.vocoder = VocoderSettings(isOn: true, amount: 0.8, followsSlide: true)
        effects.zones = KeyZoneSettings(isOn: true, zones: [KeyZone(), KeyZone(effect: .vocoder, value: 0.4)])
        audio.reset()
        for slide: Float in [0.6, 0.9, 0.2] { effects.slide = slide }

        #expect(audio.vocoder.map(\.amount) == [0.4, 0.4, 0.2])
    }

    /// A finger resting on the line between two zones stays in the one it
    /// was in until it is clearly past the line.
    @Test func aFingerOnAZonesEdgeStaysInItsZone() {
        let zones = KeyZoneSettings(isOn: true, zones: [KeyZone(), KeyZone(), KeyZone(), KeyZone()])
        let hold = SlideBands.hold
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
        effects.zones.zones[1] = KeyZone(effect: .vocoder, value: 0.2)
        effects.zones.zones[1].value = 0.6
        effects.zones.isOn = false

        #expect(audio.vocoder.map(\.isOn) == [true, true, false])
        #expect(audio.vocoder.map(\.amount).prefix(2) == [0.2, 0.6])
    }

    @Test func theNumberOfZonesKeepsTheOnesThatStay() {
        var zones = KeyZoneSettings()
        #expect(zones.zones == [KeyZone(), KeyZone(effect: .arpeggio(.up))])
        zones.count = 4
        #expect(zones.zones == [KeyZone(), KeyZone(effect: .arpeggio(.up)), KeyZone(), KeyZone()])
        zones.count = 0
        #expect(zones.count == 1)
        zones.count = 9
        #expect(zones.count == 4)
        #expect(zones.edges.isEmpty)
        zones.isOn = true
        #expect(zones.edges == [0.25, 0.5, 0.75])
    }

    /// What a zone holds on is how the effects are played, not how they are set.
    @Test func whatAZoneHoldsIsPlayedNotSet() {
        let (effects, _, _) = makeState()
        effects.zones = KeyZoneSettings(isOn: true, zones: [KeyZone(effect: .reverb), KeyZone()])
        effects.slide = 0.1
        #expect(effects.asSet.reverb == ReverbSettings())
        #expect(effects.asPlayed.reverb.isOn)
        // A zone's effect has no field on the play screen: it is not set.
        #expect(effects.slotChoices == [nil])
    }

    // MARK: – A key's own zones

    /// Reverb on the whole of one key, and on no other.
    @Test func anEffectCanBeOnOneKeyAlone() {
        let (effects, audio, _) = makeState()
        effects.zones = KeyZoneSettings(isOn: true, zones: [KeyZone()])
        effects.keyZones[.IV] = KeyZoneSettings(isOn: true, zones: [KeyZone(effect: .reverb)])

        effects.hold(.I, at: 0.5)
        #expect(!effects.asPlayed.reverb.isOn)
        effects.hold(.IV, at: 0.5)
        #expect(effects.asPlayed.reverb.isOn)
        #expect(audio.reverb.last?.isOn == true)
        effects.hold(.I, at: 0.5)
        #expect(audio.reverb.last?.isOn == false)
        #expect(effects.asSet.reverb == ReverbSettings())
    }

    /// A key played with no place on it (the computer keyboard) is in its
    /// whole-key zone, and in none of several.
    @Test func aKeyWithNoPlaceOnItPlaysItsWholeKeyZone() {
        let (effects, _, _) = makeState()
        effects.zones = KeyZoneSettings(isOn: true, zones: [KeyZone()])
        effects.keyZones[.IV] = KeyZoneSettings(isOn: true, zones: [KeyZone(effect: .chorus)])
        effects.keyZones[.V] = KeyZoneSettings(isOn: true, zones: [KeyZone(effect: .chorus), KeyZone()])
        effects.hold(.IV, at: nil)
        #expect(effects.asPlayed.chorus.isOn)
        effects.hold(.V, at: nil)
        #expect(!effects.asPlayed.chorus.isOn)
        effects.hold(nil, at: nil)
        #expect(effects.zone == nil)
    }

    /// One part of one key: its own zones take the place of every key's.
    @Test func aKeysOwnZonesTakeThePlaceOfEveryKeys() {
        let (effects, _, _) = makeState()
        effects.zones = KeyZoneSettings(isOn: true, zones: [KeyZone(), KeyZone(effect: .chorus)])
        effects.keyZones[.ii] = KeyZoneSettings(isOn: true, zones: [KeyZone(), KeyZone(), KeyZone(effect: .vocoder, value: 0.3)])
        #expect(effects.zones(of: .ii).edges.count == 2)
        #expect(effects.zones(of: .iii).edges == [0.5])

        effects.hold(.ii, at: 0.6)
        #expect(!effects.asPlayed.chorus.isOn && !effects.asPlayed.vocoder.isOn)
        effects.hold(.ii, at: 0.9)
        #expect(effects.asPlayed.vocoder.isOn && effects.asPlayed.vocoder.amount == 0.3)
        effects.hold(.iii, at: 0.9)
        #expect(effects.asPlayed.chorus.isOn && !effects.asPlayed.vocoder.isOn)

        // Switched off, the key is divided as every key is.
        effects.keyZones[.ii]?.isOn = false
        effects.hold(.ii, at: 0.9)
        #expect(effects.asPlayed.chorus.isOn)
    }

    /// The key zones' switch is the keys' own zones' too.
    @Test func aKeysOwnZonesAreOffWhileTheKeyZonesAre() {
        let (effects, audio, _) = makeState()
        effects.keyZones[.IV] = KeyZoneSettings(isOn: true, zones: [KeyZone(effect: .vocoder), KeyZone()])
        effects.hold(.IV, at: 0.2)
        #expect(!effects.asPlayed.vocoder.isOn)
        #expect(!effects.hearsTheMic && !effects.isAnyOn)
        #expect(effects.zones(of: .IV).edges.isEmpty)

        effects.zones = KeyZoneSettings(isOn: true, zones: [KeyZone()])
        #expect(audio.vocoder.last?.isOn == true)
        #expect(effects.hearsTheMic)
        #expect(effects.zones(of: .IV).edges == [0.5])
        effects.zones.isOn = false
        #expect(audio.vocoder.last?.isOn == false)
        #expect(!effects.hearsTheMic)
    }

    @Test func changingAKeysOwnZoneUnderAFingerIsHeard() {
        let (effects, audio, logger) = makeState()
        effects.zones = KeyZoneSettings(isOn: true, zones: [KeyZone()])
        effects.hold(.vi, at: 0.5)
        effects.keyZones[.vi] = KeyZoneSettings(isOn: true, zones: [KeyZone(effect: .vocoder, value: 0.2)])
        effects.keyZones[.vi]?.zones[0].value = 0.6
        #expect(audio.vocoder.map(\.amount).suffix(2) == [0.2, 0.6])
        effects.keyZones[.vi] = nil
        #expect(audio.vocoder.last?.isOn == false)
        let logged = logger.events.compactMap {
            if case let .key_own_zones_switched(degree, isOn) = $0 { "\(degree) \(isOn)" } else { nil }
        }
        #expect(logged == ["\(Degree.vi.rawValue) true", "\(Degree.vi.rawValue) false"])
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

    // MARK: – The arpeggiator

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

    /// There are two arpeggios, up and down. One saved while there were
    /// others goes up.
    @Test func anArpeggioSavedInAPatternThatIsGoneGoesUp() throws {
        #expect(ArpeggioPattern.allCases == [.up, .down])
        let saved = Data(#"{"isOn":true,"pattern":"upDown","cycle":"bar","followsSlide":false}"#.utf8)
        let loaded = try JSONDecoder().decode(ArpeggiatorSettings.self, from: saved)
        #expect(loaded == ArpeggiatorSettings(isOn: true, pattern: .up, cycle: .bar))
        let down = Data(#"{"isOn":true,"pattern":"down","cycle":"bar","followsSlide":false}"#.utf8)
        #expect(try JSONDecoder().decode(ArpeggiatorSettings.self, from: down).pattern == .down)
    }

    // MARK: – The vocoder

    @Test func theVocoderIsPassedOnAndLogged() {
        let (effects, audio, logger) = makeState()
        effects.vocoder.isOn = true
        #expect(audio.vocoder.last == VocoderSettings(isOn: true))
        #expect(switches(logger) == ["vocoder on"])
        #expect(effects.asSet.vocoder.isOn)
        #expect(effects.isAnyOn)
    }

    @Test func theMicIsWantedWhileTheVocoderOrAZoneOfItIsOn() {
        let (effects, _, _) = makeState()
        #expect(!effects.hearsTheMic)
        effects.vocoder.isOn = true
        #expect(effects.hearsTheMic)
        effects.vocoder.isOn = false

        var changes = 0
        effects.onSetChange = { changes += 1 }
        effects.zones.zones[0].effect = .vocoder
        #expect(!effects.hearsTheMic)
        effects.zones.isOn = true
        #expect(effects.hearsTheMic)
        // Whoever opens the mic is told each time.
        #expect(changes == 2)
    }

    // MARK: – Effects saved earlier

    @Test func effectsSavedBeforeTheVocoderHaveNone() throws {
        var saved = try #require(try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(NoteEffects(chorus: ChorusSettings(isOn: true)))) as? [String: Any])
        saved["vocoder"] = nil
        let loaded = try JSONDecoder().decode(NoteEffects.self, from: JSONSerialization.data(withJSONObject: saved))
        #expect(loaded == NoteEffects(chorus: ChorusSettings(isOn: true)))
    }

    /// Effects saved before there was a delay have it off, and a delay
    /// that was on is kept.
    @Test func theDelayIsSavedAndIsOffWhereNoneWas() throws {
        let echoing = NoteEffects(delay: DelaySettings(isOn: true))
        let data = try JSONEncoder().encode(echoing)
        #expect(try JSONDecoder().decode(NoteEffects.self, from: data) == echoing)
        var saved = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        saved["delay"] = nil
        let loaded = try JSONDecoder().decode(NoteEffects.self, from: JSONSerialization.data(withJSONObject: saved))
        #expect(loaded == NoteEffects())
    }

    /// The delay is an effect like the others: switched, it is passed on
    /// and logged and has a field on the play screen; a key zone holds it
    /// on while the finger is there.
    @Test func theDelayIsSwitchedLikeTheOtherEffects() {
        let (effects, audio, logger) = makeState()
        effects.delay.isOn = true
        #expect(audio.delay.map(\.isOn) == [true])
        #expect(effects.slotChoices == [.delay])
        #expect(effects.asPlayed.delay.isOn && effects.asSet.hasAnyOn)
        effects.setSlot(0, to: nil)
        #expect(!effects.delay.isOn)
        #expect(switches(logger) == ["delay on", "delay off"])

        effects.zones.zones = [KeyZone(), KeyZone(effect: .delay)]
        effects.zones.isOn = true
        audio.reset()
        effects.hold(.I, at: 0.9)
        effects.hold(.I, at: 0.1)
        #expect(audio.delay.map(\.isOn) == [true, false])
    }

    /// Effects saved before notes had a brightness are fully bright, and
    /// a brightness that was played is kept.
    @Test func brightnessIsSavedAndIsFullWhereNoneWas() throws {
        let played = NoteEffects(brightness: 0.3)
        let data = try JSONEncoder().encode(played)
        #expect(try JSONDecoder().decode(NoteEffects.self, from: data) == played)
        var saved = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        saved["brightness"] = nil
        let loaded = try JSONDecoder().decode(NoteEffects.self, from: JSONSerialization.data(withJSONObject: saved))
        #expect(loaded.brightness == 1)
    }

    /// Effects saved while there was a filter, and while the chorus and
    /// the reverb had amounts to set, are read as the switches they had.
    @Test func effectsSavedWithAFilterAndAmountsKeepTheirSwitches() throws {
        let saved = Data(#"""
            {"arpeggiator":{"isOn":false,"pattern":"random","cycle":"beat","followsSlide":false},
             "filter":{"isOn":true,"brightness":0.4,"followsSlide":true},
             "chorus":{"isOn":true,"amount":0.9,"rate":0.1,"followsSlide":true},
             "reverb":{"isOn":false,"mix":0.8,"size":0.9,"followsSlide":false},
             "vocoder":{"isOn":true,"amount":0.5,"followsSlide":false}}
            """#.utf8)
        let loaded = try JSONDecoder().decode(NoteEffects.self, from: saved)
        #expect(loaded == NoteEffects(chorus: ChorusSettings(isOn: true),
                                      vocoder: VocoderSettings(isOn: true, amount: 0.5)))
    }
}
