import SwiftUI
import UIKit

extension QualityGroup {
    /// The color a chord of the group is marked with. A chord is always
    /// named as well, so the color is never all there is to go by.
    var color: Color {
        switch self {
        case .major:      return Color(red: 0.89, green: 0.66, blue: 0.31)
        case .minor:      return Color(red: 0.43, green: 0.65, blue: 0.86)
        case .diminished: return Color(red: 0.75, green: 0.54, blue: 0.84)
        case .augmented:  return Color(red: 0.48, green: 0.78, blue: 0.54)
        }
    }
}

/// How the tree is laid out in the room it is given.
enum TreeArrangement: Equatable {
    /// The readout over the board: a phone held upright.
    case stacked
    /// The readout beside the board: a phone on its side.
    case beside
    /// The readout and the keyboard side by side over the board: a desk.
    case wide

    /// The least room the desk's arrangement is used in.
    static let wideSize = CGSize(width: 640, height: 520)

    static func of(_ size: CGSize) -> TreeArrangement {
        if size.width >= wideSize.width && size.height >= wideSize.height { return .wide }
        return size.width > size.height ? .beside : .stacked
    }
}

/// Where the tree's chords are on a board of a given size, and which chord
/// a point is on. The one place that says so: the board draws its chords
/// here and reads its fingers against the same frames.
///
/// The chord the tree is at is at the top, and a trunk runs down from it
/// to a branch for each letter its next chords' roots can be above its own,
/// a letter up first. A branch's chords are side by side along it, from the
/// lowest root, in columns as wide as one another for every branch.
struct TreeBranches {
    static let gap: CGFloat = 8
    /// How far in from the leading edge the trunk is.
    static let trunk: CGFloat = 16
    static let labelWidth: CGFloat = 36
    /// The largest a chord is drawn, however much room there is.
    static let largest = CGSize(width: 132, height: 64)
    /// How far in from the leading edge the chords on the branches start.
    static let start = trunk + gap + labelWidth + gap

    let position: TreeChord
    let next: [[TreeStep]]
    let here: CGRect
    /// Each branch's label, the step it is ("II").
    let labels: [CGRect]
    let steps: [[CGRect]]

    init(size: CGSize, position: TreeChord) {
        let next = position.next
        self.position = position
        self.next = next
        let rows = CGFloat(next.count + 1)
        let height = max(min((size.height - Self.gap * (rows - 1)) / rows, Self.largest.height), 0)
        here = CGRect(x: 0, y: 0, width: min(max(size.width * 0.4, 140), 240), height: height)
        let start = Self.start
        let columns = CGFloat(max(next.map(\.count).max() ?? 1, 1))
        let width = max(min((size.width - start - Self.gap * (columns - 1)) / columns, Self.largest.width), 0)
        labels = next.indices.map { row in
            CGRect(x: Self.trunk + Self.gap, y: (height + Self.gap) * CGFloat(row + 1),
                   width: Self.labelWidth, height: height)
        }
        steps = next.indices.map { row in
            next[row].indices.map { column in
                CGRect(x: start + (width + Self.gap) * CGFloat(column), y: (height + Self.gap) * CGFloat(row + 1),
                       width: width, height: height)
            }
        }
    }

    /// The chord at `point`, if it is on one, as a spot on `tier`.
    func spot(at point: CGPoint, tier: Int) -> TreeSpot? {
        if here.contains(point) { return TreeSpot(tier: tier, from: position, step: nil) }
        for (row, frames) in steps.enumerated() {
            if let column = frames.firstIndex(where: { $0.contains(point) }) {
                return TreeSpot(tier: tier, from: position, step: next[row][column])
            }
        }
        return nil
    }

    /// The trunk and its branches: down from the chord at the top, and
    /// along each branch under its chords.
    var lines: Path {
        var path = Path()
        guard let last = labels.last else { return path }
        path.move(to: CGPoint(x: Self.trunk, y: here.maxY))
        path.addLine(to: CGPoint(x: Self.trunk, y: last.midY))
        for (row, label) in labels.enumerated() {
            path.move(to: CGPoint(x: Self.trunk, y: label.midY))
            path.addLine(to: CGPoint(x: steps[row].last?.maxX ?? label.maxX, y: label.midY))
        }
        return path
    }
}

