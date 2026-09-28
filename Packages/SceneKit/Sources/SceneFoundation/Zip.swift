import Compression
import Foundation

/// Caps that `ZipArchive` enforces before and during decompression.
public struct ZipLimits: Sendable {
    public var maxEntries: Int
    public var maxEntryUncompressedBytes: Int
    public var maxTotalUncompressedBytes: Int
    /// Largest allowed ratio of uncompressed size to compressed size for one entry.
    public var maxCompressionRatio: Double

    public init(
        maxEntries: Int = 64,
        maxEntryUncompressedBytes: Int = 20 * 1024 * 1024,
        maxTotalUncompressedBytes: Int = 40 * 1024 * 1024,
        maxCompressionRatio: Double = 200
    ) {
        self.maxEntries = maxEntries
        self.maxEntryUncompressedBytes = maxEntryUncompressedBytes
        self.maxTotalUncompressedBytes = maxTotalUncompressedBytes
        self.maxCompressionRatio = maxCompressionRatio
    }
}

public struct ZipEntry: Sendable, Equatable {
    /// Validated relative path with "/" separators. A directory path ends with "/".
    public let path: String
    public let uncompressedSize: Int
    public let compressedSize: Int
    public let isDirectory: Bool
}

public enum ZipError: Error, Equatable, Sendable {
    /// No end of central directory record, or a central directory header has a bad signature.
    case notAZip
    /// An offset or a size points outside the bytes where that part of the archive must be.
    case truncated
    case unsupportedMethod(Int)
    case encrypted
    case zip64Unsupported
    case multiDisk
    case unsafePath(String)
    case symlink(String)
    case duplicatePath(String)
    case tooManyEntries
    case entryTooLarge(String)
    case totalTooLarge
    case suspiciousCompressionRatio(String)
    /// The local file header is missing or its name length differs from the central directory.
    case localHeaderMismatch(String)
    /// The entry shares bytes with another entry, as in overlapping-file zip bombs.
    case overlappingEntries(String)
    /// The entry data does not decode to exactly its declared size.
    case corruptEntry(String)
    case crcMismatch(String)
}

public enum ZipArchive {
    /// Parses the central directory and validates every entry. Does not decompress.
    public static func entries(of data: Data, limits: ZipLimits = .init()) throws -> [ZipEntry] {
        try data.withUnsafeBytes { try parse(Reader(buffer: $0), limits: limits).map(\.entry) }
    }

    /// Returns the decompressed bytes of every file entry, keyed by path, after full validation and CRC checks.
    public static func read(_ data: Data, limits: ZipLimits = .init()) throws -> [String: Data] {
        try data.withUnsafeBytes { buffer in
            let archive = Reader(buffer: buffer)
            var files: [String: Data] = [:]
            for record in try parse(archive, limits: limits) where !record.entry.isDirectory {
                files[record.entry.path] = try extract(record, from: archive)
            }
            return files
        }
    }

    /// Creates a zip (DEFLATE, or STORED when deflate does not help) from in-memory files. Paths use "/".
    /// Deterministic output (fixed DOS timestamp 1980-01-01) so identical input gives identical bytes.
    /// Entries keep the input order. Paths follow the same rules as `read`, and directory paths are rejected.
    public static func create(files: [(path: String, data: Data)]) throws -> Data {
        guard files.count < 0xFFFF else { throw ZipError.zip64Unsupported }
        var archive = Data()
        var directory = Data()
        var seenPaths = Set<String>()
        for file in files {
            let name = Data(file.path.utf8)
            let path = try name.withUnsafeBytes(validatedPath)
            guard !path.hasSuffix("/") else { throw ZipError.unsafePath(path) }
            guard seenPaths.insert(duplicateKey(path)).inserted else { throw ZipError.duplicatePath(path) }
            guard file.data.count < 0xFFFF_FFFF else { throw ZipError.zip64Unsupported }

            let deflated = deflate(file.data)
            let payload = deflated ?? file.data
            let localHeaderOffset = archive.count

            // These fields are identical in the local header and the central directory header.
            var fields = Data()
            fields.le16(20)                               // version needed to extract: 2.0
            fields.le16(0x0800)                           // flags: bit 11, the name is UTF-8
            fields.le16(deflated == nil ? 0 : 8)          // method: stored or deflate
            fields.le16(0)                                // modification time: 00:00:00
            fields.le16(0x0021)                           // modification date: 1980-01-01
            fields.le32(Int(file.data.withUnsafeBytes(crc32)))
            fields.le32(payload.count)
            fields.le32(file.data.count)
            fields.le16(name.count)
            fields.le16(0)                                // extra field length

            archive.le32(Signature.localHeader)
            archive.append(fields)
            archive.append(name)
            archive.append(payload)

            directory.le32(Signature.centralHeader)
            directory.le16(0x0314)                        // made by: Unix, version 2.0
            directory.append(fields)
            directory.le16(0)                             // comment length
            directory.le16(0)                             // disk number start
            directory.le16(0)                             // internal attributes
            directory.le32(0o100644 << 16)                // external attributes: regular file, rw-r--r--
            directory.le32(localHeaderOffset)
            directory.append(name)
        }
        let directoryOffset = archive.count
        archive.append(directory)
        archive.le32(Signature.endOfCentralDirectory)
        archive.le16(0)                                   // number of this disk
        archive.le16(0)                                   // disk with the central directory
        archive.le16(files.count)                         // entries on this disk
        archive.le16(files.count)                         // total entries
        archive.le32(directory.count)
        archive.le32(directoryOffset)
        archive.le16(0)                                   // comment length
        // Every offset and size written above is smaller than the archive, so this check covers them all.
        guard archive.count < 0xFFFF_FFFF else { throw ZipError.zip64Unsupported }
        return archive
    }

