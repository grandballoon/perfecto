import Foundation

@MainActor
final class FileLogger: Logger {

    private let url: URL
    private let sessionID = UUID()
    private let encoder: JSONEncoder
    private var handle: FileHandle?

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        url = caches.appendingPathComponent("perfecto.log")
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        openHandle()
        trimIfNeeded()
    }

    var logFileURL: URL { url }

    func log(_ event: LogEvent) {
        let wrapped = WrappedEvent(timestamp: Date(), sessionID: sessionID, event: event)
        guard let data = try? encoder.encode(wrapped),
              let line = String(data: data, encoding: .utf8) else { return }
        handle?.seekToEndOfFile()
        handle?.write(Data((line + "\n").utf8))
    }

    // MARK: – Private

    private func openHandle() {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: url)
    }

    // Keep at most 5000 lines; rewrite on startup if over limit.
    private func trimIfNeeded() {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count > 5000 else { return }
        let kept = lines.suffix(5000).joined(separator: "\n") + "\n"
        try? kept.write(to: url, atomically: true, encoding: .utf8)
        handle?.closeFile()
        openHandle()
    }

    private struct WrappedEvent: Encodable {
        let timestamp: Date
        let session_id: UUID
        let event: LogEvent

        init(timestamp: Date, sessionID: UUID, event: LogEvent) {
            self.timestamp  = timestamp
            self.session_id = sessionID
            self.event      = event
        }
    }
}