/// Where the tree's tiers are on a board of a given size, scrolled along it
/// by a given distance (`scrolled`, 0 with the first tier at the leading
/// edge), and where scrolling comes to rest. The one place that says so:
/// the board draws its tiers here and reads its fingers against the same
/// frames.
///
/// The tiers are side by side, each as wide as the board up to `widest`,
/// so a phone shows one at a time and a desk more.
struct TreeTiers {
    /// Between one tier and the next.
    static let gap: CGFloat = 24
    /// The widest a tier is drawn: a branch of six of the largest chords.
    static let widest = TreeBranches.start + 6 * TreeBranches.largest.width + 5 * TreeBranches.gap
    /// How fast a lifted finger must be moving, in points a second, for
    /// scrolling to go on to the next place to rest in its direction.
    static let flick: CGFloat = 400

    let size: CGSize
    let count: Int

    var width: CGFloat { min(size.width, Self.widest) }
    var tierSize: CGSize { CGSize(width: width, height: size.height) }
    private var stride: CGFloat { width + Self.gap }

    /// The farthest the board scrolls: the last tier at its trailing edge.
    var farthest: CGFloat { max(CGFloat(count) * stride - Self.gap - size.width, 0) }

    /// Where `tier` starts, unscrolled.
    func minX(of tier: Int) -> CGFloat { CGFloat(tier) * stride }

    /// Where scrolling comes to rest: a tier at the leading edge, or the
    /// last at the trailing, the nearest first.
    var stops: [CGFloat] {
        var stops: [CGFloat] = []
        for tier in 0..<max(count, 1) {
            let stop = min(minX(of: tier), farthest)
            if stops.last != stop { stops.append(stop) }
        }
        return stops
    }

    /// The tier at `point` of the board, and the point within it.
    func tier(at point: CGPoint, scrolled: CGFloat) -> (tier: Int, point: CGPoint)? {
        let x = point.x + scrolled
        let tier = Int((x / stride).rounded(.down))
        let within = CGPoint(x: x - minX(of: tier), y: point.y)
        guard (0..<count).contains(tier), within.x <= width else { return nil }
        return (tier, within)
    }

    /// Whether all of `tier` is on the board.
    func isWhole(_ tier: Int, scrolled: CGFloat) -> Bool {
        let minX = minX(of: tier) - scrolled
        return minX >= -0.5 && minX + width <= size.width + 0.5
    }

    /// Where scrolling at `scrolled`, moving `velocity` points a second
    /// along, comes to rest: the next stop in its direction if it is moving
    /// fast, else the nearest.
    func settled(_ scrolled: CGFloat, velocity: CGFloat) -> CGFloat {
        let stops = stops
        if velocity > Self.flick, let next = stops.first(where: { $0 > scrolled + 0.5 }) { return next }
        if velocity < -Self.flick, let next = stops.last(where: { $0 < scrolled - 0.5 }) { return next }
        return stops.min { abs($0 - scrolled) < abs($1 - scrolled) } ?? 0
    }

    /// Where to scroll from `scrolled` so that all of `tier` is on the
    /// board, moving as little as there is to.
    func revealing(_ tier: Int, from scrolled: CGFloat) -> CGFloat {
        let scrolled = min(max(scrolled, 0), farthest)
        if isWhole(tier, scrolled: scrolled) && stops.contains(scrolled) { return scrolled }
        let stops = stops.filter { isWhole(tier, scrolled: $0) }
        return stops.min { abs($0 - scrolled) < abs($1 - scrolled) } ?? min(minX(of: tier), farthest)
    }

    /// Of the tiers all on the board at `scrolled`, the nearest to `tier`.
    func nearestWhole(to tier: Int, scrolled: CGFloat) -> Int {
        let whole = (0..<count).filter { isWhole($0, scrolled: scrolled) }
        return whole.min { abs($0 - tier) < abs($1 - tier) } ?? tier
    }
}

/// The chord–scale tree, wired to the live performance (`ChordScaleTreeState`):
/// the chord it is at and every chord it can go to, played by pressing
/// them, with what is in focus shown over them, its notes on a keyboard.
struct ChordScaleTreeView: View {
    @Environment(PerformanceState.self) private var state

    /// Whether the tree's controls are its first row. A phone on its side
    /// has them in the screen's own row.
    var showsControls = true

