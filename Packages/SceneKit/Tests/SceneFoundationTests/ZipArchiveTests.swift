import Foundation
import Testing
@testable import SceneFoundation

@Suite("Create and read")
struct RoundTripTests {
    let files: [(path: String, data: Data)] = [
        ("theme.json", Data(String(repeating: "{\"accent\": \"#ff8800\", \"name\": \"Dusk\"}\n", count: 40).utf8)),
        ("wallpapers/night.bin", pseudoRandomBytes(4096)),
        ("empty.txt", Data()),
        ("Ünïcödé/fïlé.txt", Data("ok".utf8)),
    ]

    @Test func readReturnsTheFilesThatCreateWrote() throws {
        let archive = try ZipArchive.create(files: files)
        let expected = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0.data) })
        #expect(try ZipArchive.read(archive) == expected)

        let entries = try ZipArchive.entries(of: archive)
        #expect(entries.map(\.path) == files.map(\.path))
        #expect(entries.allSatisfy { !$0.isDirectory })
        #expect(entries[0].compressedSize < entries[0].uncompressedSize)   // deflated
        #expect(entries[1].compressedSize == entries[1].uncompressedSize)  // stored: deflate did not help

        // A Data slice whose indices do not start at 0 reads the same.
        #expect(try ZipArchive.read((Data([0xAA]) + archive).dropFirst()) == expected)
    }

    @Test func createIsDeterministic() throws {
        let first = try ZipArchive.create(files: files)
        #expect(try ZipArchive.create(files: files) == first)
        // Local header modification time and date: 00:00:00 on 1980-01-01.
        #expect(Array(first[10..<14]) == [0x00, 0x00, 0x21, 0x00])
    }

    @Test func emptyArchive() throws {
        let archive = try ZipArchive.create(files: [])
        #expect(archive.count == 22)
        #expect(try ZipArchive.entries(of: archive).isEmpty)
        #expect(try ZipArchive.read(archive).isEmpty)
    }

    @Test func createRejectsPathsThatReadWouldReject() {
        #expect(throws: ZipError.unsafePath("../x")) { try ZipArchive.create(files: [("../x", Data())]) }
        #expect(throws: ZipError.unsafePath("/x")) { try ZipArchive.create(files: [("/x", Data())]) }
        #expect(throws: ZipError.unsafePath("dir/")) { try ZipArchive.create(files: [("dir/", Data())]) }
        #expect(throws: ZipError.duplicatePath("A.txt")) {
            try ZipArchive.create(files: [("a.txt", Data()), ("A.txt", Data())])
        }
    }

    @Test func crc32MatchesTheStandardCheckValue() {
        #expect(Data("123456789".utf8).withUnsafeBytes(ZipArchive.crc32) == 0xCBF4_3926)
    }
}

@Suite("macOS tools")
struct InteropTests {
    let tree: [String: Data] = [
        "theme.json": Data(String(repeating: "{\"background\": \"#1e1e2e\", \"foreground\": \"#cdd6f4\"}\n", count: 50).utf8),
        "colors/dark.txt": Data("dark".utf8),
        "colors/café.txt": Data("latte".utf8),
        "empty.txt": Data(),
        "noise.bin": pseudoRandomBytes(2048),
    ]

    @Test func readsArchiveFromZip() throws {
        try withTemporaryDirectory { directory in
            let source = directory.appendingPathComponent("source")
            try writeFiles(tree, under: source)
            let result = try run("/usr/bin/zip", ["-q", "-r", "../out.zip", "."], in: source)
            #expect(result.status == 0, "\(result.output)")
            let archive = try Data(contentsOf: directory.appendingPathComponent("out.zip"))
            try expectArchive(archive, holds: tree)
        }
    }

    @Test func readsArchiveFromDitto() throws {
        try withTemporaryDirectory { directory in
            try writeFiles(tree, under: directory.appendingPathComponent("source"))
            let arguments = ["-c", "-k", "--norsrc", "--noextattr", "source", "out.zip"]
            let result = try run("/usr/bin/ditto", arguments, in: directory)
            #expect(result.status == 0, "\(result.output)")
            let archive = try Data(contentsOf: directory.appendingPathComponent("out.zip"))
            try expectArchive(archive, holds: tree)
        }
    }

    @Test func unzipAcceptsOurArchive() throws {
        try withTemporaryDirectory { directory in
            let url = directory.appendingPathComponent("ours.zip")
            let files = tree.sorted { $0.key < $1.key }.map { (path: $0.key, data: $0.value) }
            try ZipArchive.create(files: files).write(to: url)
            let result = try run("/usr/bin/unzip", ["-t", url.path], in: directory)
            #expect(result.status == 0, "\(result.output)")
            #expect(result.output.contains("No errors detected"), "\(result.output)")
            #expect(result.output.components(separatedBy: "testing:").count - 1 == files.count, "\(result.output)")
        }
    }

