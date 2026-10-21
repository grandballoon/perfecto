import SwiftUI

/// The Dissonance Lab (`DissonanceLabState`): what the two notes are, how
/// rough they are, their partials and the pairs that collide, the beat of
/// the pair spotlighted, and under them the level, the A/B button, the
/// interval pads and every control. With room for it the pictures and the
/// controls are side by side.
struct DissonanceLabView: View {
    @Environment(PerformanceState.self) private var state

    /// Wider than this, the controls are beside the pictures.
    private static let sideBySide: CGFloat = 640

    var body: some View {
        GeometryReader { geo in
            if geo.size.width >= Self.sideBySide {
                HStack(alignment: .top, spacing: 16) {
                    ScrollView { pictures.padding(.bottom, 16) }
                    ScrollView { controls.padding(.bottom, 16) }
                        .frame(width: min(420, geo.size.width * 0.45))
                }
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        pictures
                        controls
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .tint(.orange)
    }

    private var lab: DissonanceLabState { state.lab }

    private var pictures: some View {
        VStack(spacing: 12) {
            LabReadout(lab: lab)
            if let sounding = lab.sounding {
                RoughnessMeter(roughness: sounding.roughness)
                PartialLadderView(sounding: sounding)
                    .frame(height: 300)
                    .labPanel()
                BeatEnvelopeStrip(pair: sounding.spotlit.first)
                    .frame(height: 56)
                    .labPanel()
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            LabLevelRow(lab: lab)
            IntervalPads(lab: lab)
            LabAdvanced(lab: lab)
        }
    }
}

// MARK: – The readout

/// The notes, the interval they make, its just ratio and the root they
/// imply; or what to do while fewer than two are held.
private struct LabReadout: View {
    let lab: DissonanceLabState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let sounding = lab.sounding {
                Text(sounding.interval.name)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Color(red: 1, green: 0.65, blue: 0))
                Text("\(Self.name(sounding.keyed.low)) – \(Self.name(sounding.keyed.high))  ·  "
                     + "\(sounding.interval.semitones) semitones  ·  JI \(sounding.interval.justRatio)")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Color(white: 0.8))
                Text("\(PartialLadderView.hz(sounding.lowHz)) + \(PartialLadderView.hz(sounding.highHz))  ·  "
                     + (sounding.isJust ? "just" : "12-TET") + "  ·  " + rootText(sounding))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color(white: 0.55))
                if sounding.settings.isDichotic {
                    Label("Headphones needed: the low note is in the left ear, the high note in the right.",
                          systemImage: "headphones")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.orange)
                }
            } else if let note = lab.held.first?.note {
                Text(Self.name(note))
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Color(red: 1, green: 0.65, blue: 0))
                Text("One note: hold a second to hear the two together.")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Color(white: 0.6))
            } else {
                Text("Dissonance Lab")
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Color(red: 1, green: 0.65, blue: 0))
                Text("Hold two notes on a MIDI keyboard, or a pad below, to hear what makes them smooth or rough.")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Color(white: 0.6))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .labPanel()
        .accessibilityElement(children: .combine)
    }

    private func rootText(_ sounding: LabSounding) -> String {
        guard let root = sounding.analysis.impliedRoot else { return "no clear root" }
        return "root \(PartialLadderView.hz(root.hz)) (\(root.numerator)/\(root.denominator))"
    }

    /// A MIDI note's name, middle C being C4.
    static func name(_ note: Int) -> String {
        "\(PitchClass(rawValue: note % 12)?.name ?? "?")\(note / 12 - 1)"
    }
}

/// How rough the two notes are, as a share of a minor second over the
/// lower one in the same sound.
private struct RoughnessMeter: View {
    let roughness: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ROUGHNESS")
                Spacer()
                Text("\(Int((roughness * 100).rounded()))% of a minor 2nd")
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(Color(white: 0.7))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(white: 0.15))
                    Capsule().fill(Color.orange)
                        .frame(width: geo.size.width * CGFloat(roughness.clamped(to: 0...1)))
                }
            }
            .frame(height: 10)
        }
        .labPanel()
        .accessibilityElement()
        .accessibilityLabel("Roughness")
        .accessibilityValue("\(Int((roughness * 100).rounded())) percent of a minor second")
    }
}

// MARK: – Level and A/B

private struct LabLevelRow: View {
    @Bindable var lab: DissonanceLabState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LEVEL")
                if lab.isAdjusted { Text("· adjusted").foregroundStyle(Color(white: 0.5)) }
                Spacer()
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(Color(white: 0.7))
            HStack(spacing: 10) {
                SegmentedToggle(choices: LabLevel.allCases.map(Optional.some),
                                label: { $0.map { "\($0.rawValue)" } ?? "" },
                                hotkey: { _ in nil },
                                selection: Binding(get: { lab.isAdjusted ? nil : lab.level },
                                                   set: { if let level = $0 { lab.choose(level) } }))
                HoldButton(label: "A/B", isHeld: lab.isPlain) { lab.isPlain = $0 }
                    .frame(width: 64)
                    .accessibilityHint("Hold to hear the notes plain: equal temperament and no enhancement")
            }
        }
        .labPanel()
    }
}

