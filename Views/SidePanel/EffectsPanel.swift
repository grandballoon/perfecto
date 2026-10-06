import SwiftUI

/// The side panel's Effects page. Each effect is a card: its switch, and
/// under it, while the effect is on, its controls. The panel is narrow, so a
/// control sits below its name rather than beside it.
struct EffectsPanel: View {
    @Environment(PerformanceState.self) private var state

    var body: some View {
        @Bindable var effects = state.effects
        VStack(alignment: .leading, spacing: 24) {
            section("NOTES",
                    footnote: "Plays each chord one note at a time. One pass over the chord takes the cycle, however many notes it has. Works in Play and in the sequencer, and is sent over MIDI.") {
                card("Arpeggiator", isOn: $effects.arpeggiator.isOn) {
                    pickerControl("Pattern", selection: $effects.arpeggiator.pattern,
                                  options: ArpeggioPattern.allCases, label: \.label)
                    pickerControl("Cycle, in beats", selection: $effects.arpeggiator.cycle,
                                  options: ArpeggioCycle.allCases, label: \.label)
                    slideSwitch("cycle", isOn: $effects.arpeggiator.followsSlide)
                    tempoControl
                }
            }

            section("SOUND",
                    footnote: "Applied to everything Perfecto plays. A loop records the filter as it was played, and keeps the chorus and reverb that were set when it was closed. Brightness, amount and mix are sent over MIDI as CC 74, 93 and 91.") {
                card("Filter", isOn: $effects.filter.isOn) {
                    sliderControl("Brightness", value: $effects.filter.brightness)
                    slideSwitch("brightness", isOn: $effects.filter.followsSlide)
                }
                card("Chorus", isOn: $effects.chorus.isOn) {
                    sliderControl("Amount", value: $effects.chorus.amount)
                    slideSwitch("amount", isOn: $effects.chorus.followsSlide)
                    sliderControl("Rate", value: $effects.chorus.rate)
                }
                card("Reverb", isOn: $effects.reverb.isOn) {
                    sliderControl("Mix", value: $effects.reverb.mix)
                    slideSwitch("mix", isOn: $effects.reverb.followsSlide)
                    sliderControl("Size", value: $effects.reverb.size)
                }
            }

            footnote("Slide: where a finger is on a chord key plays every control whose slide switch is on, low at the bottom of the key and high at the top. Lifting the finger returns each to the value set here.")

            section("KEYS",
                    footnote: "Divides every chord key into zones, marked on the keys. A finger in a zone switches that zone's effect on at the value chosen for it, even if the effect is off above. Anywhere else on the key, and once the finger lifts, the effect is as set above. Zones can play different effects, or one effect at different values.") {
                card("Key zones", isOn: $effects.zones.isOn) {
                    pickerControl("Zones", selection: $effects.zones.count,
                                  options: Array(KeyZoneSettings.counts), label: \.description)
                    ForEach(effects.zones.zones.indices.reversed(), id: \.self) { index in
                        zoneControl(zoneName(index, of: effects.zones.count), zone: zoneBinding(index))
                    }
                }
            }
        }
    }

    // MARK: – Key zones

    /// Zones are listed as they sit on the key: the top one first.
    private func zoneName(_ index: Int, of count: Int) -> String {
        switch index {
        case 0:         return "Zone 1, bottom of the key"
        case count - 1: return "Zone \(count), top of the key"
        default:        return "Zone \(index + 1)"
        }
    }

    /// The zone at `index`. A row can outlive its zone for a moment when the
    /// number of zones goes down, so the binding answers for one that is gone.
    private func zoneBinding(_ index: Int) -> Binding<KeyZone> {
        let effects = state.effects
        return Binding(
            get: { effects.zones.zones.indices.contains(index) ? effects.zones.zones[index] : KeyZone() },
            set: { if effects.zones.zones.indices.contains(index) { effects.zones.zones[index] = $0 } }
        )
    }

    /// One zone: the effect it plays and, under it, the value it holds that
    /// effect's played control at.
    private func zoneControl(_ name: String, zone: Binding<KeyZone>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            controlName(name)
            Picker(name, selection: zone.effect) {
                Text("No effect").tag(EffectKind?.none)
                ForEach(EffectKind.allCases, id: \.self) { effect in
                    Text(effect.label).tag(EffectKind?.some(effect))
                }
            }
            .pickerStyle(.menu)
            .tint(.orange)
            .labelsHidden()
            switch zone.wrappedValue.effect {
            case .arpeggiator:
                pickerControl("Cycle, in beats", selection: zoneCycle(zone),
                              options: ArpeggioCycle.allCases, label: \.label)
            case .filter:
                sliderControl("Brightness", value: zone.value)
            case .chorus:
                sliderControl("Amount", value: zone.value)
            case .reverb:
                sliderControl("Mix", value: zone.value)
            case nil:
                EmptyView()
            }
        }
    }

    /// A zone's value as the arpeggiator cycle it plays.
    private func zoneCycle(_ zone: Binding<KeyZone>) -> Binding<ArpeggioCycle> {
        Binding(get: { .played(by: zone.wrappedValue.value) },
                set: { zone.wrappedValue.value = $0.slide })
    }

    // MARK: – Structure

    private func section<Cards: View>(_ title: String,
                                      footnote: String,
                                      @ViewBuilder cards: () -> Cards) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SidePanelSectionLabel(title)
            cards()
            self.footnote(footnote)
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Color(white: 0.3))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func card<Controls: View>(_ name: String,
                                      isOn: Binding<Bool>,
                                      @ViewBuilder controls: () -> Controls) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: isOn) {
                Text(name)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .tint(.orange)
            if isOn.wrappedValue {
                controls()
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.10)))
    }

    // MARK: – Controls

    private func pickerControl<Option: Hashable>(_ name: String,
                                                 selection: Binding<Option>,
                                                 options: [Option],
                                                 label: KeyPath<Option, String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            controlName(name)
            Picker(name, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option[keyPath: label]).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func sliderControl(_ name: String, value: Binding<Float>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            controlName(name)
            Slider(value: value, in: 0...1)
                .tint(.orange)
        }
    }

    /// The switch that lets the slide play `control`, placed under it.
    private func slideSwitch(_ control: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            controlName("Slide plays \(control)")
        }
        .tint(.orange)
    }

    private var tempoControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            controlName("Tempo")
            HStack(spacing: 0) {
                tempoStep("minus", by: -5, enabled: state.bpm > MusicalTime.tempoRange.lowerBound)
                Text("\(Int(state.bpm)) BPM")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                tempoStep("plus", by: 5, enabled: state.bpm < MusicalTime.tempoRange.upperBound)
            }
        }
    }

    private func tempoStep(_ symbol: String, by amount: Double, enabled: Bool) -> some View {
        Button { state.setBPM(state.bpm + amount) } label: {
            Image(systemName: "\(symbol).circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(enabled ? Color.orange : Color(white: 0.25))
        }
        .buttonStyle(.plain)
    }

    private func controlName(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Color(white: 0.6))
    }
}