    /// Checks the file contents, and that the tool's DEFLATE data went through our decoder.
    private func expectArchive(_ archive: Data, holds files: [String: Data]) throws {
        #expect(try ZipArchive.read(archive) == files)
        let entries = try ZipArchive.entries(of: archive)
        let theme = try #require(entries.first { $0.path == "theme.json" })
        #expect(theme.compressedSize < theme.uncompressedSize)
    }
}

@Suite("Archive structure")
struct StructureTests {
    @Test func findsEndRecordBeforeTrailingComment() throws {
        var archive = try ZipArchive.create(files: [("a.txt", Data("hello".utf8))])
        // The comment starts with a fake end record signature that the search must skip.
        let comment = Array("PK\u{05}\u{06} exported by Scene, not a real end record".utf8)
        archive[archive.count - 2] = UInt8(comment.count)
        archive.append(contentsOf: comment)
        #expect(try ZipArchive.read(archive) == ["a.txt": Data("hello".utf8)])
    }

    @Test func dataDescriptorEntryUsesCentralDirectorySizes() throws {
        let text = "streamed content, streamed content"
        var entry = RawEntry("a.txt", text, method: 8)
        entry.flags = 8  // local header sizes and CRC are 0, a data descriptor follows the data
        #expect(try ZipArchive.read(makeZip([entry])) == ["a.txt": Data(text.utf8)])
    }

    @Test func directoryEntryIsListedButNotRead() throws {
        var directory = RawEntry("assets/", "")
        directory.externalAttributes = 0o040755 << 16
        let archive = makeZip([directory, RawEntry("assets/a.txt")])
        #expect(try ZipArchive.entries(of: archive) == [
            ZipEntry(path: "assets/", uncompressedSize: 0, compressedSize: 0, isDirectory: true),
            ZipEntry(path: "assets/a.txt", uncompressedSize: 5, compressedSize: 5, isDirectory: false),
        ])
        #expect(try ZipArchive.read(archive) == ["assets/a.txt": Data("hello".utf8)])
    }
}

@Suite("Malicious archives")
struct MaliciousArchiveTests {
    @Test(arguments: [
        "../evil", "a/../../evil", "..", "/etc/x", "/", "..\\evil", "a\\b.txt", "C:/x", "c:x",
        "", "a\0b", "a//b", "./a", "a/./b", String(repeating: "a", count: 256),
    ])
    func rejectsUnsafePath(_ name: String) {
        expect(.unsafePath(name), reading: makeZip([RawEntry(name)]))
    }

    @Test func acceptsPathOf255Bytes() throws {
        let name = String(repeating: "a", count: 255)
        #expect(try ZipArchive.read(makeZip([RawEntry(name)])) == [name: Data("hello".utf8)])
    }

    @Test func rejectsNameThatIsNotUTF8() {
        var entry = RawEntry("x")
        entry.name = [0x66, 0xFF, 0x6F]
        expect(.unsafePath("f\u{FFFD}o"), reading: makeZip([entry]))
    }

    @Test func rejectsSymlink() {
        var link = RawEntry("link", "/etc/passwd")
        link.externalAttributes = 0o120777 << 16
        expect(.symlink("link"), reading: makeZip([link]))
    }

    @Test func rejectsDuplicatePaths() {
        expect(.duplicatePath("readme.txt"), reading: makeZip([RawEntry("README.txt"), RawEntry("readme.txt")]))
        expect(.duplicatePath("a/"), reading: makeZip([RawEntry("a"), RawEntry("a/", "")]))
        let precomposed = RawEntry("caf\u{E9}.txt")
        let decomposed = RawEntry("cafe\u{301}.txt")
        expect(.duplicatePath("cafe\u{301}.txt"), reading: makeZip([precomposed, decomposed]))
    }

    @Test func rejectsEncryptedEntry() {
        var entry = RawEntry("a.txt")
        entry.flags = 1
        expect(.encrypted, reading: makeZip([entry]))
    }

    @Test func rejectsUnsupportedMethod() {
        var entry = RawEntry("a.txt")
        entry.method = 12  // bzip2
        expect(.unsupportedMethod(12), reading: makeZip([entry]))
    }

    @Test func rejectsZip64() {
        var sentinelSize = RawEntry("a.txt")
        sentinelSize.uncompressedSize = 0xFFFF_FFFF
        expect(.zip64Unsupported, reading: makeZip([sentinelSize]))

        let zip64Field: [UInt8] = [0x01, 0x00, 0x08, 0x00, 5, 0, 0, 0, 0, 0, 0, 0]
        var centralField = RawEntry("a.txt")
        centralField.centralExtra = zip64Field
        expect(.zip64Unsupported, reading: makeZip([centralField]))

        var localField = RawEntry("a.txt")
        localField.localExtra = zip64Field
        expect(.zip64Unsupported, reading: makeZip([localField]))

        expect(.zip64Unsupported, reading: makeZip([RawEntry("a.txt")], zip64Locator: true))
    }

    @Test func rejectsMultiDiskArchive() {
        expect(.multiDisk, reading: makeZip([RawEntry("a.txt")], disk: 1))
    }

