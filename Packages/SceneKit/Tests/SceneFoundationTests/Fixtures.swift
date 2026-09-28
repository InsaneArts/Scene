import Foundation
import Testing
@testable import SceneFoundation

// MARK: - Hand-assembled archives

/// One entry of a hand-assembled archive. The defaults describe a valid stored file,
/// so each test changes only the field it attacks.
struct RawEntry {
    var name: [UInt8]
    var content: Data
    /// 8 deflates `content`. Any other value writes `content` as-is.
    var method: Int
    var flags = 0
    var crc: UInt32?                        // nil: CRC-32 of `content`
    var uncompressedSize: Int?              // nil: content.count
    var compressedSize: Int?                // nil: size of the written data
    var versionMadeBy = 0x0314              // Unix, version 2.0
    var externalAttributes = 0o100644 << 16 // regular file
    var centralExtra: [UInt8] = []
    var localExtra: [UInt8] = []
    var localNameLength: Int?               // nil: name.count
    var localSignature = 0x0403_4B50
    /// If set, no local header is written and the central directory points at this offset.
    var localHeaderOffset: Int?

    init(_ name: String, _ content: String = "hello", method: Int = 0) {
        self.name = Array(name.utf8)
        self.content = Data(content.utf8)
        self.method = method
    }
}

/// Assembles an archive byte by byte. Flag bit 3 writes zero sizes in the local header
/// and a data descriptor after the data.
func makeZip(_ entries: [RawEntry], disk: Int = 0, zip64Locator: Bool = false) -> Data {
    var body = ByteWriter()
    var directory = ByteWriter()
    for entry in entries {
        let payload = entry.method == 8 ? deflated(entry.content) : entry.content
        let crc = Int(entry.crc ?? entry.content.withUnsafeBytes(ZipArchive.crc32))
        let compressedSize = entry.compressedSize ?? payload.count
        let uncompressedSize = entry.uncompressedSize ?? entry.content.count
        let offset = entry.localHeaderOffset ?? body.data.count
        if entry.localHeaderOffset == nil {
            let descriptor = entry.flags & 8 != 0
            body.u32(entry.localSignature)
            body.u16(20, entry.flags, entry.method, 0, 0x21)  // version, flags, method, time, date
            body.u32(descriptor ? 0 : crc, descriptor ? 0 : compressedSize, descriptor ? 0 : uncompressedSize)
            body.u16(entry.localNameLength ?? entry.name.count, entry.localExtra.count)
            body.append(entry.name + entry.localExtra)
            body.append(payload)
            if descriptor { body.u32(0x0807_4B50, crc, compressedSize, uncompressedSize) }
        }
        directory.u32(0x0201_4B50)
        directory.u16(entry.versionMadeBy, 20, entry.flags, entry.method, 0, 0x21)
        directory.u32(crc, compressedSize, uncompressedSize)
        directory.u16(entry.name.count, entry.centralExtra.count, 0, 0, 0)  // name, extra, comment, disk, internal
        directory.u32(entry.externalAttributes, offset)
        directory.append(entry.name + entry.centralExtra)
    }
    var archive = body
    archive.append(directory.data)
    if zip64Locator { archive.u32(0x0706_4B50, 0, 0, 0, 1) }
    archive.u32(0x0605_4B50)
    archive.u16(disk, disk, entries.count, entries.count)
    archive.u32(directory.data.count, body.data.count)
    archive.u16(0)  // comment length
    return archive.data
}

/// Raw DEFLATE from Foundation, independent of the library's encoder.
func deflated(_ data: Data) -> Data {
    try! (data as NSData).compressed(using: .zlib) as Data
}

struct ByteWriter {
    var data = Data()

    mutating func u16(_ values: Int...) {
        for value in values {
            data.append(UInt8(truncatingIfNeeded: value))
            data.append(UInt8(truncatingIfNeeded: value >> 8))
        }
    }

    mutating func u32(_ values: Int...) {
        for value in values {
            u16(value)
            u16(value >> 16)
        }
    }

    mutating func append(_ bytes: some Sequence<UInt8>) {
        data.append(contentsOf: bytes)
    }
}

/// Expects `read` to throw exactly `error`.
func expect(
    _ error: ZipError,
    reading archive: Data,
    limits: ZipLimits = .init(),
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(throws: error, sourceLocation: sourceLocation) { try ZipArchive.read(archive, limits: limits) }
}

/// Bytes that deflate cannot shrink, the same on every run.
func pseudoRandomBytes(_ count: Int) -> Data {
    var state: UInt64 = 0x9E37_79B9_7F4A_7C15
    return Data((0..<count).map { _ in
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return UInt8(truncatingIfNeeded: state >> 56)
    })
}

// MARK: - macOS command line tools

func withTemporaryDirectory<T>(_ body: (URL) throws -> T) throws -> T {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("SceneZipTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    return try body(directory)
}

func writeFiles(_ files: [String: Data], under root: URL) throws {
    for (path, data) in files {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}

/// Runs a tool and returns its exit status and combined stdout and stderr.
func run(_ tool: String, _ arguments: [String], in directory: URL) throws -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    process.currentDirectoryURL = directory
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let output = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: output, as: UTF8.self))
}
