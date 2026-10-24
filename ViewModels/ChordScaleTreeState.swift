import Observation

/// What the tree needs from whatever plays the chords.
@MainActor
protocol ChordScaleTreeHost: AnyObject {
    /// The key the keys are in: the tree starts on its tonic chord.
    var treeKey: Key { get }
    /// The sound the tree's chords are played in.
    var treeSound: NoteSound { get }
}

/// A chord where it is on the board: on a tier, either the chord the tier
/// grows from or a step on from it.
struct TreeSpot: Hashable {
    /// The tier it is on (`ChordScaleTreeState.tiers`).
    let tier: Int
    /// The chord the tier grows from.
    let from: TreeChord
    /// How it is reached from `from`; nil for `from` itself.
    let step: TreeStep?

    var chord: TreeChord { step?.chord ?? from }
}

/// The chord–scale tree, played: it is at one chord (`position`), and can
/// go at once to any chord of any scale that chord is the home chord of
/// (`TreeChord.next`). A chord pressed sounds for as long as it is held and
/// is where the tree is from then on, so a way through it is played as it
/// is found.
///
/// The way is kept as tiers (`tiers`), each a chord and every chord on from
/// it, the next tier growing from the chord pressed on the one before. The
/// tree can be at any of them (`tier`), and moving between them changes
/// nothing of the way; only a chord pressed on a tier, other than the one
/// the next tier grows from, takes a new way on from there.
///
/// It is a line of its own, like the Tonnetz: a sink beside the keys'
/// chord, in the keys' preset with the effects as set, and no mode knows
/// of it. Of the chords held, the one pressed last sounds, and lifting it
/// hands the sound back to the one held beneath, as on the chord keys.
@Observable
@MainActor
final class ChordScaleTreeState {

    /// Whether the tree is on screen (`PerformanceState.deskPane`). Off
    /// it, nothing of its sounds. It comes on at the tonic chord of the
    /// keys' key, unless it has been somewhere since.
    var isShown = false {
        didSet {
            guard isShown != oldValue else { return }
            if !isShown { silence() } else if tiers.count == 1 { goHome() }
        }
    }

    /// The chord each tier grows from, the first where the way started.
    /// There is always one.
    private(set) var tiers = [TreeChord(root: NoteName.roots[0], quality: .major)]
    /// The tier the tree is at.
    private(set) var tier = 0

    /// The chord the tree is at.
    var position: TreeChord { tiers[tier] }

    /// The size of the tree's chords. A change takes the tree, and the way
    /// through it, to the chords of the new size on the same roots.
    var size: ChordSize {
        get { position.quality.size }
        set {
            guard newValue != size else { return }
            tiers = tiers.map { $0.resized(to: newValue) }
            logger?.log(.tree_size_switched(sevenths: newValue == .sevenths))
        }
    }

    /// The chords held, oldest first; the last is sounding.
    private(set) var held: [TreeSpot] = []

    /// A chord under a pointer, shown without being played.
    private(set) var preview: TreeSpot?

    /// What is shown of the tree: the chord under a pointer, else the one
    /// sounding; nil for where the tree is.
    var focusSpot: TreeSpot? { preview ?? held.last }

    /// The chord shown.
    var focus: TreeChord { focusSpot?.chord ?? position }

    @ObservationIgnored weak var host: (any ChordScaleTreeHost)?

    private let sink: (any ChordEventSink)?
    private let logger: (any Logger)?

    /// `sink` sounds the tree's chords; a sink that is a `SoundControl` is
    /// given the host's sound. Without one the tree is silent.
    init(sink: (any ChordEventSink)? = nil, logger: (any Logger)? = nil) {
        self.sink = sink
        self.logger = logger
    }

    // MARK: – Where it is

    /// The chord `tier` grows from, and every chord on from it.
    func spots(on tier: Int) -> (here: TreeSpot, next: [[TreeSpot]]) {
        let from = tiers[tier]
        return (TreeSpot(tier: tier, from: from, step: nil),
                from.next.map { $0.map { TreeSpot(tier: tier, from: from, step: $0) } })
    }

    /// The chord on `tier` that the next tier grows from, if there is one.
    func opened(on tier: Int) -> TreeChord? {
        tiers.indices.contains(tier + 1) ? tiers[tier + 1] : nil
    }

    // MARK: – Playing

    /// A finger came down on `spot`: it sounds, and the tree goes there. A
    /// step on from a tier is the tier after; if it is not the chord that
    /// tier grew from, the way after it is let go of, and a new tier grows
    /// from the step.
    func press(_ spot: TreeSpot) {
        guard isShown, tiers.indices.contains(spot.tier), tiers[spot.tier] == spot.from else { return }
        held.append(spot)
        if spot.step == nil {
            show(tier: spot.tier)
        } else {
            if opened(on: spot.tier) != spot.chord {
                tiers = Array(tiers.prefix(spot.tier + 1)) + [spot.chord]
            }
            show(tier: spot.tier + 1)
        }
        sound(spot.chord)
    }

    /// A finger on `spot` lifted. Of the chords still held, the last is
    /// heard again if this one was sounding; the tree stays where it is.
    func release(_ spot: TreeSpot) {
        guard let index = held.lastIndex(of: spot) else { return }
        let wasSounding = index == held.count - 1
        held.remove(at: index)
        guard wasSounding else { return }
        if let beneath = held.last { sound(beneath.chord) } else { sink?.stopChord() }
    }

    /// Goes to `tier`, keeping every tier there is.
    func show(tier: Int) {
        guard tiers.indices.contains(tier), tier != self.tier else { return }
        self.tier = tier
        logger?.log(.tree_moved(to: position.label))
    }

    /// Goes to the tonic chord of the keys' key, letting go of the way.
    func goHome() {
        guard let host else { return }
        tiers = [TreeChord.home(of: host.treeKey, size: size)]
        tier = 0
    }

    /// A pointer is over `spot`, which is shown; nil, over none.
    func hover(_ spot: TreeSpot?) {
        if preview != spot { preview = spot }
    }

    // MARK: – Sound

    /// The notes of `chord`: its root in the octave from C3, and the other
    /// notes up from it, each as far above it as its interval.
    static func notes(of chord: TreeChord) -> [Int] {
        let root = lowestRoot + chord.root.pitchClass.rawValue
        return chord.quality.intervals.map { root + $0 }
    }

    static let lowestRoot = 48

    /// Sounds `chord` in place of what the tree is sounding.
    private func sound(_ chord: TreeChord) {
        guard let host else { return }
        (sink as? any SoundControl)?.startNotes(in: host.treeSound)
        let context = ChordContext(key: Key(root: chord.root.pitchClass, scale: .major),
                                   spec: ChordSpec(degree: .I, color: .base),
                                   octave: Self.lowestRoot / 12 - 1, inversion: .root, voiceLeading: false)
        sink?.playChord(ChordEvent(voicing: Voicing(notes: Self.notes(of: chord)), articulation: .block,
                                   context: context))
    }

    /// Ends whatever of the tree's is sounding.
    private func silence() {
        held = []
        preview = nil
        sink?.stopChord()
    }
}
