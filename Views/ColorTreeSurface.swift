import SwiftUI

/// The color tree: the compass's steps as branches drawn from the chord
/// held. The root is the chord the tree steps from (the plain chord, or the
/// walk kept); a branch goes out from it to each of the compass's places,
/// its kind's way as on the compass (up adds, right raises, down takes
/// away, left lowers), each kind's two choices side by side. From the
/// branch a finger is on, a step further fans out beyond it: each kind's
/// first choice from that branch's chord. A child that only undoes its
/// branch (a tone added and taken away again) is left out.
///
/// A node is the path of places that reaches it, played as a walk is
/// (`StepCompass.walk`), so a node means the same steps on every degree.
enum ColorTree {
    /// A step further from `branch`: each kind's first choice.
    static func children(of branch: CompassPlace) -> [[CompassPlace]] {
        ColorStepKind.allCases.map { [branch, CompassPlace($0, 1)] }
    }

    /// The steps `path` takes from `origin` on `degree` in `key`, each from
    /// where the last led; nil if a place on it has no choice.
    static func steps(of path: [CompassPlace], from origin: ChordTones, key: Key, degree: Degree,
                      ranking: ColorStepRanking) -> [ColorStep]? {
        var tones = origin
        var steps: [ColorStep] = []
        for place in path {
            guard let step = StepCompass.step(at: place, from: tones, key: key, degree: degree,
                                              ranking: ranking) else { return nil }
            steps.append(step)
            tones = step.tones
        }
        return steps
    }

    /// The nodes there are from `origin`: every branch with a choice, and
    /// from `focus`, every child with one that does not lead back to the
    /// origin.
    static func nodes(from origin: ChordTones, focus: CompassPlace?, key: Key, degree: Degree,
                      ranking: ColorStepRanking) -> [[CompassPlace]] {
        let leads = { (path: [CompassPlace]) -> Bool in
            guard let steps = steps(of: path, from: origin, key: key, degree: degree, ranking: ranking)
            else { return false }
            return steps.last?.tones != origin
        }
        let branches = CompassPlace.all.map { [$0] }.filter(leads)
        guard let focus, branches.contains([focus]) else { return branches }
        return branches + children(of: focus).filter(leads)
    }
}

/// Where the tree's nodes are in a surface of `size`: the root in the
/// middle, the branches on an ellipse around it, and a branch's children
/// fanned out beyond it on the surface's edge. It is worked out from the
/// size alone, so the nodes are drawn and read by the same frames.
struct ColorTreeLayout {
    let size: CGSize

    /// What a finger can be on.
    enum Target: Hashable {
        case root
        case node([CompassPlace])
    }

    /// The angle between a kind's two choices and the way it goes, and
    /// between two children of a branch, in radians.
    static let rankSpread: CGFloat = 0.38
    static let childSpread: CGFloat = 0.32

    /// A node's size: at most 76 by 30 points, smaller in a small surface.
    var nodeSize: CGSize {
        CGSize(width: min(76, size.width * 0.15), height: min(30, size.height * 0.15))
    }

    /// The way a kind goes, in radians clockwise from the top: as on the
    /// compass.
    static func angle(of kind: ColorStepKind) -> CGFloat {
        switch kind {
        case .add:      return 0
        case .raise:    return .pi / 2
        case .takeAway: return .pi
        case .lower:    return 3 * .pi / 2
        }
    }

    /// The angle a branch is at: its kind's way, the first choice turned
    /// back from it and the second on.
    static func angle(of place: CompassPlace) -> CGFloat {
        angle(of: place.kind) + (place.rank == 1 ? -rankSpread : rankSpread)
    }

