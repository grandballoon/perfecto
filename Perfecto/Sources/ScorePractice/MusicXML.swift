import Foundation

/// MusicXML, read into a `Score`: the format the practice screen takes a
/// score in, as `.musicxml` (or `.xml`) or compressed as `.mxl`
/// (`Mxl.document`), which is what MuseScore, Dorico, Finale and Sibelius
/// export and what a phone's Files app passes on as one small file.
///
/// It states which staff each note is on, which is what says the hand, so
/// a run of one hand needs no guessing (a MIDI file only has tracks, which
/// a piano's export may or may not split by hand).
///
/// Partwise scores are read part by part with a cursor in seconds, as
/// harmonicland's reader does: `<divisions>` and `<sound tempo>` set the
/// seconds, `<chord>` shares the last onset, `<backup>` and `<forward>`
/// move the cursor, tied notes are joined into one, grace notes and rests
/// are passed over, and each `<measure>` is a barline. A part of two
/// staves is a piano's: its upper staff is the right hand and the rest the
/// left. A part of one staff is a hand by its place: the first part the
/// right, the others the left.
enum MusicXML {

    enum Failure: Error, Equatable {
        case malformed
        case timewise
        case notMusicXML
        case noNotes
    }

    static func score(from data: Data, title fallback: String = "Untitled") throws -> Score {
        guard let root = XMLTree.parse(data) else { throw Failure.malformed }
        if root.name == "score-timewise" { throw Failure.timewise }
        guard root.name == "score-partwise" else { throw Failure.notMusicXML }

        // Tempo is a property of time, not of a part: every part starts
        // from the first marking, so a piece of one tempo is exact in all.
        let firstTempo = root.first { $0.name == "sound" && $0.attributes["tempo"] != nil }
            .flatMap { Double($0.attributes["tempo"]!) } ?? 120

        var tied: [TiedNote] = []
        var barlines: [Double] = []
        for (ordinal, part) in root.children.filter({ $0.name == "part" }).enumerated() {
            let staves = part.children.flatMap { $0.children }
                .filter { $0.name == "attributes" }
                .compactMap { $0.child("staves")?.number }.max() ?? 1
            let distinct = Set(part.all { $0.name == "staff" }.map(\.text)).count
            let isPiano = staves > 1 || distinct > 1

            var divisions = 1.0
            var tempo = firstTempo
            var cursor = 0.0
            var lastOnset = 0.0
            func seconds(_ duration: Double) -> Double { duration * 60 / tempo / divisions }

            for measure in part.children where measure.name == "measure" {
                if ordinal == 0 { barlines.append(cursor) }
                var reached = cursor
                for element in measure.children {
                    reached = max(reached, cursor)
                    switch element.name {
                    case "attributes":
                        if let d = element.child("divisions")?.number, d > 0 { divisions = d }
                    case "sound", "direction":
                        let sound = element.name == "sound" ? element : element.child("sound")
                        if let bpm = sound?.attributes["tempo"].flatMap(Double.init), bpm > 0 { tempo = bpm }
                    case "backup":
                        cursor = max(0, cursor - seconds(element.child("duration")?.number ?? 0))
                    case "forward":
                        cursor += seconds(element.child("duration")?.number ?? 0)
                    case "note":
                        if element.child("grace") != nil { break }
                        let length = seconds(element.child("duration")?.number ?? 0)
                        let isChord = element.child("chord") != nil
                        let onset = isChord ? lastOnset : cursor
                        if !isChord {
                            lastOnset = cursor
                            cursor += length
                        }
                        guard let pitch = element.child("pitch").flatMap(midiPitch) else { break }
                        let staff = Int(element.child("staff")?.number ?? 1)
                        let hand: Hand = isPiano ? (staff == 1 ? .right : .left)
                                                 : (ordinal == 0 ? .right : .left)
                        let ties = element.children.filter { $0.name == "tie" }.compactMap { $0.attributes["type"] }
                        tied.append(TiedNote(
                            pitch: pitch, onset: onset, end: onset + length, hand: hand,
                            voice: element.child("voice")?.text ?? "",
                            starts: ties.contains("start"), stops: ties.contains("stop")))
                    default:
                        break
                    }
                }
                cursor = max(reached, cursor)
            }
            if ordinal == 0 { barlines.append(cursor) }
        }

        let notes = joinTies(tied)
        guard !notes.isEmpty else { throw Failure.noNotes }
        let title = (root.first { $0.name == "work-title" } ?? root.first { $0.name == "movement-title" })?
            .text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Score(title: title?.isEmpty == false ? title! : fallback, notes: notes, barlines: barlines)
    }