    /// CRC-32 as stored in zip headers (IEEE 802.3, reflected polynomial 0xEDB88320).
    static func crc32(_ bytes: UnsafeRawBufferPointer) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        crcTable.withUnsafeBufferPointer { table in
            for byte in bytes {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return ~crc
    }

    private static let crcTable: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 {
            value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }
}

// MARK: - Reading

private enum Signature {
    static let localHeader = 0x0403_4B50
    static let centralHeader = 0x0201_4B50
    static let endOfCentralDirectory = 0x0605_4B50
    static let zip64Locator = 0x0706_4B50
}

/// A central directory entry that passed validation, with the offsets needed to extract it.
private struct Record {
    let entry: ZipEntry
    let method: Int
    let crc: UInt32
    let localHeaderOffset: Int
    let dataOffset: Int
}

/// Little-endian reads that throw `ZipError.truncated` instead of reading out of bounds.
private struct Reader {
    let buffer: UnsafeRawBufferPointer

    var count: Int { buffer.count }

    func bytes(_ offset: Int, _ count: Int) throws -> UnsafeRawBufferPointer {
        guard offset >= 0, count >= 0, offset <= buffer.count - count else { throw ZipError.truncated }
        return UnsafeRawBufferPointer(rebasing: buffer[offset ..< offset + count])
    }

    /// A reader limited to `count` bytes from `offset`, with offsets relative to `offset`.
    func reader(_ offset: Int, _ count: Int) throws -> Reader {
        Reader(buffer: try bytes(offset, count))
    }

    func u16(_ offset: Int) throws -> Int {
        let b = try bytes(offset, 2)
        return Int(b[0]) | Int(b[1]) << 8
    }