    var body: some View {
        let tree = state.tree
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 12) {
                if showsControls { TreeControls() }
                switch TreeArrangement.of(geo.size) {
                case .stacked:
                    TreeCard {
                        TreeReadout(tree: tree)
                        TreeKeyboard(chord: tree.focus)
                    }
                    TreeTrail(tree: tree)
                    TreeBoard(tree: tree)
                case .beside:
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            TreeCard {
                                TreeReadout(tree: tree)
                                TreeKeyboard(chord: tree.focus)
                            }
                            TreeTrail(tree: tree)
                        }
                        .frame(width: geo.size.width * 0.4)
                        TreeBoard(tree: tree)
                    }
                case .wide:
                    TreeCard {
                        HStack(alignment: .center, spacing: 24) {
                            TreeReadout(tree: tree)
                                .frame(maxWidth: .infinity)
                            TreeKeyboard(chord: tree.focus)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    TreeTrail(tree: tree)
                    TreeBoard(tree: tree)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }
}

/// The tree's controls: the size of its chords, and a way home to the
/// tonic chord of the keys' key.
struct TreeControls: View {
    @Environment(PerformanceState.self) private var state

    var body: some View {
        @Bindable var tree = state.tree
        HStack(spacing: 10) {
            SegmentedToggle(choices: ChordSize.allCases, label: { $0.displayName.uppercased() },
                            hotkey: { _ in nil }, selection: $tree.size)
            TreeChit(label: "HOME") { tree.goHome() }
                .frame(width: 76)
        }
    }
}

/// A button as the screen's chits are drawn.
private struct TreeChit: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(white: 0.85))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(white: 0.13))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(white: 0.25), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }
}

/// The panel the readout and the keyboard are on, as the note display is
/// drawn.
private struct TreeCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(white: 0.05))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(white: 0.15), lineWidth: 1))
            )
    }
}

// MARK: – The readout

/// What is in focus: its name, how it is reached from where the tree is
/// and in which scales, and its notes.
private struct TreeReadout: View {
    let tree: ChordScaleTreeState

    var body: some View {
        let chord = tree.focus
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(chord.label)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color(white: 0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(chord.quality.displayName)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.6))
                    .lineLimit(1)
            }
            Text(way)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(white: 0.55))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(Array(chord.tones.enumerated()), id: \.offset) { index, tone in
                    Text(tone.name)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(index == 0 ? Color.black : Color(white: 0.85))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6)
                            .fill(index == 0 ? Color.orange : Color(white: 0.13)))
                }
            }
        }
    }

    /// How the chord in focus is reached: "ii of C · in C Ionian,
    /// Mixolydian", or for the chord a tier grows from, the scales it is at
    /// home in.
    private var way: String {
        let chord = tree.focus
        guard let spot = tree.focusSpot, let step = spot.step else {
            return "Here · home chord of \(chord.scales.count) scale\(chord.scales.count == 1 ? "" : "s")"
        }
        return "\(step.numeral) of \(spot.from.label) · in \(spot.from.root.asRoot.name) "
            + step.scales.map(\.displayName).joined(separator: ", ")
    }
}

// MARK: – The keyboard

/// Two octaves of keys from C3, with the notes of what is in focus lit and
/// named as they sound, its root the strongest.
private struct TreeKeyboard: View {
    let chord: TreeChord

    private static let lowest = ChordScaleTreeState.lowestRoot
    private static let octaves = 2
    /// The keyboard's width to its height.
    private static let proportions: CGFloat = 14 / 3.2
    private static let soft = Color(red: 1, green: 0.78, blue: 0.5)

