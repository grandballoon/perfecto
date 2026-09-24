import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A sequencer pattern offered to the share sheet as a `.mid` file — AirDrop,
/// Save to Files, or straight into GarageBand, where it imports as an
/// ordinary software-instrument track whose instrument can be swapped.
///
/// The file is rendered only when the user picks a destination, and
/// `onExport` fires then (on the main actor) so the export can be logged.
struct SequencerMidiExport: Transferable, Sendable {
    let pattern: SequencerPattern
    let onExport: @MainActor @Sendable (_ noteCount: Int, _ byteCount: Int) -> Void

    /// e.g. "Perfecto C Major 120 BPM.mid"
    var fileName: String {
        "Perfecto \(pattern.key.root.name) \(pattern.key.scale.displayName) \(Int(pattern.bpm)) BPM.mid"
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .midi) { export in
            let file = SequencerMidiRenderer.render(export.pattern)
            let bytes = file.encoded()
            // A fresh directory per export keeps the human-readable file name
            // without colliding with an earlier export of the same pattern.
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(export.fileName)
            try Data(bytes).write(to: url)

            let noteCount = file.tracks.flatMap(\.events).filter {
                if case .noteOn = $0.kind { return true } else { return false }
            }.count
            await export.onExport(noteCount, bytes.count)
            return SentTransferredFile(url)
        }
    }
}
