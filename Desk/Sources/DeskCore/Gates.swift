// The controller's analog surfaces read as choices: a stick as a pie of
// targets and rings of radius, a trigger as a strike or as steps. Every one
// holds on to what it chose a little past its edges, so a resting thumb or
// finger cannot flicker between two.

/// A stick read as a pie: targets at bearings round the middle, the one the
/// stick leans towards chosen.
public struct PieGate: Equatable, Sendable {
    /// Each target's bearing, degrees clockwise from up.
    public let bearings: [Double]
    /// How far either side of its bearing a target reaches, in degrees.
    /// Past every target's reach is a gap, which chooses nothing.
    public let width: Double

    /// How far out the stick has to lean to choose, of its whole reach, and
    /// how far in it comes before it lets go.
    public static let reach = 0.5
    public static let rest = 0.35
    /// How far past the line between two targets the stick has to turn to
    /// leave the one it is on, in degrees.
    public static let hold = 6.0

    public init(bearings: [Double], width: Double? = nil) {
        self.bearings = bearings
        self.width = width ?? (bearings.count > 1 ? 180 : 360)
    }

    /// `count` targets evenly round the whole circle, the first at `first`.
    public static func even(_ count: Int, first: Double = 0) -> PieGate {
        let step = 360 / Double(count)
        // A little past half a step, so no bearing falls between two targets.
        return PieGate(bearings: (0..<count).map { first + Double($0) * step }, width: step / 2 + 1)
    }

    /// The target `stick` chooses, given the one it was on; nil in the
    /// middle or in a gap.
    public func select(_ stick: Stick, from last: Int?) -> Int? {
        guard !bearings.isEmpty, stick.radius >= (last == nil ? Self.reach : Self.rest) else { return nil }
        let bearing = stick.bearing
        if let last, bearings.indices.contains(last),
           Self.turn(bearings[last], bearing) <= sideOf(last) + Self.hold {
            return last
        }
        let nearest = bearings.indices.min { Self.turn(bearings[$0], bearing) < Self.turn(bearings[$1], bearing) }!
        return Self.turn(bearings[nearest], bearing) <= width ? nearest : nil
    }

    /// How far a target reaches before the next one's is nearer.
    private func sideOf(_ index: Int) -> Double {
        let others = bearings.indices.filter { $0 != index }.map { Self.turn(bearings[index], bearings[$0]) }
        return min(width, (others.min() ?? 360) / 2)
    }

    /// Degrees between two bearings, the short way round.
    static func turn(_ a: Double, _ b: Double) -> Double {
        let difference = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }
}

/// A stick's radius read as rings: ring 0 from `PieGate.reach` out to the
/// first edge, and so on outwards.
public struct RadialBands: Equatable, Sendable {
    /// Where each ring after the first starts.
    public let edges: [Double]
    /// How far back over an edge the stick has to come to leave a ring.
    public static let hold = 0.06

    public init(edges: [Double]) {
        self.edges = edges
    }

    /// Three rings: as many as a moving thumb holds on a 360's stick.
    public static let three = RadialBands(edges: [0.72, 0.9])
    /// Two: inside and out.
    public static let two = RadialBands(edges: [0.86])

    public var count: Int { edges.count + 1 }

    public func band(_ radius: Double, from last: Int?) -> Int {
        let plain = edges.filter { radius >= $0 }.count
        guard let last else { return plain }
        // Kept while the radius is within the hold of the ring it was in.
        let low = last == 0 ? 0 : edges[last - 1] - Self.hold
        let high = last >= edges.count ? .infinity : edges[last] + Self.hold
        return radius >= low && radius < high ? last : plain
    }
}

