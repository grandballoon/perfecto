import DeskCore
import MusicTheoryCore
import SwiftUI

/// Twin rings: the degree pie under the left thumb, the color ring under
/// the right, and the triggers under them.
struct TwinRingsView: View {
    let layout: TwinRings
    let settings: DeskSettings
    let frame: GamepadFrame
    /// Lays the ring another way, chosen with the mouse.
    let arrange: (RingArrangement) -> Void

    var body: some View {
        HStack(spacing: 20) {
            VStack(spacing: 12) {
                Caption(control: "Left stick", title: "Degree, I at the top and on clockwise")
                PieView(targets: layout.degreeTargets(settings), stick: frame.left,
                        centre: (numeral(layout.degree, in: settings.key), settings.key.root.name + " " + settings.key.scale.displayName))
                TriggerBar(name: "LT", value: frame.leftTrigger, steps: TriggerSteps.three.count, tint: Theme.melody)
                Text("Arpeggio: " + (ArpeggioRate(rawValue: layout.arpeggioStep)?.name ?? "off"))
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            .panel()
            VStack(spacing: 12) {
                if layout.isOnFavorites {
                    Caption(control: "Y + right stick", title: "Favorites in \(settings.favorites.table.name): A pins, X unpins")
                    PieView(targets: layout.favoriteTargets(settings), stick: frame.right,
                            centre: (layout.chord(settings).name, "flick keeps"))
                } else if layout.isOnVoices {
                    HStack {
                        Caption(control: layout.compassLatched ? "Both sticks" : "LB + both sticks",
                                title: "The voices: each a semitone or two, to the consonant chords nearest")
                        Spacer()
                        Text("L3: compass").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Theme.faint)
                    }
                    HStack(alignment: .center, spacing: 14) {
                        BassColumn(targets: layout.bassTargets(settings), stick: frame.left)
                            .frame(width: 104)
                        let shells = layout.voiceTargets(settings)
                        PieView(targets: shells.inner, stick: frame.right, outer: shells.outer,
                                centre: (layout.chord(settings).name,
                                         layout.resetsTo(settings).map { "R3: back to \($0.name)" } ?? "flick takes a step"))
                    }
                } else if layout.isOnCompass {
                    HStack {
                        Caption(control: layout.compassLatched ? "Right stick" : "LB + right stick",
                                title: "The step compass: a tone added, raised, taken away, lowered")
                        Spacer()
                        if layout.compassLatched {
                            Text("ON · long-press LB to turn off")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.chord)
                        }
                    }
                    PieView(targets: layout.compassTargets(settings), stick: frame.right,
                            centre: (layout.chord(settings).name,
                                     layout.resetsTo(settings).map { "R3: back to \($0.name)" } ?? "flick keeps"))
                } else {
                    HStack {
                        Caption(control: "Right stick", title: layout.isExtended ? "The ring to the 13th" : "The color ring: mode round, height out")
                        Spacer()
                        ArrangementSwitch(chosen: settings.ringArrangement, choose: arrange)
                    }
                    RingView(rings: layout.ringTargets(settings), pie: settings.ring(layout.degree), stick: frame.right,
                             centre: (layout.chord(settings).name, layout.kept == nil && layout.keptStep == nil ? "plain" : "kept"))
                    HStack(spacing: 14) {
                        Fact(name: "Order", value: settings.ringOrder.name)
                        Fact(name: "Filter", value: settings.ringFilter.name)
                        Spacer()
                        Text("Menu changes them").font(.system(size: 10)).foregroundStyle(Theme.faint)
                    }
                    Text(settings.ringArrangement.summary)
                        .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
                TriggerBar(name: "RT", value: frame.rightTrigger)
                SoundingLine(line: layout.line, title: "Strike with RT or A")
            }
            .panel()
        }
    }
}

/// The bass's moves, upright as the left stick moves it: two semitones up
/// at the top, two down at the bottom.
struct BassColumn: View {
    /// Up a semitone, up two, down a semitone, down two.
    let targets: [Target?]
    let stick: Stick