    private static let stepSemitones: [String: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]

    private static func midiPitch(_ pitch: XMLTree) -> Int? {
        guard let step = pitch.child("step").flatMap({ stepSemitones[$0.text] }),
              let octave = pitch.child("octave")?.number else { return nil }
        let alter = Int((pitch.child("alter")?.number ?? 0).rounded())
        return 12 * (Int(octave) + 1) + step + alter
    }

    private struct TiedNote {
        let pitch: Int
        let onset: Double
        var end: Double
        let hand: Hand
        var voice: String
        let starts: Bool
        let stops: Bool
    }

    /// Joins tied notes into one sounding note. A tie's stop continues the
    /// open tie on its pitch that ends where it begins, in the same voice
    /// if there is one, so ties are matched in time whatever order the file
    /// wrote its voices in. A stop with no such tie is a note of its own.
    private static func joinTies(_ tied: [TiedNote]) -> [ScoreNote] {
        var open: [Int] = []        // indices into `out` of ties still open
        var out: [TiedNote] = []
        for note in tied.sorted(by: { $0.onset < $1.onset }) {
            if note.stops {
                let ends = open.filter { out[$0].pitch == note.pitch && abs(out[$0].end - note.onset) < Score.sameTime }
                if let held = ends.first(where: { out[$0].voice == note.voice }) ?? ends.first {
                    out[held].end = note.end
                    out[held].voice = note.voice
                    if !note.starts { open.removeAll { $0 == held } }
                    continue
                }
            }
            out.append(note)
            if note.starts { open.append(out.count - 1) }
        }
        return out.map {
            ScoreNote(pitch: $0.pitch, onset: $0.onset, duration: max(0.02, $0.end - $0.onset), hand: $0.hand)
        }
    }
}

/// An XML document as a tree of elements, enough to walk a MusicXML file.
struct XMLTree {
    let name: String
    let attributes: [String: String]
    var children: [XMLTree]
    /// The element's own text, trimmed.
    var text: String

    var number: Double? { Double(text) }

    func child(_ name: String) -> XMLTree? {
        children.first { $0.name == name }
    }

    /// The first element at or under this one, in document order, that
    /// passes `test`.
    func first(where test: (XMLTree) -> Bool) -> XMLTree? {
        if test(self) { return self }
        for child in children {
            if let found = child.first(where: test) { return found }
        }
        return nil
    }

    func all(where test: (XMLTree) -> Bool) -> [XMLTree] {
        (test(self) ? [self] : []) + children.flatMap { $0.all(where: test) }
    }

    static func parse(_ data: Data) -> XMLTree? {
        let builder = Builder()
        let parser = XMLParser(data: data)
        // A MusicXML file names its DTD; nothing should be fetched for it.
        parser.shouldResolveExternalEntities = false
        parser.delegate = builder
        guard parser.parse() else { return nil }
        return builder.root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var stack: [XMLTree] = []
        var root: XMLTree?

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            stack.append(XMLTree(name: name, attributes: attributes, children: [], text: ""))
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard !stack.isEmpty else { return }
            stack[stack.count - 1].text += string
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                    qualifiedName: String?) {
            guard var done = stack.popLast() else { return }
            done.text = done.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if stack.isEmpty { root = done } else { stack[stack.count - 1].children.append(done) }
        }
    }
}
