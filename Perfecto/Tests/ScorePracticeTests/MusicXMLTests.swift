import Compression
import Foundation
import Testing
@testable import ScorePractice

/// A partwise score of `parts`, each a list of measures' contents.
func musicXML(_ parts: [[String]], title: String = "Test piece") -> Data {
    let body = parts.enumerated().map { i, measures in
        "<part id=\"P\(i + 1)\">" + measures.enumerated().map { m, content in
            "<measure number=\"\(m + 1)\">\(content)</measure>"
        }.joined() + "</part>"
    }.joined()
    return Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">
    <score-partwise version="4.0"><work><work-title>\(title)</work-title></work>\(body)</score-partwise>
    """.utf8)
}

func note(_ step: String, _ octave: Int, _ duration: Int, alter: Int = 0, staff: Int? = nil,
          chord: Bool = false, tie: String? = nil, voice: Int = 1) -> String {
    (chord ? "<note><chord/>" : "<note>")
        + "<pitch><step>\(step)</step>\(alter != 0 ? "<alter>\(alter)</alter>" : "")<octave>\(octave)</octave></pitch>"
        + "<duration>\(duration)</duration>"
        + (tie.map { "<tie type=\"\($0)\"/>" } ?? "")
        + "<voice>\(voice)</voice>"
        + (staff.map { "<staff>\($0)</staff>" } ?? "")
        + "</note>"
}

func rest(_ duration: Int, staff: Int? = nil) -> String {
    "<note><rest/><duration>\(duration)</duration>" + (staff.map { "<staff>\($0)</staff>" } ?? "") + "</note>"
}

/// One bar of 4/4 at 60 to the quarter, so a quarter is a second.
let pianoAttributes = "<attributes><divisions>1</divisions><time><beats>4</beats><beat-type>4</beat-type></time><staves>2</staves></attributes><direction><sound tempo=\"60\"/></direction>"

@Suite("MusicXML")
struct MusicXMLTests {

    @Test func aPianoPartsStavesAreItsHands() throws {
        let score = try MusicXML.score(from: musicXML([[
            pianoAttributes
                + note("C", 5, 1, staff: 1) + note("E", 5, 1, staff: 1) + note("G", 5, 2, staff: 1)
                + "<backup><duration>4</duration></backup>"
                + note("C", 3, 2, staff: 2) + note("G", 3, 2, staff: 2, chord: true) + rest(2, staff: 2),
        ]]))
        #expect(score.title == "Test piece")
        #expect(score.steps(.right).map(\.onset) == [0, 1, 2])
        #expect(score.steps(.right).map { $0.notes.map(\.pitch) } == [[72], [76], [79]])
        #expect(score.steps(.left).map { $0.notes.map(\.pitch) } == [[48, 55]])
        #expect(score.steps(.left)[0].notes.allSatisfy { $0.duration == 2 })
        #expect(score.barlines == [0, 4])
    }

    @Test func alterationsAndTheTempoMakeThePitchesAndSeconds() throws {
        let score = try MusicXML.score(from: musicXML([[
            "<attributes><divisions>2</divisions></attributes><direction><sound tempo=\"120\"/></direction>"
                + note("F", 4, 1, alter: 1) + note("B", 3, 1, alter: -1),
        ]]))
        #expect(score.notes.map(\.pitch) == [66, 58])
        // Two divisions to a quarter at 120: an eighth is a quarter second.
        #expect(score.notes.map(\.onset) == [0, 0.25])
    }

    @Test func tiedNotesAreOneNote() throws {
        let score = try MusicXML.score(from: musicXML([[
            pianoAttributes + note("D", 5, 3, staff: 1) + note("D", 5, 1, staff: 1, tie: "start"),
            note("D", 5, 2, staff: 1, tie: "stop") + note("E", 5, 2, staff: 1),
        ]]))
        #expect(score.notes.map(\.pitch) == [74, 74, 76])
        #expect(score.notes[1].onset == 3)
        #expect(score.notes[1].duration == 3)
        #expect(score.barlines == [0, 4, 8])
    }

    @Test func graceNotesAreLeftOut() throws {
        let score = try MusicXML.score(from: musicXML([[
            pianoAttributes
                + "<note><grace/><pitch><step>B</step><octave>4</octave></pitch><staff>1</staff></note>"
                + note("C", 5, 4, staff: 1),
        ]]))
        #expect(score.notes.map(\.pitch) == [72])
    }

    @Test func partsOfOneStaffAreHandsByTheirPlace() throws {
        let attributes = "<attributes><divisions>1</divisions></attributes>"
        let score = try MusicXML.score(from: musicXML([
            [attributes + note("C", 5, 4)],
            [attributes + note("C", 3, 4)],
        ]))
        #expect(score.steps(.right).map { $0.notes.map(\.pitch) } == [[72]])
        #expect(score.steps(.left).map { $0.notes.map(\.pitch) } == [[48]])
    }

    @Test func whatIsNotAPartwiseScoreIsRefused() {
        #expect(throws: MusicXML.Failure.malformed) { try MusicXML.score(from: Data("<a><b></a>".utf8)) }
        #expect(throws: MusicXML.Failure.timewise) { try MusicXML.score(from: Data("<score-timewise/>".utf8)) }
        #expect(throws: MusicXML.Failure.notMusicXML) { try MusicXML.score(from: Data("<html/>".utf8)) }
        #expect(throws: MusicXML.Failure.noNotes) { try MusicXML.score(from: musicXML([[rest(4)]])) }
    }
}

@Suite("Mxl")
struct MxlTests {

    private let score = musicXML([[pianoAttributes + note("A", 4, 4, staff: 1)]])

    @Test func theContainerNamesTheScore() throws {
        let container = Data("""
        <?xml version="1.0"?><container><rootfiles><rootfile full-path="music/piece.musicxml"/></rootfiles></container>
        """.utf8)
        let archive = zip([("META-INF/container.xml", container, true),
                           ("other.xml", Data("<x/>".utf8), false),
                           ("music/piece.musicxml", score, true)])
        #expect(Mxl.isArchive(archive))
        #expect(try Mxl.document(in: archive) == score)
    }

    @Test func withNoContainerTheFirstScoreIsTaken() throws {
        let archive = zip([("META-INF/manifest.xml", Data("<m/>".utf8), false), ("piece.xml", score, false)])
        #expect(try Mxl.document(in: archive) == score)
    }

    @Test func aScoreIsNotAnArchive() {
        #expect(!Mxl.isArchive(score))
        #expect(throws: Mxl.Failure.notZip) { try Mxl.document(in: score) }
    }

    /// A ZIP archive of `files`, each stored or deflated.
    private func zip(_ files: [(name: String, data: Data, deflated: Bool)]) -> Data {
        var local = [UInt8](), central = [UInt8]()
        func u16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
        func u32(_ v: Int) -> [UInt8] { u16(v & 0xFFFF) + u16(v >> 16) }
        for file in files {
            let raw = [UInt8](file.data)
            let stored = file.deflated ? deflate(raw) : raw
            let name = [UInt8](file.name.utf8)
            let method = file.deflated ? 8 : 0
            let offset = local.count
            local += u32(0x0403_4B50) + u16(20) + u16(0) + u16(method) + u32(0) + u32(0)
                + u32(stored.count) + u32(raw.count) + u16(name.count) + u16(0) + name + stored
            central += u32(0x0201_4B50) + u16(20) + u16(20) + u16(0) + u16(method) + u32(0) + u32(0)
                + u32(stored.count) + u32(raw.count) + u16(name.count) + u16(0) + u16(0) + u16(0)
                + u16(0) + u32(0) + u32(offset) + name
        }
        let end = u32(0x0605_4B50) + u16(0) + u16(0) + u16(files.count) + u16(files.count)
            + u32(central.count) + u32(local.count) + u16(0)
        return Data(local + central + end)
    }

    private func deflate(_ raw: [UInt8]) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: raw.count + 1024)
        let count = compression_encode_buffer(&out, out.count, raw, raw.count, nil, COMPRESSION_ZLIB)
        return Array(out.prefix(count))
    }
}
