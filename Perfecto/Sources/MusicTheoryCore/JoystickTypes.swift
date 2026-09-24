public enum JoystickMode: CaseIterable, Hashable, Codable, Sendable {
    case `default`, extended, chromatic
}

public enum JoystickDirection: CaseIterable, Hashable, Codable, Sendable {
    case center, up, upRight, right, downRight, down, downLeft, left, upLeft
}

public enum Inversion: CaseIterable, Hashable, Sendable {
    case root, first, second
}