    var body: some View {
        GeometryReader { geo in
            let keys = PianoKeys(size: geo.size,
                                 span: PianoSpan(start: Double(PianoKeys.whitesBelow(Self.lowest)),
                                                 count: Double(7 * Self.octaves)))
            let notes = Self.lowest..<(Self.lowest + 12 * Self.octaves)
            let lit = lights
            ZStack(alignment: .topLeading) {
                ForEach(notes.filter { !PianoKeys.isBlack($0) }, id: \.self) { key($0, in: keys, lit: lit[$0]) }
                ForEach(notes.filter(PianoKeys.isBlack), id: \.self) { key($0, in: keys, lit: lit[$0]) }
            }
        }
        .aspectRatio(Self.proportions, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    /// Each note of the chord, by its key, with its name and whether it is
    /// the root.
    private var lights: [Int: (name: String, isRoot: Bool)] {
        var lights: [Int: (name: String, isRoot: Bool)] = [:]
        for (index, (note, tone)) in zip(ChordScaleTreeState.notes(of: chord), chord.tones).enumerated() {
            lights[note] = (tone.name, index == 0)
        }
        return lights
    }

    private func key(_ note: Int, in keys: PianoKeys, lit: (name: String, isRoot: Bool)?) -> some View {
        let isBlack = PianoKeys.isBlack(note)
        let frame = keys.frame(of: note)
        let fill: Color = switch lit {
        case nil:      Color(white: isBlack ? 0.08 : 0.92)
        case let lit?: lit.isRoot ? .orange : Self.soft
        }
        return fill
            .overlay(alignment: .bottom) {
                if let lit {
                    Text(lit.name)
                        .font(.system(size: (frame.width * (isBlack ? 0.5 : 0.36)).clamped(to: 7...12),
                                      weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.black.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.bottom, 4)
                }
            }
            .border(Color.black, width: 0.5)
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
    }
}

// MARK: – The way through

/// The chord each tier grows from, the first first, each a way to its
/// tier; the tier the tree is at is lit, and the tiers past it are kept.
private struct TreeTrail: View {
    let tree: ChordScaleTreeState

    var body: some View {
        let tiers = tree.tiers
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(tiers.enumerated()), id: \.offset) { index, chord in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color(white: 0.4))
                        }
                        Button { tree.show(tier: index) } label: {
                            crumb(chord.label, isHere: index == tree.tier, isAhead: index > tree.tier)
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
            }
            .onChange(of: tree.tier) { proxy.scrollTo(tree.tier) }
            .onChange(of: tiers.count) { proxy.scrollTo(tree.tier) }
            .onAppear { proxy.scrollTo(tree.tier) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func crumb(_ label: String, isHere: Bool, isAhead: Bool) -> some View {
        Text(label)
            .font(.system(size: 12, weight: isHere ? .semibold : .regular, design: .monospaced))
            .foregroundStyle(isHere ? Color.orange : Color(white: isAhead ? 0.5 : 0.75))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.09)))
    }
}

// MARK: – The board

/// The tiers of the tree side by side (`TreeTiers`), scrolled along by a
/// finger that comes down off the chords, or a trackpad or a wheel; it
/// comes to rest with a tier at its edge. A chord on any tier is played by
/// pressing it, and the board scrolls to show the tier the tree goes to.
private struct TreeBoard: View {
    let tree: ChordScaleTreeState

    @State private var scrolled: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let tiers = TreeTiers(size: geo.size, count: tree.tiers.count)
            ZStack(alignment: .topLeading) {
                ForEach(tree.tiers.indices, id: \.self) { index in
                    TreeTier(tree: tree, tier: index, from: tree.tiers[index], size: tiers.tierSize)
                        .frame(width: tiers.width, height: geo.size.height)
                        .offset(x: tiers.minX(of: index) - scrolled)
                }
                TreeTouchLayer(tiers: tiers, scrolled: scrolled, tree: tree,
                               scroll: { scroll(to: $0, in: tiers) },
                               settle: { settle(velocity: $0, in: tiers) })
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
            .onAppear { reveal(in: tiers, animated: false) }
            .onChange(of: tree.tier) { reveal(in: tiers, animated: true) }
            .onChange(of: tree.tiers.count) { reveal(in: tiers, animated: true) }
            .onChange(of: geo.size) { reveal(in: tiers, animated: false) }
        }
    }

    /// Follows a finger, as it moves.
    private func scroll(to scrolled: CGFloat, in tiers: TreeTiers) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { self.scrolled = min(max(scrolled, 0), tiers.farthest) }
    }

    /// Comes to rest once the finger lifts, at the tier nearest the one the
    /// tree is at, if that one has gone from view.
    private func settle(velocity: CGFloat, in tiers: TreeTiers) {
        let resting = tiers.settled(scrolled, velocity: velocity)
        withAnimation(Self.motion) { scrolled = resting }
        tree.show(tier: tiers.nearestWhole(to: tree.tier, scrolled: resting))
    }

    /// Brings the tier the tree is at into view.
    private func reveal(in tiers: TreeTiers, animated: Bool) {
        let shown = tiers.revealing(tree.tier, from: scrolled)
        guard shown != scrolled else { return }
        withAnimation(animated ? Self.motion : nil) { scrolled = shown }
    }

    private static let motion = Animation.easeOut(duration: 0.25)
}

