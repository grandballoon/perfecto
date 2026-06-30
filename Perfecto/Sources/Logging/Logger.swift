import Foundation

@MainActor
protocol Logger {
    func log(_ event: LogEvent)
}
