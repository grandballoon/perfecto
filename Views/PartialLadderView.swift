import SwiftUI

/// The two notes' partials as rungs of two ladders side by side, the lower
/// note's on the left, on one axis of pitch that rises evenly by octaves.
/// Each rung is as wide as its partial is strong as sounded. A line joins
/// each pair of partials that collide, as thick as the pair is rough, and
/// a spotlighted pair is lit and labelled with how fast it beats. The root
/// the two imply is marked under them.
struct PartialLadderView: View {
    let sounding: LabSounding

    /// How many of the roughest pairs are named by their beat, beside the
    /// spotlighted ones: more would hide the ladder.
    private static let namedPairs = 3

    /// The pitches the axis is marked at.
    private static let marks: [Double] = [50, 100, 200, 500, 1000, 2000, 5000, 10000]

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .accessibilityElement()
        .accessibilityLabel("Partial ladder")
        .accessibilityValue(accessibilityValue)
    }

    // MARK: – Layout

    private struct Axis {
        let lowest: Double
        let highest: Double
        let height: CGFloat

        /// The height of `hz`, from the top.
        func y(_ hz: Double) -> CGFloat {
            let share = log2(hz / lowest) / log2(highest / lowest)
            return height * CGFloat(1 - share.clamped(to: 0...1))
        }
    }

    private var axis: (lowest: Double, highest: Double) {
        let count = Double(sounding.lowPartials.count)
        let lowest = min(sounding.analysis.impliedRoot?.hz ?? sounding.lowHz, sounding.lowHz) / 1.3
        let highest = max(sounding.lowHz, sounding.highHz) * count * 1.15
        return (lowest, highest)
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let (lowest, highest) = axis
        let axis = Axis(lowest: lowest, highest: highest, height: size.height - 8)
        let gutter: CGFloat = 40
        let width = size.width - gutter
        let lowX = gutter + width * 0.3
        let highX = gutter + width * 0.7
        let reach = width * 0.17
        let strongest = (sounding.lowPartials + sounding.highPartials).map(\.strength).max() ?? 1
        let half = { (strength: Float) -> CGFloat in
            reach * CGFloat((strength / max(strongest, 1e-6)).squareRoot())
        }

        // The axis's marks.
        for hz in Self.marks where hz > lowest && hz < highest {
            let y = axis.y(hz) + 4
            var line = Path()
            line.move(to: CGPoint(x: gutter - 4, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(line, with: .color(Color(white: 0.14)), lineWidth: 1)
            context.draw(Text(hz >= 1000 ? "\(Int(hz / 1000))k" : "\(Int(hz))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Color(white: 0.4)),
                         at: CGPoint(x: gutter - 8, y: y), anchor: .trailing)
        }

        // The implied root.
        if let root = sounding.analysis.impliedRoot {
            let y = axis.y(root.hz) + 4
            var line = Path()
            line.move(to: CGPoint(x: gutter, y: y))
            line.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(line, with: .color(Color(white: 0.55)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            context.draw(Text("root \(Self.hz(root.hz))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Color(white: 0.7)),
                         at: CGPoint(x: size.width - 4, y: y - 2), anchor: .bottomTrailing)
        }

        // The pairs that collide, the roughest the thickest, and the
        // roughest few and the spotlighted named by their beat.
        let roughest = sounding.analysis.pairs.first?.roughness ?? 0
        for (rank, pair) in sounding.analysis.pairs.enumerated() {
            let spot = sounding.spotlit.first { $0.pair.low == pair.low && $0.pair.high == pair.high }
            let offset = Double(sounding.highPartials[pair.high - 1].offset)
            let from = CGPoint(x: lowX + half(sounding.lowPartials[pair.low - 1].strength),
                               y: axis.y(pair.lowHz) + 4)
            let to = CGPoint(x: highX - half(sounding.highPartials[pair.high - 1].strength),
                             y: axis.y(pair.highHz + offset) + 4)
            var line = Path()
            line.move(to: from)
            line.addLine(to: to)
            let thickness = 1 + 5 * CGFloat(roughest > 0 ? pair.roughness / roughest : 0)
            context.stroke(line, with: .color(spot != nil ? .orange : Color(white: 0.38)),
                           lineWidth: spot != nil ? thickness + 1.5 : thickness)
            let middle = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 - 3)
            if let spot {
                context.draw(Text(Self.rate(spot.beatRate))
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                                .foregroundStyle(Color.orange),
                             at: middle, anchor: .bottom)
            } else if rank < Self.namedPairs {
                context.draw(Text(Self.rate(pair.beatRate))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Color(white: 0.55)),
                             at: middle, anchor: .bottom)
            }
        }

        // The rungs.
        let spotLow = Set(sounding.spotlit.map(\.pair.low))
        let spotHigh = Set(sounding.spotlit.map(\.pair.high))
        for (index, partial) in sounding.lowPartials.enumerated() {
            rung(&context, x: lowX, y: axis.y(sounding.lowHz * Double(index + 1)) + 4,
                 half: half(partial.strength), number: index + 1, lit: spotLow.contains(index + 1), leading: true)
        }
        for (index, partial) in sounding.highPartials.enumerated() {
            let hz = sounding.highHz * Double(index + 1) + Double(partial.offset)
            rung(&context, x: highX, y: axis.y(hz) + 4, half: half(partial.strength), number: index + 1,
                 lit: spotHigh.contains(index + 1), leading: false)
        }
    }

    private func rung(_ context: inout GraphicsContext, x: CGFloat, y: CGFloat, half: CGFloat, number: Int,
                      lit: Bool, leading: Bool) {
        let bar = Path(roundedRect: CGRect(x: x - max(half, 1.5), y: y - 1.5, width: 2 * max(half, 1.5), height: 3),
                       cornerRadius: 1.5)
        context.fill(bar, with: .color(lit ? .orange : Color(white: 0.8)))
        if number <= 6 || lit {
            context.draw(Text("\(number)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(lit ? Color.orange : Color(white: 0.45)),
                         at: CGPoint(x: leading ? x - half - 6 : x + half + 6, y: y),
                         anchor: leading ? .trailing : .leading)
        }
    }

    // MARK: – Words

    private var accessibilityValue: String {
        guard let spot = sounding.spotlit.first else {
            return "\(sounding.analysis.pairs.count) pairs of partials collide"
        }
        return "\(sounding.analysis.pairs.count) pairs of partials collide. Spotlit: partial \(spot.pair.low) "
            + "of the lower note against partial \(spot.pair.high) of the upper, "
            + (spot.beatRate < LabSounding.beatless ? "not beating" : "beating \(Self.rate(spot.beatRate))")
    }

    static func hz(_ hz: Double) -> String {
        hz >= 100 ? "\(Int(hz.rounded())) Hz" : String(format: "%.1f Hz", hz)
    }

    static func rate(_ rate: Double) -> String {
        rate < LabSounding.beatless ? "0 Hz" : rate < 10 ? String(format: "%.1f Hz", rate) : "\(Int(rate.rounded())) Hz"
    }
}

/// How loud the spotlighted pair is from moment to moment, drawn as it goes
/// by: the wobble of its beat made visible. With motion reduced it stands
/// still.
struct BeatEnvelopeStrip: View {
    let pair: LabPair?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seconds across the strip.
    private static let span = 2.0

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || pair == nil)) { timeline in
            Canvas { context, size in
                draw(in: &context, size: size, at: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Beat envelope")
        .accessibilityValue(pair.map { $0.beatRate < LabSounding.beatless
                                ? "steady, no beat" : "\(PartialLadderView.rate($0.beatRate)) beat" }
                            ?? "nothing spotlit")
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, at now: Double) {
        guard let pair else {
            context.draw(Text("No pair to follow").font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Color(white: 0.4)),
                         at: CGPoint(x: size.width / 2, y: size.height / 2))
            return
        }
        let peak = max(pair.lowStrength + pair.highStrength, 1e-9)
        // Fast beats are drawn slowed, so each is still a wobble on screen.
        let shown = pair.beatRate > 8 ? 8 / pair.beatRate : 1
        var line = Path()
        let steps = max(Int(size.width / 2), 2)
        for step in 0...steps {
            let x = size.width * CGFloat(step) / CGFloat(steps)
            let seconds = (now - Self.span * (1 - Double(step) / Double(steps))) * shown
            let value = pair.envelope(at: seconds) / peak
            let y = size.height - 4 - (size.height - 8) * CGFloat(value)
            if step == 0 { line.move(to: CGPoint(x: x, y: y)) } else { line.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(line, with: .color(.orange), lineWidth: 2)
        if shown < 1 {
            context.draw(Text("slowed ×\(Int((1 / shown).rounded()))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Color(white: 0.5)),
                         at: CGPoint(x: size.width - 4, y: 4), anchor: .topTrailing)
        }
    }
}