    func u32(_ offset: Int) throws -> Int {
        let b = try bytes(offset, 4)
        return Int(b[0]) | Int(b[1]) << 8 | Int(b[2]) << 16 | Int(b[3]) << 24
    }
}

extension ZipArchive {
    private static func parse(_ archive: Reader, limits: ZipLimits) throws -> [Record] {
        guard let end = endOfCentralDirectory(in: archive) else {
            // A local header at the start without an end record means the file was cut short.
            throw (try? archive.u32(0)) == Signature.localHeader ? ZipError.truncated : ZipError.notAZip
        }
        if end >= 20, try archive.u32(end - 20) == Signature.zip64Locator {
            throw ZipError.zip64Unsupported
        }
        let disk = try archive.u16(end + 4)
        let directoryDisk = try archive.u16(end + 6)
        let entriesOnDisk = try archive.u16(end + 8)
        let entryCount = try archive.u16(end + 10)
        let directorySize = try archive.u32(end + 12)
        let directoryOffset = try archive.u32(end + 16)
        // ZIP64 archives put these sentinel values in the classic record.
        if [disk, directoryDisk, entriesOnDisk, entryCount].contains(0xFFFF)
            || directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF {
            throw ZipError.zip64Unsupported
        }
        guard disk == 0, directoryDisk == 0, entriesOnDisk == entryCount else { throw ZipError.multiDisk }
        guard entryCount <= limits.maxEntries else { throw ZipError.tooManyEntries }
        guard directoryOffset + directorySize <= end else { throw ZipError.truncated }

        let directory = try archive.reader(directoryOffset, directorySize)
        // Local headers and their data must lie before the central directory.
        let body = try archive.reader(0, directoryOffset)
        var records: [Record] = []
        var seenPaths = Set<String>()
        var totalSize = 0
        var cursor = 0
        for _ in 0..<entryCount {
            guard try directory.u32(cursor) == Signature.centralHeader else { throw ZipError.notAZip }
            let madeBy = try directory.u16(cursor + 4)
            let flags = try directory.u16(cursor + 8)
            let method = try directory.u16(cursor + 10)
            let crc = try directory.u32(cursor + 16)
            let compressedSize = try directory.u32(cursor + 20)
            let uncompressedSize = try directory.u32(cursor + 24)
            let nameLength = try directory.u16(cursor + 28)
            let extraLength = try directory.u16(cursor + 30)
            let commentLength = try directory.u16(cursor + 32)
            let startDisk = try directory.u16(cursor + 34)
            let externalAttributes = try directory.u32(cursor + 38)
            let localHeaderOffset = try directory.u32(cursor + 42)
            let name = try directory.bytes(cursor + 46, nameLength)
            let extra = try directory.bytes(cursor + 46 + nameLength, extraLength)
            cursor += 46 + nameLength + extraLength + commentLength
            guard cursor <= directory.count else { throw ZipError.truncated }

            if compressedSize == 0xFFFF_FFFF || uncompressedSize == 0xFFFF_FFFF
                || localHeaderOffset == 0xFFFF_FFFF || startDisk == 0xFFFF || hasZip64Field(extra) {
                throw ZipError.zip64Unsupported
            }
            guard startDisk == 0 else { throw ZipError.multiDisk }

            let path = try validatedPath(name)
            guard flags & 1 == 0 else { throw ZipError.encrypted }
            guard method == 0 || method == 8 else { throw ZipError.unsupportedMethod(method) }
            // The Unix mode sits in the high 16 bits when the host is Unix (3) or OS X (19).
            let host = madeBy >> 8
            if host == 3 || host == 19, (externalAttributes >> 16) & 0o170000 == 0o120000 {
                throw ZipError.symlink(path)
            }
            guard seenPaths.insert(duplicateKey(path)).inserted else { throw ZipError.duplicatePath(path) }

            guard uncompressedSize <= limits.maxEntryUncompressedBytes else { throw ZipError.entryTooLarge(path) }
            if method == 0, compressedSize != uncompressedSize { throw ZipError.corruptEntry(path) }
            if uncompressedSize > 0, compressedSize == 0
                || Double(uncompressedSize) / Double(compressedSize) > limits.maxCompressionRatio {
                throw ZipError.suspiciousCompressionRatio(path)
            }
            totalSize += uncompressedSize
            guard totalSize <= limits.maxTotalUncompressedBytes else { throw ZipError.totalTooLarge }

            // Sizes come from the central directory, so data descriptors (flag bit 3) need no special case.
            guard try body.u32(localHeaderOffset) == Signature.localHeader,
                  try body.u16(localHeaderOffset + 26) == nameLength else {
                throw ZipError.localHeaderMismatch(path)
            }
            let localExtraLength = try body.u16(localHeaderOffset + 28)
            if hasZip64Field(try body.bytes(localHeaderOffset + 30 + nameLength, localExtraLength)) {
                throw ZipError.zip64Unsupported
            }
            let dataOffset = localHeaderOffset + 30 + nameLength + localExtraLength
            _ = try body.bytes(dataOffset, compressedSize)

            let entry = ZipEntry(
                path: path,
                uncompressedSize: uncompressedSize,
                compressedSize: compressedSize,
                isDirectory: path.hasSuffix("/")
            )
            records.append(Record(
                entry: entry,
                method: method,
                crc: UInt32(crc),
                localHeaderOffset: localHeaderOffset,
                dataOffset: dataOffset
            ))
        }

        // Entries that share bytes let a small archive expand many times (David Fifield's zip bomb).
        // Each entry spans its local header and its data. The index breaks ties so errors are stable.
        let order = records.indices.sorted {
            (records[$0].localHeaderOffset, $0) < (records[$1].localHeaderOffset, $1)
        }
        for (previous, next) in zip(order, order.dropFirst()) {
            let previousEnd = records[previous].dataOffset + records[previous].entry.compressedSize
            guard previousEnd <= records[next].localHeaderOffset else {
                throw ZipError.overlappingEntries(records[next].entry.path)
            }
        }
        return records
    }

    /// Searches backwards for the end record whose comment ends exactly at the end of the data.
    private static func endOfCentralDirectory(in archive: Reader) -> Int? {
        let last = archive.count - 22
        guard last >= 0 else { return nil }
        for offset in stride(from: last, through: max(0, last - 0xFFFF), by: -1) {
            if (try? archive.u32(offset)) == Signature.endOfCentralDirectory,
               (try? archive.u16(offset + 20)) == last - offset {
                return offset
            }
        }
        return nil
    }

