import SwiftUI

/// The MIDI controller, drawn as it is (`ControllerLayout`) and lit with
/// what it is doing: the keys held, the pads struck, where the knobs and
/// the wheels are and which buttons are on.
///
/// It is played as an Orchid (`OrchidState`), so the controls that play a
/// part there are marked with it.
///
/// Under it is what the Orchid is doing, the last message heard and what
/// it was read as, and LEARN, which teaches a control chosen on the
/// drawing what it sends: the next message heard is its.
struct ControllerView: View {
    @Environment(PerformanceState.self) private var state

    var body: some View {
        let controller = state.controller
        let layout = controller.layout
        VStack(alignment: .leading, spacing: 14) {
            header
            ControllerFace(controller: controller, orchid: state.orchid)
                .aspectRatio(layout.size.width / layout.size.height, contentMode: .fit)
            ControllerReadout(controller: controller, orchid: state.orchid, key: state.key)
            Spacer(minLength: 0)
        }
    }

    /// Whether the controller is connected, and the switches.
    private var header: some View {
        @Bindable var controller = state.controller
        return HStack(spacing: 10) {
            Circle()
                .fill(controller.device == nil ? Color(white: 0.3) : Color.orange)
                .frame(width: 8, height: 8)
            Text(status)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(white: controller.device == nil ? 0.55 : 0.85))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if controller.hasLearnedAny {
                chit("RESET", isOn: false, label: "Forget what the controls learned") {
                    controller.forgetLearned()
                }
            }
            ForEach(OrchidPart.allCases, id: \.self) { part in
                controlMenu(for: part)
            }
            chit("KEY MODE", isOn: state.orchid.isKeyMode, label: "Key mode", width: 96) {
                state.orchid.switchKeyMode()
            }
            chit("VEL ARP", isOn: state.orchid.velocityPlaysArpeggio,
                 label: "Velocity plays the arpeggio", width: 84) {
                state.orchid.switchVelocityArpeggio()
            }
            chit("LEARN", isOn: controller.isLearning, label: "Learn") {
                controller.isLearning.toggle()
            }
        }
    }

    /// The knob or wheel `part` is played by, chosen from a menu of them,
    /// and lit while it has one.
    private func controlMenu(for part: OrchidPart) -> some View {
        let orchid = state.orchid
        let control = orchid.controls[part]
        return Menu {
            Picker(part.name, selection: Binding(get: { control }, set: { orchid.give(part, to: $0) })) {
                Text("None").tag(TurnedControl?.none)
                ForEach(orchid.map.turned, id: \.self) { turned in
                    Text(turned.name).tag(TurnedControl?.some(turned))
                }
            }
            .pickerStyle(.inline)
        } label: {
            chitLabel("\(part.name) · \(control?.name ?? "NONE")", isOn: control != nil, width: 150)
        }
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel(part == .voicing ? "Voicing control" : "Arpeggio control")
    }

    private var status: String {
        let controller = state.controller
        if let device = controller.device { return device }
        if controller.sources.isEmpty { return "No MIDI controller connected" }
        return "No \(controller.layout.name) · hearing \(controller.sources.joined(separator: ", "))"
    }

    /// A switch of the row, lit while it is on as the screen's others are.
    private func chit(_ text: String, isOn: Bool, label: String, width: CGFloat = 72,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            chitLabel(text, isOn: isOn, width: width)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func chitLabel(_ text: String, isOn: Bool, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(isOn ? Color.black : Color(white: 0.85))
            .lineLimit(1)
            .frame(width: width)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isOn ? Color.orange : Color(white: 0.13))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(isOn ? Color.orange : Color(white: 0.25), lineWidth: 1))
            )
    }
}

/// The controller's panel, at its own proportions: each control in its
/// frame, scaled from the layout's units to the view's points.
private struct ControllerFace: View {
    let controller: ControllerState
    let orchid: OrchidState

    var body: some View {
        GeometryReader { geo in
            let layout = controller.layout
            let scale = geo.size.width / layout.size.width
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 1.2 * scale)
                    .fill(Color(white: 0.1))
                    .overlay(RoundedRectangle(cornerRadius: 1.2 * scale)
                        .stroke(Color(white: 0.22), lineWidth: 1))

                Text(layout.name.uppercased())
                    .font(.system(size: (1.5 * scale).clamped(to: 9...18), weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(white: 0.5))
                    .placed(in: layout.nameplate, by: scale, alignment: .leading)

                ForEach(layout.captions, id: \.self) { caption in
                    Text(caption.text)
                        .font(.system(size: Self.textSize(scale), weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(white: 0.45))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .placed(in: caption.frame, by: scale)
                }

                ForEach(layout.controls) { control in
                    ControllerControlView(control: control, controller: controller, orchid: orchid,
                                          scale: scale)
                        .placed(in: control.frame, by: scale)
                }

                ControllerKeysView(controller: controller)
                    .placed(in: layout.keyboard.frame, by: scale)
            }
        }
    }