/// The right trigger as a strike: it sounds as it crosses a threshold,
/// with a level from how fast it was pulled, its depth afterwards is a
/// continuous control, and it lets go below a lower threshold.
public struct TriggerStrike: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        case strike(level: Double)
        case depth(Double)
        case release
    }

    /// Pulled past this, it sounds.
    public static let threshold = 0.08
    /// Let back past this, it lets go.
    public static let letGo = 0.05
    /// How long after crossing the threshold the level is read: a pull that
    /// gets further in that time is faster, and louder.
    public static let window = 0.016
    /// The softest strike, and how far a pull has to get in the window for
    /// the loudest.
    public static let softest = 0.3
    public static let fullPull = 0.6

    private enum Phase: Equatable, Sendable {
        case resting
        case crossing(since: Double)
        case held
    }

    private var phase = Phase.resting

    public init() {}

    public var isHeld: Bool { phase == .held }

    public mutating func step(_ value: Double, at time: Double) -> [Event] {
        switch phase {
        case .resting:
            guard value >= Self.threshold else { return [] }
            phase = .crossing(since: time)
            return value >= 0.95 ? strike(value) : []
        case .crossing(let since):
            if value < Self.letGo {
                phase = .resting
                return []
            }
            return time - since >= Self.window || value >= 0.95 ? strike(value) : []
        case .held:
            if value < Self.letGo {
                phase = .resting
                return [.release]
            }
            return [.depth(value)]
        }
    }

    private mutating func strike(_ value: Double) -> [Event] {
        phase = .held
        let speed = min(1, max(0, (value - Self.threshold) / Self.fullPull))
        return [.strike(level: Self.softest + (1 - Self.softest) * speed), .depth(value)]
    }
}

/// A trigger read as steps: 0 at rest, then 1, 2, … as it is pulled past
/// each edge.
public struct TriggerSteps: Equatable, Sendable {
    public let edges: [Double]
    public static let hold = 0.05

    public init(edges: [Double]) {
        self.edges = edges
    }

    /// Off and three steps.
    public static let three = TriggerSteps(edges: [0.15, 0.45, 0.78])

    public var count: Int { edges.count + 1 }

    public func step(_ value: Double, from last: Int) -> Int {
        let plain = edges.filter { value >= $0 }.count
        let low = last == 0 ? -Double.infinity : edges[last - 1] - Self.hold
        let high = last >= edges.count ? .infinity : edges[last] + Self.hold
        return value >= low && value < high ? last : plain
    }
}

/// A stick leaned and let go, read in time: a flick (out and back quickly)
/// keeps what it pointed at; a lean held is played while it is held.
public struct StickGesture: Equatable, Sendable {
    public enum Event: Equatable, Sendable {
        /// The stick points at a target (each time it changes).
        case aim(Int)
        /// Out and back within `flickTime`: keep `target`.
        case flick(Int)
        /// Back to the middle after a lean held: let go of `target`.
        case lift(Int)
    }

    /// Out and back within this many seconds is a flick.
    public static let flickTime = 0.2

    public private(set) var target: Int?
    private var since: Double = 0

    public init() {}

    public var isAiming: Bool { target != nil }

    public mutating func step(_ stick: Stick, gate: PieGate, at time: Double) -> [Event] {
        let next = gate.select(stick, from: target)
        guard next != target else { return [] }
        defer { target = next }
        switch (target, next) {
        case (nil, let next?):
            since = time
            return [.aim(next)]
        case (let last?, nil):
            return time - since <= Self.flickTime ? [.flick(last)] : [.lift(last)]
        case (_, let next?):
            return [.aim(next)]
        case (nil, nil):
            return []
        }
    }

    /// Forgets the lean, as if the stick were at rest: what it was on is let
    /// go of without being kept.
    public mutating func reset() {
        target = nil
    }
}

/// A button told apart by how long it is held: let go quickly with nothing
/// else done meanwhile, it was tapped.
public struct TapOrHold: Equatable, Sendable {
    public static let tapTime = 0.35

    private var pressedAt: Double?
    private var wasUsed = false

    public init() {}

    /// The button went down at `time`.
    public mutating func press(at time: Double) {
        pressedAt = time
        wasUsed = false
    }

    /// Something was done while it was held, so letting it go is no tap.
    public mutating func use() {
        wasUsed = true
    }

    /// The button came up at `time`: whether that was a tap.
    public mutating func release(at time: Double) -> Bool {
        defer { pressedAt = nil }
        guard let pressedAt else { return false }
        return !wasUsed && time - pressedAt <= Self.tapTime
    }
}