    /// True if the extra field list has a ZIP64 extended information field (header ID 0x0001).
    private static func hasZip64Field(_ extra: UnsafeRawBufferPointer) -> Bool {
        let fields = Reader(buffer: extra)
        var offset = 0
        while let id = try? fields.u16(offset), let size = try? fields.u16(offset + 2) {
            if id == 0x0001 { return true }
            offset += 4 + size
        }
        return false
    }

    /// Returns the name as a String if it is a safe relative path. Otherwise throws `unsafePath`.
    private static func validatedPath(_ name: UnsafeRawBufferPointer) throws -> String {
        let path = String(decoding: name, as: UTF8.self)
        let unsafe = ZipError.unsafePath(path)
        // Lossy decoding changes the bytes only if they are not valid UTF-8.
        guard !name.isEmpty, name.count <= 255, path.utf8.elementsEqual(name),
              !name.contains(0), !name.contains(UInt8(ascii: "\\")) else { throw unsafe }
        // A drive letter such as "C:" makes the path absolute on Windows.
        if let first = path.first, first.isASCII, first.isLetter, path.dropFirst().first == ":" { throw unsafe }
        // A directory path ends with one "/". Every segment must be a real name, so a leading "/",
        // "//", "." and ".." all fail.
        let body = path.hasSuffix("/") ? path.dropLast() : Substring(path)
        for segment in body.split(separator: "/", omittingEmptySubsequences: false) {
            guard !segment.isEmpty, segment != ".", segment != ".." else { throw unsafe }
        }
        return path
    }

    /// APFS is usually case-insensitive, so "A.txt" and "a.txt" name one file, and so do "a" and "a/".
    /// String equality in Swift also treats NFC and NFD spellings as equal, as APFS does.
    private static func duplicateKey(_ path: String) -> String {
        (path.hasSuffix("/") ? String(path.dropLast()) : path).lowercased()
    }

    private static func extract(_ record: Record, from archive: Reader) throws -> Data {
        let path = record.entry.path
        let stored = try archive.bytes(record.dataOffset, record.entry.compressedSize)
        // Allocates exactly the declared size, which parse() already checked against the limits.
        var content = Data(count: record.entry.uncompressedSize)
        if !content.isEmpty {
            let complete = content.withUnsafeMutableBytes { output in
                if record.method == 0 {
                    output.copyMemory(from: stored)
                    return true
                }
                return inflate(stored, into: output)
            }
            guard complete else { throw ZipError.corruptEntry(path) }
        }
        guard content.withUnsafeBytes(crc32) == record.crc else { throw ZipError.crcMismatch(path) }
        return content
    }

    /// Decodes raw DEFLATE (RFC 1951) into `output`. Returns true only if the stream ends exactly when
    /// `output` is full. Stops at the first byte that would go past `output`.
    private static func inflate(_ input: UnsafeRawBufferPointer, into output: UnsafeMutableRawBufferPointer) -> Bool {
        guard let source = input.baseAddress, let destination = output.baseAddress else { return false }
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            return false
        }
        defer { compression_stream_destroy(stream) }
        // After `output` is full, one spare byte shows whether the stream has more data
        // or only its end marker.
        let probe = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        defer { probe.deallocate() }

        stream.pointee.src_ptr = source.assumingMemoryBound(to: UInt8.self)
        stream.pointee.src_size = input.count
        stream.pointee.dst_ptr = destination.assumingMemoryBound(to: UInt8.self)
        stream.pointee.dst_size = output.count
        var probing = false
        while true {
            let before = (stream.pointee.src_size, stream.pointee.dst_size)
            let status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
            if probing, stream.pointee.dst_size == 0 { return false }  // more bytes than declared
            switch status {
            case COMPRESSION_STATUS_END:
                return probing || stream.pointee.dst_size == 0  // fewer bytes than declared fails
            case COMPRESSION_STATUS_OK where stream.pointee.dst_size == 0:
                probing = true
                stream.pointee.dst_ptr = probe
                stream.pointee.dst_size = 1
            case COMPRESSION_STATUS_OK where (stream.pointee.src_size, stream.pointee.dst_size) != before:
                continue
            default:
                return false  // a decode error, or no progress because the input ended early
            }
        }
    }
}

// MARK: - Writing

extension ZipArchive {
    /// Raw DEFLATE of `data`, or nil if the result is not smaller than `data`.
    private static func deflate(_ data: Data) -> Data? {
        guard data.count > 1 else { return nil }
        var output = Data(count: data.count - 1)
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_encode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, destination.count,
                    source.bindMemory(to: UInt8.self).baseAddress!, source.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        // 0 means the encoded data did not fit, so deflate does not save space.
        guard written > 0 else { return nil }
        output.count = written
        return output
    }
}

private extension Data {
    mutating func le16(_ value: Int) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func le32(_ value: Int) {
        le16(value)
        le16(value >> 16)
    }
}
