import Testing
@testable import Perfecto

/// The play screen's effect fields: one to start with, one effect to a
/// field, and the same switches as the Effects page.
@Suite("EffectSlots")
@MainActor
struct EffectSlotsTests {

    private func makeState() -> EffectsState {
        EffectsState(arpeggiator: Arpeggiator(downstream: RecordingSink(), clock: ManualClock()))
    }

    @Test func thereIsOneEmptyFieldToStartWith() {
        let effects = makeState()
        #expect(effects.slotChoices == [nil])
        #expect(!effects.slots.canAdd)                // nothing to add to while it is empty
        #expect(effects.slots.choices(for: 0) == [nil, .arpeggio(.up), .arpeggio(.down), .chorus, .reverb, .delay, .vocoder])
    }

    /// A field switches its effect on, and the one it had off.
    @Test func aFieldSwitchesItsEffect() {
        let effects = makeState()
        effects.setSlot(0, to: .chorus)
        #expect(effects.chorus.isOn)
        effects.setSlot(0, to: .reverb)
        #expect(!effects.chorus.isOn && effects.reverb.isOn)
        #expect(effects.slotChoices == [.reverb])
        effects.setSlot(0, to: nil)
        #expect(!effects.asSet.hasAnyOn)
        #expect(effects.slotChoices == [nil])
    }

    /// The two arpeggios are two choices of the one arpeggiator.
    @Test func theArpeggiosAreUpAndDown() {
        let effects = makeState()
        effects.setSlot(0, to: .arpeggio(.up))
        #expect(effects.arpeggiator == ArpeggiatorSettings(isOn: true, pattern: .up))
        effects.setSlot(0, to: .arpeggio(.down))
        #expect(effects.arpeggiator == ArpeggiatorSettings(isOn: true, pattern: .down))
        #expect(effects.slotChoices == [.arpeggio(.down)])
    }

    /// A field is added for one more effect, and offers only the effects
    /// no other field has.
    @Test func aFieldIsAddedForAnotherEffect() {
        let effects = makeState()
        effects.setSlot(0, to: .arpeggio(.up))
        #expect(effects.slots.canAdd)
        effects.addSlot()
        #expect(effects.slotChoices == [.arpeggio(.up), nil])
        #expect(!effects.slots.canAdd)
        #expect(effects.slots.choices(for: 1) == [nil, .chorus, .reverb, .delay, .vocoder])
        #expect(effects.slots.choices(for: 0) == [nil, .arpeggio(.up), .arpeggio(.down), .chorus, .reverb, .delay, .vocoder])

        effects.setSlot(1, to: .arpeggio(.down))      // the other field's effect: not taken
        #expect(effects.slotChoices == [.arpeggio(.up), nil])
        effects.setSlot(1, to: .reverb)
        #expect(effects.arpeggiator.isOn && effects.reverb.isOn)
        #expect(effects.slotChoices == [.arpeggio(.up), .reverb])
    }

    @Test func thereIsAFieldForEachEffectAtMost() {
        let effects = makeState()
        for (slot, choice) in [EffectChoice.arpeggio(.up), .chorus, .reverb, .delay, .vocoder].enumerated() {
            if slot > 0 { effects.addSlot() }
            effects.setSlot(slot, to: choice)
        }
        #expect(effects.slotChoices == [.arpeggio(.up), .chorus, .reverb, .delay, .vocoder])
        #expect(!effects.slots.canAdd)
        effects.addSlot()
        #expect(effects.slotChoices.count == 5)
    }

    /// A field stays where it is while it is being changed, also through
    /// off, and the row closes up once the finger lifts.
    @Test func aFieldLeftOffGoesWhenTheFingerLifts() {
        let effects = makeState()
        effects.setSlot(0, to: .chorus)
        effects.addSlot()
        effects.setSlot(1, to: .reverb)

        effects.setSlot(0, to: nil)
        #expect(effects.slotChoices == [nil, .reverb])
        effects.setSlot(0, to: .vocoder)
        #expect(effects.slotChoices == [.vocoder, .reverb])
        effects.setSlot(0, to: nil)
        effects.settleSlots()
        #expect(effects.slotChoices == [.reverb])
        #expect(!effects.chorus.isOn && !effects.vocoder.isOn && effects.reverb.isOn)

        effects.setSlot(0, to: nil)
        effects.settleSlots()
        #expect(effects.slotChoices == [nil])         // the last field stays
    }

    /// An effect switched somewhere else (the Effects page) has its field.
    @Test func theFieldsFollowTheEffectsHoweverTheyAreSwitched() {
        let effects = makeState()
        effects.reverb.isOn = true
        #expect(effects.slotChoices == [.reverb])
        effects.arpeggiator = ArpeggiatorSettings(isOn: true, pattern: .down)
        #expect(effects.slotChoices == [.reverb, .arpeggio(.down)])
        effects.arpeggiator.pattern = .up
        #expect(effects.slotChoices == [.reverb, .arpeggio(.up)])
        effects.reverb.isOn = false
        #expect(effects.slotChoices == [.arpeggio(.up)])
        effects.arpeggiator.isOn = false
        #expect(effects.slotChoices == [nil])

        effects.asSet = NoteEffects(chorus: ChorusSettings(isOn: true), vocoder: VocoderSettings(isOn: true))
        #expect(effects.slotChoices == [.chorus, .vocoder])
    }

    /// An effect switched on elsewhere takes a field that was added and
    /// left empty.
    @Test func anEffectSwitchedOnTakesAnEmptyField() {
        let effects = makeState()
        effects.setSlot(0, to: .chorus)
        effects.addSlot()
        effects.vocoder.isOn = true
        #expect(effects.slotChoices == [.chorus, .vocoder])
    }
}
