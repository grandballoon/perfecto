@testable import Perfecto

/// Recording double for Logger. Captures log events instead of writing to disk.
/// Use in tests to assert what events were emitted.
@MainActor
final class RecordingLogger: Logger {

    private(set) var events: [LogEvent] = []

    func log(_ event: LogEvent) {
        events.append(event)
    }

    func reset() { events = [] }
}