    /// The size of what is written on the panel, at `scale` points to a
    /// unit of it.
    static func textSize(_ scale: CGFloat) -> CGFloat {
        (1.0 * scale).clamped(to: 7...12)
    }
}

/// One control, drawn as its kind is and lit as far as it is moved.
private struct ControllerControlView: View {
    let control: ControllerControl
    let controller: ControllerState
    let orchid: OrchidState
    let scale: CGFloat

    private var value: Double { controller.values[control.id] ?? 0 }
    /// What is written on it: its part on the Orchid, if it has one.
    private var mark: String {
        orchid.map.mark(of: control.id) ?? orchid.part(of: control.id)?.name ?? control.mark
    }
    /// The key button is lit while key mode is on, as the Orchid's is, and
    /// the key change button while it waits for a key.
    private var isKeyButtonOn: Bool {
        control.id == orchid.map.key ? orchid.isKeyMode
            : control.id == orchid.map.keyChange && orchid.isWaitingForKey
    }
    private var isLearning: Bool { controller.learning == control.id }

    var body: some View {
        face
            .overlay {
                // The control a message is about to be learned for.
                if isLearning {
                    RoundedRectangle(cornerRadius: 0.4 * scale)
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                        .padding(-0.35 * scale)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { controller.choose(control.id) }
            .accessibilityElement()
            .accessibilityLabel(control.name)
            .accessibilityAddTraits(isLearning ? .isSelected : [])
    }

    @ViewBuilder
    private var face: some View {
        switch control.kind {
        case .pad:
            chip(lit: value, cornerRadius: 0.35 * scale)
        case .button, .pedal:
            chip(lit: value >= 0.5 || isKeyButtonOn ? 1 : 0, cornerRadius: 0.3 * scale)
        case .octaveDown:
            chip(lit: controller.keys.shift < 0 ? 1 : 0, cornerRadius: 0.3 * scale)
        case .octaveUp:
            chip(lit: controller.keys.shift > 0 ? 1 : 0, cornerRadius: 0.3 * scale)
        case .knob:
            knob
        case .pitchWheel:
            wheel(from: 0.5, to: 0.5 + value / 2)
        case .modWheel:
            wheel(from: 0, to: value)
        }
    }

    /// A pad or a button: lit as far as `lit` (0 to 1), with its mark on it.
    private func chip(lit: Double, cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(white: 0.17))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.orange.opacity(lit > 0 ? 0.35 + 0.65 * lit : 0)))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color(white: lit > 0 ? 0 : 0.3), lineWidth: 1))
            .overlay {
                Text(mark)
                    .font(.system(size: ControllerFace.textSize(scale), weight: .semibold, design: .monospaced))
                    .foregroundStyle(lit > 0 ? Color.black : Color(white: 0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
    }

    /// A knob's 270°, lit from its lowest to where it is, with its mark
    /// under it.
    private var knob: some View {
        ZStack {
            Circle().fill(Color(white: 0.17))
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(Color(white: 0.3), style: StrokeStyle(lineWidth: 0.25 * scale, lineCap: .round))
                .rotationEffect(.degrees(135))
                .padding(0.2 * scale)
            Circle()
                .trim(from: 0, to: 0.75 * value)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 0.25 * scale, lineCap: .round))
                .rotationEffect(.degrees(135))
                .padding(0.2 * scale)
            // The pointer.
            Capsule()
                .fill(Color(white: 0.85))
                .frame(width: 0.18 * scale, height: 0.7 * scale)
                .offset(y: -0.55 * scale)
                .rotationEffect(.degrees(-135 + 270 * value))
        }
        .overlay(alignment: .bottom) {
            Text(mark)
                .font(.system(size: ControllerFace.textSize(scale), weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(white: 0.6))
                .fixedSize()
                .offset(y: 1.5 * scale)
        }
    }

    /// A wheel in its slot, lit from `from` to `to` (shares of its height
    /// from the bottom), with a line where it is.
    private func wheel(from: Double, to: Double) -> some View {
        GeometryReader { geo in
            let height = geo.size.height
            let low = min(from, to), high = max(from, to)
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 0.5 * scale)
                    .fill(Color(white: 0.15))
                Rectangle()
                    .fill(Color.orange.opacity(0.55))
                    .frame(height: height * (high - low))
                    .offset(y: height * (1 - high))
                Rectangle()
                    .fill(to == from ? Color(white: 0.6) : Color.orange)
                    .frame(height: 2)
                    .offset(y: (height * (1 - to) - 1).clamped(to: 0...max(0, height - 2)))
            }
            .clipShape(RoundedRectangle(cornerRadius: 0.5 * scale))
            .overlay(RoundedRectangle(cornerRadius: 0.5 * scale)
                .stroke(Color(white: 0.3), lineWidth: 1))
        }
        .overlay(alignment: .top) {
            // The part it plays, over it: a wheel has no mark of its own.
            if let part = orchid.part(of: control.id) {
                Text(part.name)
                    .font(.system(size: ControllerFace.textSize(scale), weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.orange)
                    .fixedSize()
                    .offset(y: -1.6 * scale)
            }
        }
    }
}

