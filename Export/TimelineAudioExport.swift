import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// The timeline as an audio file, for the share sheet: everything it
/// plays, the loops and the sequence together, rendered as it sounds.
struct TimelineAudioExport: Transferable, Sendable {
    let timeline: Timeline
    let live: LiveSettings
    let bpm: Double
    /// The mic sample, for the notes that play it.
    let sample: Recording?
    let onExport: @MainActor @Sendable (_ seconds: Double) -> Void

    /// e.g. "Perfecto C Major 120 BPM.wav"
    var fileName: String {
        "Perfecto \(live.key.root.name) \(live.key.scale.displayName) \(Int(bpm)) BPM.wav"
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .wav) { export in
            // A fresh directory per export keeps the readable file name
            // without colliding with an earlier export.
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(export.fileName)
            let seconds = try await TimelineAudioRenderer.render(export.timeline, live: export.live, bpm: export.bpm,
                                                                 sample: export.sample, to: url)
            await export.onExport(seconds)
            return SentTransferredFile(url)
        }
    }
}
