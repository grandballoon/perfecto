import SwiftUI

/// The side panel's Effects page. Each effect is a card: its switch, and
/// under it, while the effect is on, its controls, if it has any (the
/// chorus and the reverb are each one sound). The panel is narrow, so a
/// control sits below its name rather than beside it.
struct EffectsPanel: View {
    @Environment(PerformanceState.self) private var state
    @Environment(SidePanelState.self) private var panel

    /// Whose effects the cards show: the ones chosen (at the top of the
    /// page, or by whatever opened it) while they are still there, the
    /// keys' otherwise.
    private var target: EffectsTarget {
        switch panel.effectsTarget {
        case .keys:         return .keys
        case .loop(let id): return state.quickLoopState.loops.contains { $0.id == id } ? .loop(id) : .keys
        case .pad:          return editedPad == nil ? .keys : .pad
        }
    }

    /// The loop being edited.
    private var loop: Layer.ID? {
        if case .loop(let id) = target { id } else { nil }
    }

    /// The pad being edited on the pads' screen, if it has a sound to edit.
    private var editedPad: PadPlace? {
        state.pads.edited.flatMap { state.pads.grid[$0] == nil ? nil : $0 }
    }

    private var isKeys: Bool { target == .keys }

    /// The chord key chosen in the Key zones card's picture, whose own
    /// zones the card sets; nil is the zones of every key.
    @State private var zonedKey: Degree?

