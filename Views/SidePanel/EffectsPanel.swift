import SwiftUI

/// The side panel's Effects page. Each effect is a card: its switch, and
/// under it, while the effect is on, its controls. The panel is narrow, so a
/// control sits below its name rather than beside it.
struct EffectsPanel: View {
    @Environment(PerformanceState.self) private var state

    /// The loop whose effects the cards show, chosen at the top of the
    /// page; nil for the keys'.
    @State private var chosenLoop: Layer.ID?

    /// The loop being edited, while it is still there.
    private var loop: Layer.ID? {
        state.quickLoopState.loops.contains { $0.id == chosenLoop } ? chosenLoop : nil
    }

    var body: some View {
        @Bindable var effects = state.effects
        VStack(alignment: .leading, spacing: 24) {
            if !state.quickLoopState.loops.isEmpty { targetPicker }

            section("NOTES",
                    footnote: "Plays each chord one note at a time. One pass over the chord takes the cycle, however many notes it has. Works in Play and in the sequencer, and is sent over MIDI.") {
                card("Arpeggiator", isOn: control(\.arpeggiator.isOn)) {
                    pickerControl("Pattern", selection: control(\.arpeggiator.pattern),
                                  options: ArpeggioPattern.allCases, label: \.label)
                    pickerControl("Cycle, in beats", selection: control(\.arpeggiator.cycle),
                                  options: ArpeggioCycle.allCases, label: \.label)
                    if loop == nil { slideSwitch("cycle", isOn: $effects.arpeggiator.followsSlide) }
                    tempoControl
                }
            }

            section("SOUND",
                    footnote: loop == nil
                        ? "Applied to what the keys play. A loop keeps the effects it was recorded with, the filter as it was played; choose the loop above to change them. Brightness, amount and mix are sent over MIDI as CC 74, 93 and 91."
                        : "Applied to this loop alone, whatever is set for the keys. The chorus's rate and the reverb's size are shared by everything that is sounding: they follow the note played last that has the effect on.") {
                card("Filter", isOn: control(\.filter.isOn)) {
                    sliderControl("Brightness", value: control(\.filter.brightness))
                    if loop == nil { slideSwitch("brightness", isOn: $effects.filter.followsSlide) }
                }
                card("Chorus", isOn: control(\.chorus.isOn)) {
                    sliderControl("Amount", value: control(\.chorus.amount))
                    if loop == nil { slideSwitch("amount", isOn: $effects.chorus.followsSlide) }
                    sliderControl("Rate", value: control(\.chorus.rate))
                }
                card("Reverb", isOn: control(\.reverb.isOn)) {
                    sliderControl("Mix", value: control(\.reverb.mix))
                    if loop == nil { slideSwitch("mix", isOn: $effects.reverb.followsSlide) }
                    sliderControl("Size", value: control(\.reverb.size))
                }
            }

            section("VOICE",
                    footnote: loop == nil
                        ? "Your voice shapes the notes: hold a chord and speak or sing into the phone, and the chord says the words. It uses the microphone while it is on. Headphones give the clearest result; on the speaker the phone has to cancel its own sound, which dulls it. Bright sounds, such as Saw Lead and Strings, speak most clearly."
                        : "How much of this loop your voice shapes. The microphone is open only while the vocoder is on for the keys; while it is off, the loop is heard whole.") {
                card("Vocoder", isOn: control(\.vocoder.isOn)) {
                    sliderControl("Amount", value: control(\.vocoder.amount))
                    if loop == nil { slideSwitch("amount", isOn: $effects.vocoder.followsSlide) }
                }
                if state.micAccess.isRefused { micRefusal }
            }

            if loop == nil {
                footnote("Slide: where a finger is on a chord key plays every control whose slide switch is on, low at the bottom of the key and high at the top. Lifting the finger returns each to the value set here.")

                section("KEYS",
                        footnote: "Divides every chord key into zones, marked on the keys. A finger in a zone switches that zone's effect on at the value chosen for it, even if the effect is off above. Anywhere else on the key, and once the finger lifts, the effect is as set above. Zones can play different effects, or one effect at different values. A zone can also have a key and an octave of its own: a chord played from it is in them, and a finger sliding into it changes the chord it is holding.") {
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
    }

    // MARK: – Whose effects

    /// Chooses whose effects the cards below set: the keys', or one loop's.
    /// Each loop has its own, and nothing set for the keys reaches them.
    private var targetPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SidePanelSectionLabel("EFFECTS OF")
            Picker("Effects of", selection: Binding(get: { loop }, set: { chosenLoop = $0 })) {
                Text("The keys").tag(Layer.ID?.none)
                ForEach(Array(state.quickLoopState.loops.enumerated()), id: \.element.id) { index, entry in
                    Text("Loop \(index + 1)").tag(Layer.ID?.some(entry.id))
                }
            }
            .pickerStyle(.menu)
            .tint(.orange)
            .labelsHidden()
        }
    }

    /// One setting of the effects being shown: the keys' as set, or the
    /// chosen loop's own. Setting a loop's changes every note of it and
    /// nothing of the keys'.
    private func control<Value>(_ setting: WritableKeyPath<NoteEffects, Value>) -> Binding<Value> {
        let (effects, sequencer) = (state.effects, state.sequencerState)
        guard let loop else {
            return Binding(get: { effects.asSet[keyPath: setting] },
                           set: { effects.asSet[keyPath: setting] = $0 })
        }
        return Binding(
            get: { (sequencer.effects(ofLayer: loop) ?? effects.asSet)[keyPath: setting] },
            set: { value in
                sequencer.editEffects(ofLayer: loop, following: effects.asSet) { $0[keyPath: setting] = value }
            })
    }

    /// Shown when the vocoder was asked for and the app may not use the mic.
    private var micRefusal: some View {
        VStack(alignment: .leading, spacing: 6) {
            footnote("Perfecto is not allowed to use the microphone, so the vocoder has nothing to hear.")
            if let settings = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: settings)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.orange)
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
    /// effect's played control at; then the key and the octave its chords
    /// are in.
    private func zoneControl(_ name: String, zone: Binding<KeyZone>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            menuControl(name, selection: zone.effect, unset: "No effect",
                        options: EffectKind.allCases, label: \.label)
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
            case .vocoder:
                sliderControl("Amount", value: zone.value)
            case nil:
                EmptyView()
            }
            zoneKeyControl(zone.key)
            menuControl("Octave", selection: zone.octave, unset: "As chosen",
                        options: Array(PerformanceState.octaves), label: \.description)
        }
    }

    /// A zone's key: its root, and its scale once it has a root of its own.
    /// A root chosen for a zone that followed the key starts in the scale
    /// that is chosen.
    private func zoneKeyControl(_ key: Binding<Key?>) -> some View {
        let chosen = state.key
        let root = Binding<PitchClass?>(
            get: { key.wrappedValue?.root },
            set: { root in
                key.wrappedValue = root.map { Key(root: $0, scale: (key.wrappedValue ?? chosen).scale) }
            })
        return Group {
            menuControl("Key", selection: root, unset: "As chosen",
                        options: PitchClass.allCases, label: \.name)
            if let own = key.wrappedValue {
                Picker("Scale", selection: Binding(get: { own.scale },
                                                   set: { key.wrappedValue = Key(root: own.root, scale: $0) })) {
                    ForEach(ScaleType.allCases.filter(\.isHeptatonic)) { scale in
                        Text(scale.displayName).tag(scale)
                    }
                }
                .pickerStyle(.menu)
                .tint(.orange)
                .labelsHidden()
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

    /// A choice from a menu that can also be left unset.
    private func menuControl<Option: Hashable>(_ name: String,
                                               selection: Binding<Option?>,
                                               unset: String,
                                               options: [Option],
                                               label: KeyPath<Option, String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            controlName(name)
            Picker(name, selection: selection) {
                Text(unset).tag(Option?.none)
                ForEach(options, id: \.self) { option in
                    Text(option[keyPath: label]).tag(Option?.some(option))
                }
            }
            .pickerStyle(.menu)
            .tint(.orange)
            .labelsHidden()
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