    /// The frame of `target`.
    func frame(of target: Target) -> CGRect {
        let node = nodeSize
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        switch target {
        case .root:
            return CGRect(x: center.x - node.width * 0.6, y: center.y - node.height / 2,
                          width: node.width * 1.2, height: node.height)
        case .node(let path):
            guard let branch = path.first else { return frame(of: .root) }
            let angle: CGFloat, radii: CGSize
            if path.count == 1 {
                angle = Self.angle(of: branch)
                radii = CGSize(width: size.width * 0.27, height: size.height * 0.3)
            } else {
                let slot = CGFloat(ColorStepKind.allCases.firstIndex(of: path[1].kind) ?? 0)
                angle = Self.angle(of: branch) + (slot - 1.5) * Self.childSpread
                radii = CGSize(width: (size.width - node.width) / 2, height: (size.height - node.height) / 2)
            }
            let x = center.x + radii.width * sin(angle), y = center.y - radii.height * cos(angle)
            return CGRect(x: x - node.width / 2, y: y - node.height / 2, width: node.width, height: node.height)
        }
    }

    /// What is under `point`, of the nodes `shown` and the root: a node drawn
    /// later lies over one drawn earlier, so it is found first. Nil between
    /// them, so a finger sliding across stays on what it was on.
    func target(at point: CGPoint, among shown: [[CompassPlace]]) -> Target? {
        let targets = [Target.root] + shown.map { .node($0) }
        return targets.reversed().first { frame(of: $0).contains(point) }
    }
}

/// The color tree, wired to the live performance. A finger on a node plays
/// the path to it, every step at once, and sliding along a branch to a
/// child walks it a step further. Played, lifting is the plain chord again;
/// kept by the pin, lifting keeps the path, and the tree is drawn from its
/// node next. With a chord held (and the compass's names on) each node is
/// named by the chord it plays; otherwise by what its step does, from I.
/// With a chord held, the key assistance tells apart the nodes whose path
/// leads out of the key, and a finger passes over one that plays nothing
/// as over the space between nodes.
struct ColorTreeSurface: View {
    @Environment(PerformanceState.self) private var state

    /// What the finger on the tree is on, while one is.
    @State private var touched: ColorTreeLayout.Target?
    /// The branch whose children show: the one the finger was last on.
    @State private var focus: CompassPlace?
    /// False once the finger is gone, whether it lifted or was taken away.
    @GestureState private var isDown = false

    private static let controlsHeight: CGFloat = 30

    var body: some View {
        VStack(spacing: 6) {
            tree
            controls
        }
    }

    // MARK: – The tree

    private var tree: some View {
        let degree = state.activeDegree ?? .I
        let named = state.compassShowsChords && state.activeDegree != nil
        let origin = state.compassOrigin(for: degree)
        let key = state.playedKey, ranking = state.compassRanking
        let shown = ColorTree.nodes(from: origin, focus: focus, key: key, degree: degree, ranking: ranking)
        let held = state.heldPath
        return GeometryReader { geo in
            let layout = ColorTreeLayout(size: geo.size)
            ZStack(alignment: .topLeading) {
                branches(shown, held: held, in: layout)
                rootChip(degree: named ? degree : nil, origin: origin)
                    .frame(width: layout.frame(of: .root).width, height: layout.frame(of: .root).height)
                    .offset(x: layout.frame(of: .root).minX, y: layout.frame(of: .root).minY)
                ForEach(shown, id: \.self) { path in
                    let frame = layout.frame(of: .node(path))
                    let steps = ColorTree.steps(of: path, from: origin, key: key, degree: degree, ranking: ranking)
                    // Out of the key if any step on its path is: that is heard on the way.
                    let isInKey: Bool? = state.activeDegree == nil ? nil : steps?.allSatisfy { $0.fit != .borrowed }
                    nodeChip(path, step: steps?.last, degree: named ? degree : nil, isOn: held == path,
                             mark: state.keyAssistance.mark(isInKey: isInKey))
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDown) { _, isDown, _ in isDown = true }
                    .onChanged { drag in
                        guard let target = layout.target(at: drag.location, among: shown),
                              target != touched else { return }
                        if case .node(let path) = target, !state.placesSound(path) { return }
                        touched = target
                        switch target {
                        case .root:
                            state.treeHeld([])
                        case .node(let path):
                            focus = path.first
                            state.treeHeld(path)
                        }
                    }
            )
            .onChange(of: isDown) {
                guard !isDown else { return }
                state.treeLifted()
                touched = nil
                focus = nil
            }
        }
    }

