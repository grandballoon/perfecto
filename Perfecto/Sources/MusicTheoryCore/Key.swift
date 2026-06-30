public struct Key: Equatable, Hashable, Sendable {
    public let root: PitchClass
    public let scale: ScaleType

    public init(root: PitchClass, scale: ScaleType) {
        self.root = root
        self.scale = scale
    }
}
