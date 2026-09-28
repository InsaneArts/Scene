import CryptoKit
import Foundation

/// Safe file mechanics: atomic writes that keep symlinks, hashes, and backups.
public enum FileOps {
    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256(fileAt url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return sha256(data)
    }

    /// Follows symlinks so a write lands in the link target and the link itself stays.
    public static func resolvedTarget(_ url: URL) -> URL {
        var current = url
        for _ in 0..<16 {
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: current.path) else { return current }
            current = URL(fileURLWithPath: destination, relativeTo: current.deletingLastPathComponent()).standardizedFileURL
        }
        return current
    }

    public static func isWritable(_ url: URL) -> Bool {
        let target = resolvedTarget(url)
        let fm = FileManager.default
        if fm.fileExists(atPath: target.path) { return fm.isWritableFile(atPath: target.path) }
        var dir = target.deletingLastPathComponent()
        while !fm.fileExists(atPath: dir.path) && dir.path != "/" { dir.deleteLastPathComponent() }
        return fm.isWritableFile(atPath: dir.path)
    }

    /// Writes `data` atomically: a temporary file in the target's folder, flushed, then renamed over the target.
    /// Keeps the permissions of an existing file.
    public static func write(_ data: Data, to url: URL) throws {
        let target = resolvedTarget(url)
        let fm = FileManager.default
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temp = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).scene-\(UUID().uuidString.prefix(8))")
        guard fm.createFile(atPath: temp.path, contents: nil) else { throw SceneError.failed("cannot create \(temp.path)") }
        do {
            let handle = try FileHandle(forWritingTo: temp)
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            if let attributes = try? fm.attributesOfItem(atPath: target.path), let permissions = attributes[.posixPermissions] {
                try fm.setAttributes([.posixPermissions: permissions], ofItemAtPath: temp.path)
            }
            if rename(temp.path, target.path) != 0 { throw SceneError.failed("rename failed: \(String(cString: strerror(errno)))") }
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }

    public static func write(_ text: String, to url: URL) throws { try write(Data(text.utf8), to: url) }

    public static func read(_ url: URL) -> Data? { try? Data(contentsOf: url) }

    public static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    public static func delete(_ url: URL) throws {
        let target = resolvedTarget(url)
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
    }

    /// Copies a file's current bytes into the backup folder and returns the backup's relative name.
    public static func backup(_ url: URL, into folder: URL) throws -> String? {
        let target = resolvedTarget(url)
        guard let data = try? Data(contentsOf: target) else { return nil }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8))-\(target.lastPathComponent)"
        try data.write(to: folder.appendingPathComponent(name), options: .atomic)
        return name
    }
}
