import Foundation

/// A score taken in for practice, and what has been made of it
/// (`Practice`), as it is kept. A piece saved when pieces had recordings is
/// read the same, its recording passed over.
struct Piece: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var title: String
    /// The score as it was imported, in the piece's folder.
    let scoreFile: String
    var practice: Practice
    let added: Date
    /// When it was last saved, by whichever device saved it: of two copies
    /// of a piece, the later is the one kept. Nil in pieces saved before it
    /// was kept, which count as saved long ago.
    var modified: Date?
}

/// The pieces, each in a folder of its own: the score copied in as it was
/// given, and the piece itself as JSON beside them,
/// so a piece is read again as it was left.
///
/// The folder is in the app's iCloud container when the device is signed
/// in to iCloud (`resolve`), so the phone and the Mac share their pieces,
/// and in the app's support folder when it is not. Every read and write
/// goes through a file coordinator, which is how a file in iCloud is read
/// whole (it is downloaded first) and written without the sync daemon
/// catching it half done.
///
/// It is the only part of score practice that touches the disk. Its calls
/// can wait on the network, the first read of a piece from the other
/// device above all, so they are made off the main thread where they read.
struct ScoreLibrary: Sendable {
    let folder: URL
    /// Whether the folder is in iCloud, so it is shared and watched.
    var isInCloud = false

    static let containerIdentifier = "iCloud.com.lukesovernconley.pocketchord"

    /// The folder on this device alone.
    static let local = ScoreLibrary(folder: URL.applicationSupportDirectory
        .appendingPathComponent("Scores", isDirectory: true))

    private static let pieceFile = "piece.json"

    /// The library in iCloud if the device is signed in to it, with any
    /// pieces kept on the device alone moved into it; the local one if not.
    /// It can wait on iCloud, so it is never called on the main thread.
    nonisolated static func resolve() -> ScoreLibrary {
        let files = FileManager.default
        guard let container = files.url(forUbiquityContainerIdentifier: containerIdentifier) else { return local }
        let cloud = ScoreLibrary(folder: container.appendingPathComponent("Scores", isDirectory: true),
                                 isInCloud: true)
        do {
            try files.createDirectory(at: cloud.folder, withIntermediateDirectories: true)
        } catch {
            return local
        }
        let kept = (try? files.contentsOfDirectory(at: local.folder, includingPropertiesForKeys: nil)) ?? []
        for piece in kept {
            let destination = cloud.folder.appendingPathComponent(piece.lastPathComponent, isDirectory: true)
            if files.fileExists(atPath: destination.path) { continue }
            try? files.setUbiquitous(true, itemAt: piece, destinationURL: destination)
        }
        return cloud
    }

    /// The pieces kept, the latest first. Pieces from the other device are
    /// downloaded as they are read.
    func pieces() -> [Piece] {
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil)) ?? []
        return folders
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .compactMap { try? piece(at: $0.appendingPathComponent(Self.pieceFile)) }
            .sorted { $0.added > $1.added }
    }

    /// The score at `url` read and kept as a new piece. A file the system
    /// has only lent (from the Files app) is read while it is lent.
    func importScore(from url: URL) throws -> (Piece, Score) {
        let data = try Self.readLent(url)
        let name = url.deletingPathExtension().lastPathComponent
        let score = try Self.score(from: data, title: name)
        let id = UUID()
        let bytes = [UInt8](data.prefix(4))
        let scoreFile = "score." + (MidiScore.isMidi(bytes) ? "mid" : Mxl.isArchive(data) ? "mxl" : "musicxml")
        try write(data, to: folder(of: id).appendingPathComponent(scoreFile))
        let piece = Piece(id: id, title: score.title, scoreFile: scoreFile,
                          practice: Practice(score: score), added: .now)
        return (try save(piece), score)
    }

    func score(of piece: Piece) throws -> Score {
        let data = try read(folder(of: piece.id).appendingPathComponent(piece.scoreFile))
        return try Self.score(from: data, title: piece.title)
    }

    /// `piece` saved as it is now; it is given back marked with the moment.
    @discardableResult
    func save(_ piece: Piece) throws -> Piece {
        var piece = piece
        piece.modified = .now
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try write(encoder.encode(piece), to: folder(of: piece.id).appendingPathComponent(Self.pieceFile))
        return piece
    }

    func delete(_ piece: Piece) {
        remove(folder(of: piece.id))
    }

    private func folder(of id: UUID) -> URL {
        folder.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// MusicXML, compressed or not, or a Standard MIDI File.
    static func score(from data: Data, title: String) throws -> Score {
        if MidiScore.isMidi([UInt8](data.prefix(4))) { return try MidiScore.score(from: [UInt8](data), title: title) }
        return try MusicXML.score(from: Mxl.isArchive(data) ? Mxl.document(in: data) : data, title: title)
    }

    // MARK: – Coordinated files

    /// The piece at `url`. Two devices that saved it while apart leave
    /// copies in conflict; the one iCloud chose is kept, which is the later
    /// unless the clocks disagree, and the others are let go.
    private func piece(at url: URL) throws -> Piece {
        if isInCloud, let others = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !others.isEmpty {
            for version in others { version.isResolved = true }
            try? NSFileVersion.removeOtherVersionsOfItem(at: url)
        }
        return try JSONDecoder().decode(Piece.self, from: read(url))
    }

    private func read(_ url: URL) throws -> Data {
        var data = Data()
        try coordinate(reading: url) { data = try Data(contentsOf: $0) }
        return data
    }

    private func write(_ data: Data, to url: URL) throws {
        try coordinate(writing: url, options: .forReplacing) { target in
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: target, options: .atomic)
        }
    }

    private func remove(_ url: URL) {
        try? coordinate(writing: url, options: .forDeleting) { try FileManager.default.removeItem(at: $0) }
    }

    private func coordinate(reading url: URL, _ body: (URL) throws -> Void) throws {
        var failure: NSError?
        var thrown: (any Error)?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &failure) { target in
            do { try body(target) } catch { thrown = error }
        }
        if let error = failure ?? thrown { throw error }
    }

    private func coordinate(writing url: URL, options: NSFileCoordinator.WritingOptions,
                            _ body: (URL) throws -> Void) throws {
        var failure: NSError?
        var thrown: (any Error)?
        NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &failure) { target in
            do { try body(target) } catch { thrown = error }
        }
        if let error = failure ?? thrown { throw error }
    }

    private static func readLent(_ url: URL) throws -> Data {
        let lent = url.startAccessingSecurityScopedResource()
        defer { if lent { url.stopAccessingSecurityScopedResource() } }
        return try Data(contentsOf: url)
    }
}

/// Watches the library in iCloud for what the other device changes: each
/// file there is downloaded as soon as it is known of, so a piece is ready
/// before it is opened, and `onChange` is told whenever anything arrives
/// or changes.
@MainActor
final class ScoreLibraryWatcher {
    private let query = NSMetadataQuery()
    private var observers: [any NSObjectProtocol] = []

    init(onChange: @escaping @MainActor () -> Void) {
        query.searchScopes = [NSMetadataQueryUbiquitousDataScope]
        query.predicate = NSPredicate(format: "%K LIKE '*'", NSMetadataItemFSNameKey)
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.downloadAll()
                    onChange()
                }
            })
        }
        query.start()
    }

    func stop() {
        query.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    private func downloadAll() {
        query.disableUpdates()
        defer { query.enableUpdates() }
        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
                    != NSMetadataUbiquitousItemDownloadingStatusCurrent else { continue }
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
    }
}