    var body: some View {
        @Bindable var effects = state.effects
        VStack(alignment: .leading, spacing: 24) {
            if !state.quickLoopState.loops.isEmpty || editedPad != nil { targetPicker }

            section("NOTES",
                    footnote: "Plays each chord one note at a time: Arpeggio 1 from the lowest note up, Arpeggio 2 from the highest down. One pass over the chord takes the cycle, however many notes it has. Works in Play, in the sequencer and on the Tonnetz, and is sent over MIDI.") {
                card("Arpeggiator", isOn: control(\.arpeggiator.isOn)) {
                    pickerControl("Arpeggio", selection: control(\.arpeggiator.pattern),
                                  options: ArpeggioPattern.allCases, label: \.label)
                    pickerControl("Cycle, in beats", selection: control(\.arpeggiator.cycle),
                                  options: ArpeggioCycle.allCases, label: \.label)
                    if isKeys { slideSwitch("cycle", isOn: $effects.arpeggiator.followsSlide) }
                    tempoControl
                }
            }

            section("SOUND",
                    footnote: isKeys
                        ? "Applied to what the keys and the Tonnetz play. A loop keeps the effects it was recorded with; choose the loop above to change them. The chorus and the reverb are sent over MIDI as CC 93 and 91."
                        : "Applied to this \(targetName) alone, whatever is set for the keys.") {
                card("Chorus", isOn: control(\.chorus.isOn))
                card("Reverb", isOn: control(\.reverb.isOn))
                card("Delay", isOn: control(\.delay.isOn))
            }

            section("VOICE",
                    footnote: vocoderFootnote) {
                card("Vocoder", isOn: control(\.vocoder.isOn)) {
                    sliderControl("Amount", value: control(\.vocoder.amount))
                    if isKeys { slideSwitch("amount", isOn: $effects.vocoder.followsSlide) }
                }
                if state.micAccess.isRefused { micRefusal }
            }

            if isKeys {
                footnote("Slide: where a finger is on a chord key plays every control whose slide switch is on (the arpeggio's cycle, the vocoder's amount), low at the bottom of the key and high at the top. Lifting the finger returns each to the value set here.")

                section("KEYS",
                        footnote: "Divides the chord keys into zones, marked on the keys. A finger in a zone switches that zone's effect on, at the value chosen for it if it has one, even if the effect is off above. Anywhere else on the key, and once the finger lifts, the effect is as set above. Zones can play different effects, or one effect at different values. A zone can also have a key and an octave of its own: a chord played from it is in them, and a finger sliding into it changes the chord it is holding. Every key is divided alike unless it has zones of its own: tap a key in the picture to give it some, and again to go back to every key's. One zone is the whole key, so an effect can be on one key alone.") {
                    card("Key zones", isOn: $effects.zones.isOn) {
                        KeyZonesMap(key: state.key,
                                    zones: { effects.zones(of: $0) },
                                    hasOwn: { effects.keyZones[$0]?.isOn == true },
                                    selected: $zonedKey)
                        let zones = zonesBinding
                        if let key = zonedKey {
                            Toggle(isOn: zones.isOn) { controlName("\(numeral(key)) has zones of its own") }
                                .tint(.orange)
                        } else {
                            controlName("Every key. Tap a key for zones of its own.")
                        }
                        if zonedKey == nil || zones.wrappedValue.isOn {
                            pickerControl("Zones", selection: zones.count,
                                          options: Array(KeyZoneSettings.counts), label: \.description)
                            ForEach(zones.wrappedValue.zones.indices.reversed(), id: \.self) { index in
                                zoneControl(zoneName(index, of: zones.wrappedValue.count),
                                            zone: zoneBinding(index, in: zones))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: – Whose effects

    /// Chooses whose effects the cards below set: the keys', one loop's,
    /// or those of the pad being edited. Each loop and pad has its own, and
    /// nothing set for the keys reaches them.
    private var targetPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            SidePanelSectionLabel("EFFECTS OF")
            Picker("Effects of", selection: Binding(get: { target }, set: { panel.effectsTarget = $0 })) {
                Text("The keys").tag(EffectsTarget.keys)
                ForEach(Array(state.quickLoopState.loops.enumerated()), id: \.element.id) { index, entry in
                    Text("Loop \(index + 1)").tag(EffectsTarget.loop(entry.id))
                }
                if let pad = editedPad {
                    Text("Pad \(pad.row + 1)·\(pad.column + 1)").tag(EffectsTarget.pad)
                }
            }
            .pickerStyle(.menu)
            .tint(.orange)
            .labelsHidden()
        }
    }

    /// What the page calls whatever its cards are set for, other than the keys.
    private var targetName: String { target == .pad ? "pad" : "loop" }

    private var vocoderFootnote: String {
        switch target {
        case .keys:
            return "Your voice shapes the notes: hold a chord and speak or sing into the phone, and the chord says the words. It uses the microphone while it is on. Headphones give the clearest result; on the speaker the phone has to cancel its own sound, which dulls it. Bright sounds, such as Saw Lead and Strings, speak most clearly."
        case .loop:
            return "How much of this loop your voice shapes. The microphone is open only while the vocoder is on for the keys or for a pad; while it is off, the loop is heard whole."
        case .pad:
            return "How much of this pad your voice shapes. The microphone is open while the pads are on screen or playing in sequence."
        }
    }

    /// One setting of the effects being shown: the keys' as set, the chosen
    /// loop's own, or the edited pad's. Setting a loop's changes every note
    /// of it, and a pad's that pad, and nothing of the keys'.
    private func control<Value>(_ setting: WritableKeyPath<NoteEffects, Value>) -> Binding<Value> {
        let (effects, sequencer, pads) = (state.effects, state.sequencerState, state.pads)
        if target == .pad, let pad = editedPad {
            return Binding(get: { (pads.grid[pad]?.effects ?? effects.asSet)[keyPath: setting] },
                           set: { value in pads.edit { $0.effects[keyPath: setting] = value } })
        }
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

    /// A chord key as it is named on the keys.
    private func numeral(_ degree: Degree) -> String {
        degreeNumeral(key: state.key, degree: degree)
    }

    /// The zones the card sets: every key's, or the chosen key's own, which
    /// start as the whole key.
    private var zonesBinding: Binding<KeyZoneSettings> {
        let effects = state.effects
        guard let key = zonedKey else {
            return Binding(get: { effects.zones }, set: { effects.zones = $0 })
        }
        return Binding(get: { effects.keyZones[key] ?? .ofOneKey }, set: { effects.keyZones[key] = $0 })
    }

    /// Zones are listed as they sit on the key: the top one first.
    private func zoneName(_ index: Int, of count: Int) -> String {
        if count == 1 { return "The whole key" }
        switch index {
        case 0:         return "Zone 1, bottom of the key"
        case count - 1: return "Zone \(count), top of the key"
        default:        return "Zone \(index + 1)"
        }
    }

    /// The zone at `index`. A row can outlive its zone for a moment when the
    /// number of zones goes down, so the binding answers for one that is gone.
    private func zoneBinding(_ index: Int, in zones: Binding<KeyZoneSettings>) -> Binding<KeyZone> {
        Binding(
            get: { zones.wrappedValue.zones.indices.contains(index) ? zones.wrappedValue.zones[index] : KeyZone() },
            set: { if zones.wrappedValue.zones.indices.contains(index) { zones.wrappedValue.zones[index] = $0 } }
        )
    }

    /// One zone, under its name: the octave its chords are in, the effect
    /// it plays with the value it holds that effect's played control at (if
    /// it has one), and the key and inversion its chords are in.
    private func zoneControl(_ name: String, zone: Binding<KeyZone>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(Color(white: 0.2))
            Text(name)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(white: 0.85))
            pickerControl("Octave (— is the one chosen)", selection: zone.octave,
                          options: [nil] + PerformanceState.octaves.map(Optional.some), label: \.octaveLabel)
            menuControl("Effect", selection: zone.effect, unset: "No effect",
                        options: EffectChoice.allCases, label: \.label)
            switch zone.wrappedValue.effect {
            case .arpeggio:
                pickerControl("Cycle, in beats", selection: zoneCycle(zone),
                              options: ArpeggioCycle.allCases, label: \.label)
            case .vocoder:
                sliderControl("Amount", value: zone.value)
            case .chorus, .reverb, .delay, nil:
                EmptyView()
            }
            zoneKeyControl(zone.key)
            menuControl("Inversion", selection: zone.inversion, unset: "As chosen",
                        options: PerformanceState.inversions.map(Inversion.init(steps:)), label: \.label)
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

    /// An effect with a switch and nothing else to set.
    private func card(_ name: String, isOn: Binding<Bool>) -> some View {
        card(name, isOn: isOn) { EmptyView() }
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

private extension Optional where Wrapped == Int {
    /// A zone's octave as its picker shows it: nil follows the octave chosen.
    var octaveLabel: String { map(String.init) ?? "—" }
}