    @Test func rejectsTruncatedArchive() {
        let archive = makeZip([RawEntry("a.txt", String(repeating: "x", count: 100))])
        // The end record is cut off.
        expect(.truncated, reading: archive.prefix(archive.count - 30))
        // The end record is intact, but the central directory it points to is gone.
        expect(.truncated, reading: archive.prefix(40) + archive.suffix(22))
        // The entry claims more data than lies before the central directory.
        var overlong = RawEntry("a.txt", "hello hello", method: 8)
        overlong.compressedSize = 10_000
        expect(.truncated, reading: makeZip([overlong]))
    }

    @Test func rejectsCRCMismatch() throws {
        var entry = RawEntry("a.txt")
        entry.crc = 0xDEAD_BEEF
        let archive = makeZip([entry])
        #expect(try ZipArchive.entries(of: archive).count == 1)  // entries(of:) does not decompress
        expect(.crcMismatch("a.txt"), reading: archive)
    }

    @Test func rejectsRatioBomb() {
        // 30 MB of zeros deflates to about 30 KB.
        var bomb = RawEntry("bomb.bin", "", method: 8)
        bomb.content = Data(count: 30 * 1024 * 1024)
        bomb.crc = 0  // never checked: the declared sizes reject the entry first
        let archive = makeZip([bomb])
        expect(.entryTooLarge("bomb.bin"), reading: archive)
        // With the size limits raised, the ratio of about 1000:1 still rejects it.
        let raised = ZipLimits(maxEntryUncompressedBytes: 64 << 20, maxTotalUncompressedBytes: 64 << 20)
        expect(.suspiciousCompressionRatio("bomb.bin"), reading: archive, limits: raised)
    }

    @Test func rejectsDataThatDoesNotMatchDeclaredSize() {
        // 1 MB of zeros deflates to about 1 KB. A declared size of 1,000 bytes keeps the ratio low,
        // so only the output cap during decompression catches the lie.
        var longer = RawEntry("longer.bin", "", method: 8)
        longer.content = Data(count: 1 << 20)
        longer.uncompressedSize = 1000
        expect(.corruptEntry("longer.bin"), reading: makeZip([longer]))

        var shorter = RawEntry("shorter.txt", "hello hello hello", method: 8)
        shorter.uncompressedSize = 100
        expect(.corruptEntry("shorter.txt"), reading: makeZip([shorter]))

        // The deflate stream stops halfway, so the decoder runs out of input before its end marker.
        let lines = (0..<100).map { "line \($0)\n" }.joined()
        var cut = RawEntry("cut.txt", lines, method: 8)
        cut.compressedSize = deflated(Data(lines.utf8)).count / 2
        expect(.corruptEntry("cut.txt"), reading: makeZip([cut]))

        var stored = RawEntry("stored.txt")
        stored.uncompressedSize = 3
        expect(.corruptEntry("stored.txt"), reading: makeZip([stored]))
    }

    @Test func rejectsTotalAboveLimit() {
        let entries = (1...3).map { RawEntry("f\($0).txt", String(repeating: "x", count: 60)) }
        let limits = ZipLimits(maxEntryUncompressedBytes: 100, maxTotalUncompressedBytes: 150)
        expect(.totalTooLarge, reading: makeZip(entries), limits: limits)
    }

    @Test func rejectsOverlappingEntries() {
        // Two central directory entries share one local header and its data.
        var twin = RawEntry("b.txt")
        twin.localHeaderOffset = 0
        expect(.overlappingEntries("b.txt"), reading: makeZip([RawEntry("a.txt"), twin]))

        // Fifield's construction: the data of a.txt holds the complete local header and data of b.txt.
        var outer = RawEntry("a.txt")
        outer.content = makeZip([RawEntry("b.txt", "kernel")]).prefix(30 + 5 + 6)
        var quoted = RawEntry("b.txt", "kernel")
        quoted.localHeaderOffset = 30 + 5
        expect(.overlappingEntries("b.txt"), reading: makeZip([outer, quoted]))
    }

    @Test func rejectsTooManyEntries() throws {
        let files = (0..<65).map { (path: "f\($0).txt", data: Data("x".utf8)) }
        expect(.tooManyEntries, reading: try ZipArchive.create(files: files))
        #expect(try ZipArchive.read(ZipArchive.create(files: Array(files.prefix(64)))).count == 64)
    }

    @Test func rejectsLocalHeaderThatDisagrees() {
        var wrongLength = RawEntry("a.txt")
        wrongLength.localNameLength = 4
        expect(.localHeaderMismatch("a.txt"), reading: makeZip([wrongLength]))

        var wrongSignature = RawEntry("a.txt")
        wrongSignature.localSignature = 0x0201_4B50
        expect(.localHeaderMismatch("a.txt"), reading: makeZip([wrongSignature]))
    }

    @Test func rejectsDataThatIsNotAZip() {
        expect(.notAZip, reading: Data())
        expect(.notAZip, reading: Data("plain text, no end of central directory record".utf8))
    }
}