/// The controller's keys, lit as they are held, brighter the harder they
/// are struck, and drawn as the piano's are (`PianoKeys`).
private struct ControllerKeysView: View {
    let controller: ControllerState

    var body: some View {
        let keyboard = controller.layout.keyboard
        Canvas { context, size in
            let keys = PianoKeys(size: size, span: PianoSpan(
                start: Double(PianoKeys.whitesBelow(keyboard.lowestNote)),
                count: Double(keyboard.notes.filter { !PianoKeys.isBlack($0) }.count)))
            let notes = keyboard.notes
            for isBlack in [false, true] {
                for note in notes where PianoKeys.isBlack(note) == isBlack {
                    let frame = keys.frame(of: note).insetBy(dx: isBlack ? 0 : 0.5, dy: 0)
                    let shape = Path(roundedRect: frame, cornerRadius: 2)
                    let velocity = controller.velocity(ofKey: note - keyboard.lowestNote)
                    context.fill(shape, with: .color(isBlack ? Color(white: 0.08) : Color(white: 0.88)))
                    if let velocity {
                        context.fill(shape, with: .color(.orange.opacity(0.45 + 0.55 * Double(velocity) / 127)))
                    }
                    if !isBlack {
                        context.stroke(shape, with: .color(Color(white: 0.35)), lineWidth: 0.5)
                    }
                    // Each C, named in the octave it sends as the keys are
                    // shifted now.
                    if note % 12 == 0, let name = PianoKeys.octaveName(of: note + controller.keys.shift * 12) {
                        context.draw(Text(name)
                                        .font(.system(size: (frame.width * 0.42).clamped(to: 7...11),
                                                      weight: .medium, design: .monospaced))
                                        .foregroundStyle(Color(white: velocity == nil ? 0.4 : 0.1)),
                                     at: CGPoint(x: frame.midX, y: frame.maxY - 8))
                    }
                }
            }
        }
    }
}

/// What was last heard and what it was read as, and while learning, what
/// is to be done.
private struct ControllerReadout: View {
    let controller: ControllerState
    let orchid: OrchidState
    let key: Key

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if controller.isLearning {
                line(learningPrompt, color: .orange)
            } else if orchid.isChoosingKey {
                line("Strike a root to make it the key (hold MIN for a minor one).", color: .orange)
            }
            line(playing, color: Color(white: 0.85))
            line(heard, color: Color(white: 0.7))
            if controller.keys.shift != 0 {
                line("Octave \(controller.keys.shift > 0 ? "+" : "")\(controller.keys.shift)",
                     color: Color(white: 0.55))
            }
        }
    }

    private func line(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(2)
    }

    /// How the Orchid's roots are played now: in the key or as notes, and
    /// with the buttons held.
    private var playing: String {
        let mode = orchid.isKeyMode ? "Key mode · \(key.root.name) \(key.scale.displayName)"
                                    : "Key mode off · a root alone is its note"
        var parts = [mode]
        if let build = orchid.build, build.type != .note { parts.append(build.legend) }
        if let arpeggio = orchid.heldArpeggio {
            let speed = arpeggio.cycle?.label ?? "as set"
            parts.append("Arpeggio \(arpeggio.pattern == .up ? "up" : "down") · \(speed)")
        }
        return parts.joined(separator: " · ")
    }

    private var learningPrompt: String {
        guard let id = controller.learning, let control = controller.layout.control(id) else {
            return "Choose a control to teach it what it sends."
        }
        let now = controller.address(of: id).map { "now \($0.label)" } ?? "now nothing"
        return "Press or move \(control.name) on the controller (\(now))."
    }

    private var heard: String {
        guard let heard = controller.heard else { return "Nothing heard yet" }
        let target: String
        switch heard.target {
        case let .control(id):
            let name = controller.layout.control(id)?.name ?? id
            target = controller.hasLearned(id) ? "\(name) (learned)" : name
        case let .key(key):
            target = "key \(Self.noteName(controller.layout.keyboard.lowestNote + key + controller.keys.shift * 12))"
        case .none:
            target = "nothing on the controller"
        }
        return "Heard \(heard.message.label)  →  \(target)"
    }

    /// "C♯3": a note as the app names it (middle C is C4).
    private static func noteName(_ note: Int) -> String {
        "\(PitchClass(rawValue: note % 12)?.name ?? "?")\(note / 12 - 1)"
    }
}

private extension View {
    /// The view in `frame`, a frame on the panel, at `scale` points to a
    /// unit of it.
    func placed(in frame: CGRect, by scale: CGFloat, alignment: Alignment = .center) -> some View {
        self.frame(width: frame.width * scale, height: frame.height * scale, alignment: alignment)
            .offset(x: frame.minX * scale, y: frame.minY * scale)
    }
}