/// One tier: the chord it grows from at the top, and the branches of
/// chords on from it (`TreeBranches`), the one the next tier grows from
/// marked. When a new way is taken from the tier before, the branches grow
/// again around its chord.
private struct TreeTier: View {
    let tree: ChordScaleTreeState
    let tier: Int
    let from: TreeChord
    let size: CGSize

    private static let numerals = ["II", "III", "IV", "V", "VI", "VII"]

    var body: some View {
        let branches = TreeBranches(size: size, position: from)
        let sounding = tree.held.last
        let here = TreeSpot(tier: tier, from: from, step: nil)
        let opened = tree.opened(on: tier)
        ZStack(alignment: .topLeading) {
            branches.lines
                .stroke(Color(white: 0.22), lineWidth: 1.5)
            TreeHere(chord: from, scales: from.scales.count,
                     isSounding: sounding == here || grew(from: sounding),
                     isAt: tier == tree.tier)
                .frame(width: branches.here.width, height: branches.here.height)
                .offset(x: branches.here.minX, y: branches.here.minY)
            ForEach(branches.labels.indices, id: \.self) { row in
                let frame = branches.labels[row]
                Text(Self.numerals[row])
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(white: 0.55))
                    .frame(width: frame.width, height: frame.height)
                    .background(Color.black)
                    .offset(x: frame.minX, y: frame.minY)
            }
            ForEach(branches.next.indices, id: \.self) { row in
                ForEach(Array(branches.next[row].enumerated()), id: \.element.chord) { column, step in
                    let frame = branches.steps[row][column]
                    let spot = TreeSpot(tier: tier, from: from, step: step)
                    TreeLeaf(step: step, isSounding: sounding == spot, isPreviewed: tree.preview == spot,
                             isOpened: opened == step.chord)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .transition(.opacity)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .animation(.easeOut(duration: 0.18), value: from)
    }

    /// Whether `sounding` is the step on the tier before that this tier
    /// grew from: the same chord, played from there.
    private func grew(from sounding: TreeSpot?) -> Bool {
        guard let sounding, sounding.step != nil else { return false }
        return sounding.tier == tier - 1 && sounding.chord == from
    }
}

/// The chord a tier grows from: outlined on the tier the tree is at, and
/// lit while it sounds.
private struct TreeHere: View {
    let chord: TreeChord
    let scales: Int
    let isSounding: Bool
    let isAt: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(chord.quality.group.color)
                .overlay(Circle().strokeBorder(Color.black.opacity(isSounding ? 0.6 : 0), lineWidth: 1))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 1) {
                Text(chord.label)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("I · \(scales) scale\(scales == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .opacity(0.7)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(isSounding ? Color.black : Color(white: 0.95))
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(isSounding ? Color.orange : Color(white: 0.13)))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(isAt ? Color.orange : Color(white: 0.3), lineWidth: isAt ? 1.5 : 1))
    }
}

/// A chord the tree can go to: its name and numeral, marked along its top
/// in its group's color, raised if the next tier grows from it, and lit
/// while it sounds.
private struct TreeLeaf: View {
    let step: TreeStep
    let isSounding: Bool
    let isPreviewed: Bool
    let isOpened: Bool

    private static let corner: CGFloat = 8

    var body: some View {
        VStack(spacing: 2) {
            Text(step.chord.label)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(step.numeral)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .opacity(0.7)
        }
        .padding(.horizontal, 3)
        .foregroundStyle(isSounding ? Color.black : Color(white: 0.9))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: Self.corner)
            .fill(isSounding ? Color.orange : Color(white: isOpened ? 0.2 : 0.09)))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: Self.corner, topTrailingRadius: Self.corner)
                .fill(step.chord.quality.group.color)
                .frame(height: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.corner))
        .overlay(
            RoundedRectangle(cornerRadius: Self.corner)
                .strokeBorder(isSounding || isPreviewed ? Color.orange : Color(white: isOpened ? 0.6 : 0.25),
                              lineWidth: isPreviewed && !isSounding ? 1.5 : 1)
        )
    }
}

// MARK: – Touches

private struct TreeTouchLayer: UIViewRepresentable {
    let tiers: TreeTiers
    let scrolled: CGFloat
    let tree: ChordScaleTreeState
    let scroll: (CGFloat) -> Void
    let settle: (CGFloat) -> Void

