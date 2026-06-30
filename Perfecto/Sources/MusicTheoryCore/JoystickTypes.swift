public enum JoystickMode: Hashable, Sendable {
    case `default`, extended, chromatic
}

public enum JoystickDirection: Hashable, Sendable {
    case center, up, upRight, right, downRight, down, downLeft, left, upLeft
}

public enum Inversion: Sendable {
    case root, first, second
}