    var body: some View {
        VStack(spacing: 6) {
            Caption(control: "Left stick", title: "Bass")
            ForEach([1, 0, 2, 3], id: \.self) { index in
                if index == 2 {
                    Capsule().fill(Theme.chord.opacity(abs(stick.y) > 0.3 ? 0.9 : 0.25))
                        .frame(width: 10, height: 10)
                        .offset(y: CGFloat(-stick.y) * 8)
                }
                if let target = targets[index] {
                    TargetLabel(target: target, accent: Theme.chord, compact: true)
                        .opacity(target.isHidden ? 0.4 : 1)
                } else {
                    Text("—").font(.system(size: 11)).foregroundStyle(Theme.faint)
                }
            }
        }
    }
}

/// The ring's three arrangements, as a switch: L3 or Menu › Color ring
/// change it from the controller.
struct ArrangementSwitch: View {
    let chosen: RingArrangement
    let choose: (RingArrangement) -> Void

    var body: some View {
        HStack(spacing: 2) {
            Text("L3")
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.faint)
                .padding(.trailing, 4)
            ForEach(RingArrangement.allCases, id: \.self) { arrangement in
                Button {
                    choose(arrangement)
                } label: {
                    Text(arrangement.name)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .foregroundStyle(arrangement == chosen ? Color.black : Theme.text)
                        .background(arrangement == chosen ? Theme.chord : Theme.raised, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Petals and depth: the degree pie, the diamond of what each face button
/// strikes, and the scale of darker and brighter the triggers move along.
struct PetalsView: View {
    let layout: Petals
    let settings: DeskSettings
    let frame: GamepadFrame

    var body: some View {
        HStack(spacing: 20) {
            VStack(spacing: 12) {
                Caption(control: "Left stick", title: "Degree")
                PieView(targets: layout.degreeTargets(settings), stick: frame.left,
                        centre: (numeral(layout.degree, in: settings.key), settings.summary))
                VoicingBend(layout: layout, stick: frame.right)
            }
            .panel()
            VStack(spacing: 14) {
                Caption(control: layout.isMarking ? "LB + face buttons" : "Face buttons",
                        title: layout.isMarking ? "Marks on the triad" : "Strike at four heights")
                Diamond(targets: layout.petalTargets(settings), frame: frame)
                    .frame(maxHeight: .infinity)
                Caption(control: "LT ◀  ▶ RT", title: "Darker and brighter, a mode at a time")
                DepthScale(targets: layout.depthTargets(settings))
                HStack(spacing: 16) {
                    TriggerBar(name: "LT", value: frame.leftTrigger, steps: TriggerSteps.three.count, tint: Theme.borrowed)
                    TriggerBar(name: "RT", value: frame.rightTrigger, steps: TriggerSteps.three.count)
                }
                SoundingLine(line: layout.line, title: "Hold a face button")
            }
            .panel()
        }
    }
}

/// Face Chords: the face buttons as tiles where they are on the controller,
/// each with the number and the name of its chord, and the chord heard in
/// the middle, with the second voice's under it.
struct FaceChordsView: View {
    let layout: FaceChords
    let settings: DeskSettings
    let frame: GamepadFrame

    var body: some View {
        VStack(spacing: 14) {
            Caption(control: "Face buttons", title: layout.isLayered ? "LT held" : "Chords by number")
            GeometryReader { proxy in
                let middle = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                let distance = min(proxy.size.width, proxy.size.height) * 0.34
                ZStack {
                    heard.position(middle)
                    ForEach(FaceChords.faces, id: \.self) { button in
                        tile(button)
                            .position(point(middle, bearing: FaceChords.bearing(button), distance: distance))
                    }
                }
            }
            .frame(minHeight: 320)
            TriggerBar(name: "LT", value: frame.leftTrigger, steps: 2, tint: Theme.borrowed)
        }
        .panel()
    }

    private var heard: some View {
        VStack(spacing: 2) {
            if let heard = layout.heard {
                Text(numeral(heard.degree, in: settings.key)).font(.system(size: 44, weight: .heavy, design: .rounded))
                Text(layout.line.chord?.name ?? "").font(.system(size: 20, weight: .semibold, design: .rounded))
            } else {
                Text("Hold a face button").font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
            if let over = layout.voices[1].heard {
                Text("over " + numeral(over.degree, in: settings.key) + " · " + (layout.voices[1].line.chord?.name ?? ""))
                    .font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.melody)
            }
        }
        .foregroundStyle(Theme.chord)
    }

    private func tile(_ button: PadButton) -> some View {
        let degree = layout.map.degree(button, layered: layout.isLayered)
        let tint = Theme.color(of: button) ?? Theme.chord
        let lit = layout.heard?.button == button
        return VStack(spacing: 2) {
            Text(button.rawValue.uppercased()).font(.system(size: 11, weight: .heavy, design: .rounded))
            Text(degree.map { numeral($0, in: settings.key) } ?? "–").font(.system(size: 30, weight: .heavy, design: .rounded))
            Text(degree.map { DeskChord(key: settings.key, degree: $0).name } ?? "").font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(lit ? Color.black : tint)
        .frame(width: 112, height: 96)
        .background(RoundedRectangle(cornerRadius: 18).fill(lit ? tint : Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(tint.opacity(frame.isDown(button) ? 1 : 0.5), lineWidth: 2))
    }
}

/// The four face buttons, where they are on the controller, each with the
/// chord it would strike now.
struct Diamond: View {
    let targets: [Target]
    let frame: GamepadFrame

    var body: some View {
        GeometryReader { proxy in
            let middle = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let distance = min(proxy.size.width, proxy.size.height) * 0.33
            ZStack {
                ForEach(Array(zip(Petals.diamond, targets)), id: \.0) { button, target in
                    VStack(spacing: 6) {
                        ControlChip(control: .button(button), isHeld: frame.isDown(button))
                            .scaleEffect(1.3)
                        TargetLabel(target: target, accent: Theme.color(of: button) ?? Theme.chord)
                            .scaleEffect(1.15)
                    }
                    .position(point(middle, bearing: target.bearing, distance: distance))
                }
            }
        }
        .frame(minHeight: 220)
    }
}

/// The modes from three darker to three brighter, the one the triggers are
/// at lit.
struct DepthScale: View {
    let targets: [Target]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(targets.enumerated()), id: \.offset) { _, target in
                VStack(spacing: 2) {
                    Text(target.name)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text(target.detail)
                        .font(.system(size: 9, weight: .medium))
                        .opacity(0.7)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(target.isAimed ? Color.black : Theme.text)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(target.isAimed ? Theme.chord : Theme.raised.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

/// The voicing the right stick bends to, shown as a small cross.
struct VoicingBend: View {
    let layout: Petals
    let stick: Stick

    var body: some View {
        HStack(spacing: 10) {
            Caption(control: "Right stick", title: "Voicing bend")
            Spacer()
            Text(bendText)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(layout.bend == (0, 0) ? Theme.secondary : Theme.chord)
        }
    }

    private var bendText: String {
        let (octaves, roll) = layout.bend
        if octaves == 0 && roll == 0 { return "as set · R3 keeps a bend" }
        return "octave \(octaves >= 0 ? "+" : "")\(octaves) · inversion \(roll >= 0 ? "+" : "")\(roll)"
    }
}

/// The neighbourhood: the chord sounding in the middle, the chords a step
/// away round it, and the path and bookmarks under it.
struct NeighbourhoodView: View {
    let layout: Neighbourhood
    let settings: DeskSettings
    let frame: GamepadFrame

    var body: some View {
        HStack(spacing: 20) {
            VStack(spacing: 14) {
                HStack(spacing: 6) {
                    Text("LB").font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(Theme.secondary)
                    ForEach(Neighbourhood.Lens.allCases, id: \.self) { lens in
                        Text(lens.name)
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .foregroundStyle(lens == layout.lens ? Color.black : Theme.text)
                            .background(lens == layout.lens ? Theme.chord : Theme.raised, in: Capsule())
                    }
                    Text("RB").font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(Theme.secondary)
                }
                PieView(targets: layout.neighbourTargets(settings), stick: frame.right,
                        centre: (layout.centre.name, layout.centreDetail(settings)))
                Text(layout.isOnPalette ? "Y held: the bookmarks. Flick to jump, hold to listen."
                     : "Flick the right stick to move there; hold it to listen and come back.")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            .panel()
            VStack(alignment: .leading, spacing: 16) {
                Caption(control: "Left stick ← →", title: "The path")
                FlowRow(items: layout.path.enumerated().map { index, chord in
                    (chord.name, index == layout.pathIndex)
                })
                Caption(control: "L3 · Y", title: "Bookmarks")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(Array(layout.palette.enumerated()), id: \.offset) { index, chord in
                        Text(chord?.name ?? "\(index + 1)")
                            .font(.system(size: 12, weight: chord == nil ? .regular : .semibold, design: .rounded))
                            .foregroundStyle(chord == nil ? Theme.faint : Theme.text)
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .background(Theme.raised.opacity(chord == nil ? 0.4 : 0.8),
                                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                }
                Spacer(minLength: 0)
                TriggerBar(name: "RT", value: frame.rightTrigger)
                TriggerBar(name: "LT", value: frame.leftTrigger, tint: Theme.melody)
                SoundingLine(line: layout.line, title: "A strikes the centre")
            }
            .frame(maxWidth: 340)
            .panel()
        }
    }
}

/// Chips that wrap: the path's chords.
struct FlowRow: View {
    let items: [(String, Bool)]

    var body: some View {
        let shown = Array(items.suffix(12))
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, item in
                Text(item.0)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(item.1 ? Color.black : Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .background(item.1 ? Theme.chord : Theme.raised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
    }
}

/// Two voices: the chords under the left hand, the line under the right.
struct TwoVoicesView: View {
    let layout: TwoVoices
    let settings: DeskSettings
    let frame: GamepadFrame

    var body: some View {
        HStack(spacing: 20) {
            VStack(spacing: 12) {
                Caption(control: "Left stick · LT", title: "Chords, swelled")
                PieView(targets: layout.degreeTargets(settings), stick: frame.left,
                        centre: (layout.chord(settings).name, layout.height.displayName))
                TriggerBar(name: "LT", value: frame.leftTrigger)
                SoundingLine(line: layout.chords, title: layout.drones ? "Drone on" : "Pull LT to swell")
            }
            .panel()
            VStack(spacing: 12) {
                Caption(control: layout.isOnBar ? "RB + right stick" : "Right stick · RT",
                        title: layout.isOnBar ? "The bar: two octaves, at rest in tune" : "The line, pressure on RT")
                if layout.isOnBar {
                    BarView(layout: layout, settings: settings)
                } else {
                    PieView(targets: noteTargets, stick: frame.right, accent: Theme.melody,
                            centre: (melodyName, "outer ring: octave up"))
                }
                TriggerBar(name: "RT", value: frame.rightTrigger, tint: Theme.melody)
                Text(layout.chordTonesOnly ? "Y: chord tones only" : "Y: every note of the key")
                    .font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
            .panel()
        }
    }

    private var noteTargets: [Target] {
        let petals = layout.petals(settings)
        return petals.enumerated().map { index, petal in
            Target(bearing: Double(index) * 360 / Double(petals.count), name: noteName(petal.note),
                   detail: petal.isChordTone ? "chord tone" : "", fit: petal.isReachable ? .inKey : .tense,
                   isNear: petal.isChordTone, isAimed: index == layout.petal)
        }
    }

    private var melodyName: String {
        guard let pitch = layout.melody.pitch else { return "—" }
        return noteName(Int(pitch.rounded())) + (abs(pitch - pitch.rounded()) > 0.05 ? " ~" : "")
    }

    private func noteName(_ note: Int) -> String {
        "\(PitchClass(rawValue: note % 12)!.name)\(note / 12 - 1)"
    }
}

/// The Trautonium's bar, upright: the key's notes marked along it and the
/// pitch the stick is at.
struct BarView: View {
    let layout: TwoVoices
    let settings: DeskSettings

    var body: some View {
        GeometryReader { proxy in
            let low = Double((settings.octave + 1 + layout.lineOctave) * 12 + settings.key.root.rawValue)
            let span = TwoVoices.barSpan
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.raised.opacity(0.6))
                ForEach(0...Int(span), id: \.self) { step in
                    let note = Int(low) + step
                    if settings.key.has(note) {
                        let y = proxy.size.height * (1 - CGFloat(Double(step) / span))
                        Rectangle().fill(Theme.rule).frame(height: note % 12 == settings.key.root.rawValue ? 2 : 1)
                            .offset(y: y)
                    }
                }
                if let pitch = layout.melody.pitch ?? layout.barPitch {
                    let y = proxy.size.height * (1 - CGFloat((pitch - low) / span))
                    Capsule().fill(Theme.melody).frame(height: 6).offset(y: y - 3)
                }
            }
        }
        .frame(maxWidth: 200)
    }
}

/// The arranger: four bars of time, a lane to each, with every chord as
/// long as it lasts, the cursor, the playhead, and the chord being written
/// growing as it is held; and the chord the sticks aim at.
struct ArrangerView: View {
    let layout: Arranger
    let settings: DeskSettings
    let frame: GamepadFrame

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Caption(control: "D-pad · RT · LB RB", title: "Four bars at \(Int(settings.tempo)) bpm")
                    Spacer()
                    Fact(name: "Grid · L3", value: settings.grid.name)
                    Fact(name: "Cursor", value: position(layout.cursor))
                }
                VStack(spacing: 8) {
                    ForEach(0..<Arrangement.bars, id: \.self) { bar in
                        HStack(spacing: 8) {
                            Text("\(bar + 1)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.faint)
                                .frame(width: 14)
                            BarLane(bar: bar, layout: layout, grid: settings.grid)
                        }
                    }
                }
                Text(status)
                    .font(.system(size: 11, weight: layout.writing == nil ? .regular : .semibold))
                    .foregroundStyle(layout.writing == nil ? Theme.secondary : Theme.chord)
            }
            .panel()
            VStack(spacing: 12) {
                Caption(control: "Both sticks", title: "Aim")
                Text(layout.aimed(settings).name)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.chord)
                HStack(spacing: 12) {
                    PieView(targets: layout.degreeTargets(settings), stick: frame.left, compact: true)
                    PieView(targets: ringTargets, stick: frame.right, compact: true)
                }
                TriggerBar(name: "RT", value: frame.rightTrigger)
                TriggerBar(name: "LT", value: frame.leftTrigger, tint: Theme.melody)
            }
            .frame(maxWidth: 460)
            .panel()
        }
    }

    private var status: String {
        if let writing = layout.writing {
            return (writing.isLive ? "Recording live: " : "Writing: ") + "\(beats(writing.length)) held, let go to place it"
        }
        if layout.playing != nil { return "Playing round the four bars. RT records live at the playhead; Y stops." }
        return "Hold RT to write for as long as it's held. Y plays from the cursor."
    }

    /// "bar 2 · beat 3.5"
    private func position(_ beats: Double) -> String {
        let bar = Int(beats) / Arrangement.beatsPerBar + 1
        let beat = beats.truncatingRemainder(dividingBy: Double(Arrangement.beatsPerBar)) + 1
        return "bar \(bar) · beat \(beat.formatted(.number.precision(.fractionLength(0...2))))"
    }

    private func beats(_ beats: Double) -> String {
        "\(beats.formatted(.number.precision(.fractionLength(2)))) beats"
    }

    /// The ring's inner band, compactly: a sector for each mode.
    private var ringTargets: [Target] {
        let pie = settings.ring(layout.degree)
        return pie.sectors.map { sector in
            let chord = DeskChord(key: settings.key, degree: layout.degree,
                                  color: pie.color(of: RingCell(mode: sector.mode, height: .seventh)))
            return Target(bearing: sector.bearing, name: chord.name, detail: "",
                          fit: chord.fit(in: settings.key), isAimed: layout.aim?.mode == sector.mode)
        }
    }
}

/// One bar of the arranger, left to right: its beats and grid lines, the
/// chords in it (a chord over the bar line is drawn in both), the cursor
/// and the playhead.
struct BarLane: View {
    let bar: Int
    let layout: Arranger
    let grid: BeatGrid

    private var from: Double { Double(bar * Arrangement.beatsPerBar) }
    private var to: Double { from + Double(Arrangement.beatsPerBar) }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let x = { (beats: Double) in CGFloat((beats - from) / Double(Arrangement.beatsPerBar)) * width }
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.raised.opacity(0.35))
                // The grid's lines, faint, and the beats', stronger.
                ForEach(lines, id: \.self) { line in
                    let isBeat = line == line.rounded()
                    Rectangle()
                        .fill(Theme.rule.opacity(isBeat ? 0.9 : 0.35))
                        .frame(width: 1, height: isBeat ? height : height * 0.35)
                        .offset(x: x(line), y: isBeat ? 0 : height * 0.65)
                }
                ForEach(chords, id: \.start) { placed in
                    let start = max(placed.start, from), end = min(placed.end, to)
                    ChordBlock(name: placed.start >= from ? placed.chord.name : "", isHeard: isHeard(placed))
                        .frame(width: max(2, x(end) - x(start) - 2), height: height - 8)
                        .offset(x: x(start) + 1, y: 4)
                }
                if let writing = layout.writing, writing.start < to, writing.start + writing.length > from {
                    let start = max(writing.start, from), end = min(writing.start + max(writing.length, 0.05), to)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.chord.opacity(0.35))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.chord, lineWidth: 2))
                        .frame(width: max(3, x(end) - x(start)), height: height - 8)
                        .offset(x: x(start), y: 4)
                }
                if layout.cursor >= from && layout.cursor < to {
                    Capsule().fill(Theme.chord)
                        .frame(width: 3, height: height + 6)
                        .offset(x: x(layout.cursor) - 1.5, y: -3)
                }
                if let playhead = layout.playhead, playhead >= from && playhead < to {
                    Rectangle().fill(Theme.text)
                        .frame(width: 2, height: height)
                        .offset(x: x(playhead) - 1)
                }
            }
        }
        .frame(height: 58)
    }

    /// The grid's lines in the bar (beats alone with no grid).
    private var lines: [Double] {
        let step = min(grid.step ?? 1, 1)
        return stride(from: from, to: to, by: step).map { $0 }
    }

    private var chords: [Placed] {
        layout.arrangement.chords.filter { $0.start < to && $0.end > from }
    }

    private func isHeard(_ placed: Placed) -> Bool {
        guard let playhead = layout.playhead, layout.writing == nil else { return false }
        return placed.covers(playhead)
    }
}

/// A chord on the arranger's timeline.
struct ChordBlock: View {
    let name: String
    let isHeard: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isHeard ? Theme.chord : Theme.panel)
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isHeard ? Theme.chord : Theme.rule))
            .overlay(alignment: .leading) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(isHeard ? Color.black : Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 8)
            }
            .clipped()
    }
}

/// What a line of chords is sounding, named.
struct SoundingLine: View {
    let line: ChordLine
    let title: String

    var body: some View {
        HStack {
            Circle().fill(line.isSounding ? Theme.chord : Theme.rule).frame(width: 8, height: 8)
            Text(line.isSounding ? (line.chord?.name ?? "") : title)
                .font(.system(size: 13, weight: line.isSounding ? .semibold : .regular))
                .foregroundStyle(line.isSounding ? Theme.text : Theme.secondary)
            Spacer()
            if line.arpeggio != nil {
                Text("arp " + (line.arpeggio?.name ?? ""))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.melody)
            }
        }
    }
}