    func makeUIView(context: Context) -> TreeTouchView {
        let view = TreeTouchView()
        view.isMultipleTouchEnabled = true
        return view
    }

    func updateUIView(_ view: TreeTouchView, context: Context) {
        view.tiers = tiers
        view.scrolled = scrolled
        view.tree = tree
        view.scroll = scroll
        view.settle = settle
    }
}

/// Receives the board's raw touches and plays the chords by them. A
/// finger plays the chord it came down on until it lifts, wherever it
/// goes and however the board moves under it meanwhile; a finger that
/// comes down off the chords scrolls the board, as do a trackpad and a
/// wheel. A cancelled touch, or the view leaving the screen, ends its
/// chord, so one can never be left sounding. A pointer over a chord shows
/// it.
private final class TreeTouchView: UIView {
    var tiers: TreeTiers?
    var scrolled: CGFloat = 0
    weak var tree: ChordScaleTreeState?
    /// Asks for the board to be scrolled this far along.
    var scroll: ((CGFloat) -> Void)?
    /// Asks for it to come to rest, moving this fast along it.
    var settle: ((CGFloat) -> Void)?

    private var pressed: [ObjectIdentifier: TreeSpot] = [:]
    /// The finger scrolling, where it came down and how far the board was
    /// scrolled then, and where it was last and when.
    private var dragging: (touch: ObjectIdentifier, startX: CGFloat, startScrolled: CGFloat,
                           lastX: CGFloat, lastTime: TimeInterval, velocity: CGFloat)?
    private var wheelStart: CGFloat = 0
    private let haptic = UIImpactFeedbackGenerator(style: .light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hovered)))
        let wheel = UIPanGestureRecognizer(target: self, action: #selector(wheeled))
        wheel.allowedScrollTypesMask = .all
        wheel.allowedTouchTypes = []
        addGestureRecognizer(wheel)
    }

    required init?(coder: NSCoder) { fatalError("not from a nib") }

    private func spot(at point: CGPoint) -> TreeSpot? {
        guard let tiers, let tree, let found = tiers.tier(at: point, scrolled: scrolled),
              tree.tiers.indices.contains(found.tier) else { return nil }
        return TreeBranches(size: tiers.tierSize, position: tree.tiers[found.tier])
            .spot(at: found.point, tier: found.tier)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let point = touch.location(in: self)
            if let spot = spot(at: point) {
                pressed[ObjectIdentifier(touch)] = spot
                haptic.impactOccurred()
                tree?.press(spot)
            } else if dragging == nil {
                dragging = (ObjectIdentifier(touch), point.x, scrolled, point.x, touch.timestamp, 0)
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard var drag = dragging, let touch = touches.first(where: { ObjectIdentifier($0) == drag.touch })
        else { return }
        let x = touch.location(in: self).x
        let elapsed = touch.timestamp - drag.lastTime
        if elapsed > 0 { drag.velocity = (drag.lastX - x) / CGFloat(elapsed) }
        (drag.lastX, drag.lastTime) = (x, touch.timestamp)
        dragging = drag
        scroll?(drag.startScrolled - (x - drag.startX))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        guard newWindow == nil else { return }
        pressed.values.forEach { tree?.release($0) }
        pressed = [:]
        dragging = nil
    }

    private func lift(_ touches: Set<UITouch>) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            if let spot = pressed.removeValue(forKey: id) { tree?.release(spot) }
            if let drag = dragging, drag.touch == id {
                dragging = nil
                // A finger that stopped before lifting has no speed left.
                settle?(touch.timestamp - drag.lastTime > 0.1 ? 0 : drag.velocity)
            }
        }
    }

    /// A trackpad's or a wheel's scrolling, along or up and down alike.
    @objc private func wheeled(_ recognizer: UIPanGestureRecognizer) {
        let along = { (point: CGPoint) in abs(point.x) >= abs(point.y) ? point.x : point.y }
        switch recognizer.state {
        case .began:
            wheelStart = scrolled
        case .changed:
            scroll?(wheelStart - along(recognizer.translation(in: self)))
        case .ended, .cancelled:
            settle?(-along(recognizer.velocity(in: self)))
        default:
            break
        }
    }

    @objc private func hovered(_ recognizer: UIHoverGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed: tree?.hover(spot(at: recognizer.location(in: self)))
        default:               tree?.hover(nil)
        }
    }
}