    /// The lines from the root to each branch and from a branch to its
    /// children, the path held lit.
    private func branches(_ shown: [[CompassPlace]], held: [CompassPlace], in layout: ColorTreeLayout) -> some View {
        func middle(_ target: ColorTreeLayout.Target) -> CGPoint {
            let frame = layout.frame(of: target)
            return CGPoint(x: frame.midX, y: frame.midY)
        }
        func line(to path: [CompassPlace]) -> (from: CGPoint, to: CGPoint) {
            (middle(path.count == 1 ? .root : .node(Array(path.dropLast()))), middle(.node(path)))
        }
        let lit = shown.filter { !held.isEmpty && held.starts(with: $0) }
        return ZStack {
            Path { path in
                for node in shown {
                    let (from, to) = line(to: node)
                    path.move(to: from)
                    path.addLine(to: to)
                }
            }
            .stroke(Color(white: 0.25), lineWidth: 1)
            Path { path in
                for node in lit {
                    let (from, to) = line(to: node)
                    path.move(to: from)
                    path.addLine(to: to)
                }
            }
            .stroke(Color.orange, lineWidth: 2)
        }
        .allowsHitTesting(false)
    }

    private func rootChip(degree: Degree?, origin: ChordTones) -> some View {
        let name = degree.map { chordLabel(key: state.playedKey, spec: ChordSpec(degree: $0, color: .tones(origin))) }
        let kept = state.keepsCompassColor && !state.compassWalk.isEmpty
        return CompassChip(text: name ?? (kept ? "kept" : "plain"), detail: kept ? "KEPT" : "AS IT IS",
                           isOn: false, isEnabled: true, isMiddle: true,
                           onTap: { state.treeHeld([]); state.treeLifted() })
            .accessibilityLabel("The chord the tree steps from")
            .accessibilityValue(name ?? "")
    }

    private func nodeChip(_ path: [CompassPlace], step: ColorStep?, degree: Degree?, isOn: Bool,
                          mark: KeyMark) -> some View {
        let text: String
        if let degree, let step {
            text = chordLabel(key: state.playedKey, spec: ChordSpec(degree: degree, color: .tones(step.tones)))
                + mark.suffix(avoid: step.fit == .avoid)
        } else {
            text = step?.editName ?? "—"
        }
        let detail = degree == nil ? "" : step?.editName ?? ""
        return CompassChip(text: text, detail: detail, isOn: isOn, isEnabled: true, mark: mark,
                           onTap: { state.treeHeld(path); state.treeLifted() })
            .accessibilityLabel(path.map { "\($0.kind) \($0.rank)" }.joined(separator: ", then "))
            .accessibilityValue(text)
    }

    // MARK: – Controls

    /// Under the tree: back to the plain chord, the walk kept, and the pin.
    private var controls: some View {
        let keeps = state.keepsCompassColor
        let walk = state.compassWalk
        let degree = state.activeDegree
        let walkText = walk.isEmpty ? "—" : degree.map {
            CompassWalk.steps(walk, key: state.playedKey, degree: $0, ranking: state.compassRanking,
                              assistance: state.keyAssistance)
                .map(\.editName).joined(separator: " · ")
        } ?? "\(walk.count) step\(walk.count == 1 ? "" : "s")"
        return HStack(spacing: 6) {
            CornerChip(text: "clear", detail: "BACK TO PLAIN", isOn: false, isEnabled: keeps && !walk.isEmpty) {
                state.compassCleared()
            }
            .accessibilityLabel("Back to the plain chord")
            CornerChip(text: walkText, detail: "BACK A STEP", isOn: false, isEnabled: keeps && !walk.isEmpty) {
                state.compassStepBack()
            }
            .accessibilityLabel("Back a step along the walk kept")
            .accessibilityValue(walkText)
            CornerChip(text: keeps ? "kept" : "played", detail: "PIN", isOn: keeps, isEnabled: true) {
                state.keepsCompassColor.toggle()
            }
            .accessibilityLabel("Keep the tree's color")
            .accessibilityValue(keeps ? "On" : "Off")
        }
        .frame(height: Self.controlsHeight)
    }
}
