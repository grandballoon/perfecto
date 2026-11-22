import Compression
import Foundation

/// Compressed MusicXML (`.mxl`): a ZIP archive whose
/// `META-INF/container.xml` names the score inside it. Only the container
/// is read here; the score is read by `MusicXML` like any other.
///
/// A minimal ZIP reader: the end-of-central-directory record, the central
/// directory (whose sizes are right even when a streamed archive left the
/// local headers' at zero), and one entry's bytes through its local
/// header, stored or deflated, the only two methods MusicXML tools write.
enum Mxl {

    enum Failure: Error, Equatable {
        case notZip
        case corrupt
        case unsupportedMethod(Int)
        case noScore
    }

    /// Whether `data` is a ZIP archive rather than an XML document.
    static func isArchive(_ data: Data) -> Bool {
        data.count >= 4 && Array(data.prefix(4)) == [0x50, 0x4B, 0x03, 0x04]
    }

    /// The MusicXML document in the archive: the one its container names,
    /// or failing a container, its first XML file outside `META-INF`.
    static func document(in data: Data) throws -> Data {
        let bytes = [UInt8](data)
        let entries = try self.entries(bytes)
        var rootPath: String?
        if let container = entries.first(where: { $0.name == "META-INF/container.xml" }),
           let tree = XMLTree.parse(try read(container, in: bytes)) {
            rootPath = tree.first { $0.name == "rootfile" }?.attributes["full-path"]
        }
        let root = rootPath.flatMap { path in entries.first { $0.name == path } }
            ?? entries.first { entry in
                let name = entry.name.lowercased()
                return !name.hasPrefix("meta-inf/") && (name.hasSuffix(".xml") || name.hasSuffix(".musicxml"))
            }
        guard let root else { throw Failure.noScore }
        return try read(root, in: bytes)
    }

    struct Entry: Equatable {
        let name: String
        let method: Int
        let compressedSize: Int
        let size: Int
        let offset: Int
    }

    static func entries(_ bytes: [UInt8]) throws -> [Entry] {
        // The end record is at the very end, pushed back by a comment of up
        // to 64 KiB.
        guard bytes.count >= 22 else { throw Failure.notZip }
        let lowest = max(0, bytes.count - 22 - 0xFFFF)
        guard let end = stride(from: bytes.count - 22, through: lowest, by: -1)
            .first(where: { u32(bytes, $0) == 0x0605_4B50 }) else { throw Failure.notZip }
        let count = u16(bytes, end + 10)
        var p = u32(bytes, end + 16)
        var entries: [Entry] = []
        for _ in 0..<count {
            guard p + 46 <= bytes.count, u32(bytes, p) == 0x0201_4B50 else { throw Failure.corrupt }
            let nameLength = u16(bytes, p + 28)
            guard p + 46 + nameLength <= bytes.count else { throw Failure.corrupt }
            entries.append(Entry(
                name: String(decoding: bytes[(p + 46)..<(p + 46 + nameLength)], as: UTF8.self),
                method: u16(bytes, p + 10),
                compressedSize: u32(bytes, p + 20),
                size: u32(bytes, p + 24),
                offset: u32(bytes, p + 42)))
            p += 46 + nameLength + u16(bytes, p + 30) + u16(bytes, p + 32)
        }
        return entries
    }

    static func read(_ entry: Entry, in bytes: [UInt8]) throws -> Data {
        let p = entry.offset
        guard p + 30 <= bytes.count, u32(bytes, p) == 0x0403_4B50 else { throw Failure.corrupt }
        let start = p + 30 + u16(bytes, p + 26) + u16(bytes, p + 28)
        guard start + entry.compressedSize <= bytes.count else { throw Failure.corrupt }
        let stored = Array(bytes[start..<(start + entry.compressedSize)])
        switch entry.method {
        case 0:
            return Data(stored)
        case 8:
            return try inflate(stored, size: entry.size)
        default:
            throw Failure.unsupportedMethod(entry.method)
        }
    }

    /// Raw deflate, which is what Apple's `COMPRESSION_ZLIB` decodes.
    private static func inflate(_ stored: [UInt8], size: Int) throws -> Data {
        guard size > 0 else { return Data() }
        var out = [UInt8](repeating: 0, count: size)
        let written = compression_decode_buffer(&out, size, stored, stored.count, nil, COMPRESSION_ZLIB)
        guard written == size else { throw Failure.corrupt }
        return Data(out)
    }

    private static func u16(_ b: [UInt8], _ i: Int) -> Int {
        Int(b[i]) | Int(b[i + 1]) << 8
    }

    private static func u32(_ b: [UInt8], _ i: Int) -> Int {
        guard i >= 0, i + 4 <= b.count else { return -1 }
        return Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24
    }
}