/// A chit that is on while it is held down.
private struct HoldButton: View {
    let label: String
    let isHeld: Bool
    let onHold: (Bool) -> Void

    var body: some View {
        Text(label)
            .font(.system(.footnote, design: .monospaced).weight(.semibold))
            .foregroundStyle(isHeld ? Color.black : Color(white: 0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHeld ? Color.orange : Color(white: 0.13))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(isHeld ? Color.orange : Color(white: 0.25), lineWidth: 1))
            )
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isHeld { onHold(true) } }
                .onEnded { _ in onHold(false) })
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onHold(!isHeld) }
    }
}

// MARK: – The pads

/// The twelve intervals over a root, each sounding while it is held.
private struct IntervalPads: View {
    @Bindable var lab: DissonanceLabState

    private static let intervals = Array(Interval.allCases.dropFirst())
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PADS OVER")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color(white: 0.7))
                Stepper(value: Binding(get: { lab.padRoot }, set: { lab.setPadRoot($0) }),
                        in: DissonanceLabState.padRoots) {
                    Text(LabReadout.name(lab.padRoot))
                        .font(.system(.footnote, design: .monospaced).weight(.semibold))
                        .foregroundStyle(Color(white: 0.9))
                }
                .accessibilityLabel("Pads' root")
                .accessibilityValue(LabReadout.name(lab.padRoot))
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Self.intervals, id: \.self) { interval in
                    HoldButton(label: interval.shortName, isHeld: lab.heldPad == interval) { held in
                        if held { lab.pressPad(interval) } else if lab.heldPad == interval { lab.releasePad() }
                    }
                    .accessibilityLabel(interval.name)
                }
            }
        }
        .labPanel()
    }
}

// MARK: – Every control

private struct LabAdvanced: View {
    @Bindable var lab: DissonanceLabState
    @State private var isOpen = false

    var body: some View {
        DisclosureGroup(isExpanded: $isOpen) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Original register", isOn: Binding(get: { lab.settings.voicing == .original },
                                                         set: { lab.settings.voicing = $0 ? .original : .close }))
                section("SOUND") {
                    labeled("Partials", "\(lab.settings.partialCount)") {
                        Slider(value: Binding(get: { Double(lab.settings.partialCount) },
                                              set: { lab.settings.partialCount = Int($0.rounded()) }),
                               in: Double(LabSettings.partialRange.lowerBound)...Double(LabSettings.partialRange.upperBound),
                               step: 1)
                    }
                    labeled("Rolloff", String(format: "1/n^%.1f", lab.settings.brightness)) {
                        Slider(value: $lab.settings.brightness, in: LabSettings.brightnessRange)
                    }
                    Toggle("Piano-like decay", isOn: $lab.settings.isStruck)
                }
                section("SPOTLIGHT") {
                    Toggle("Spotlight", isOn: $lab.settings.spotlight)
                    Stepper("Pairs: \(lab.settings.spotlightCount)", value: $lab.settings.spotlightCount,
                            in: LabSettings.spotlightRange)
                    labeled("Boost", String(format: "+%.0f dB", lab.settings.spotlightBoost)) {
                        Slider(value: $lab.settings.spotlightBoost, in: LabSettings.boostRange, step: 1)
                    }
                    labeled("Others", String(format: "%.0f dB", lab.settings.spotlightCut)) {
                        Slider(value: $lab.settings.spotlightCut, in: LabSettings.cutRange, step: 1)
                    }
                }
                section("BEAT") {
                    picker("Shaping", BeatShaping.allCases, \.displayName, $lab.settings.beatShaping)
                    picker("Tuning", LabTuning.allCases, \.displayName, $lab.settings.tuning)
                    picker("Crutch", BeatCrutch.allCases, \.displayName, $lab.settings.crutch)
                    labeled("Crutch depth", "\(Int((lab.settings.crutchDepth * 100).rounded()))%") {
                        Slider(value: $lab.settings.crutchDepth, in: 0...1)
                    }
                    .disabled(lab.settings.crutch == .off)
                }
                section("HEARING") {
                    Toggle("Root tone", isOn: $lab.settings.rootTone)
                    Toggle("Dichotic (headphones)", isOn: $lab.settings.isDichotic)
                }
            }
            .font(.system(.footnote, design: .monospaced))
            .foregroundStyle(Color(white: 0.85))
            .padding(.top, 10)
        } label: {
            Text("ADVANCED")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Color(white: 0.7))
        }
        .labPanel()
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color(white: 0.5))
            content()
        }
    }

    private func labeled<Content: View>(_ title: String, _ value: String,
                                        @ViewBuilder _ control: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(value).foregroundStyle(Color(white: 0.6))
            }
            control()
                .accessibilityLabel(title)
                .accessibilityValue(value)
        }
    }

    private func picker<Choice: Hashable>(_ title: String, _ choices: [Choice], _ name: KeyPath<Choice, String>,
                                          _ selection: Binding<Choice>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Picker(title, selection: selection) {
                ForEach(choices, id: \.self) { Text($0[keyPath: name]).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }
}

private extension View {
    /// The lab's panels: dark, edged, as the note display is.
    func labPanel() -> some View {
        padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(white: 0.05))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.15), lineWidth: 1))
            )
    }
}
