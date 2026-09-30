import Foundation
import SceneFoundation

/// A theme in a public GitHub repository: a Scene theme (theme.json) or an Omarchy theme (colors.toml).
/// Scene downloads the default branch as a ZIP and reads only the files a theme may hold.
public struct GitHubRepository: Sendable, Equatable {
    public var owner: String
    public var name: String

    public init(owner: String, name: String) {
        self.owner = owner
        self.name = name
    }

    /// Accepts `https://github.com/owner/repo` (with `.git`, a trailing slash, or a `/tree/…` path) and `owner/repo`.
    public init?(_ text: String) {
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://", "www."] where rest.lowercased().hasPrefix(prefix) { rest = String(rest.dropFirst(prefix.count)) }
        if rest.lowercased().hasPrefix("github.com/") { rest = String(rest.dropFirst("github.com/".count)) }
        else if rest.contains(".") && rest.split(separator: "/").first?.contains(".") == true { return nil }
        let parts = rest.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else { return nil }
        var repo = parts[1]
        if repo.lowercased().hasSuffix(".git") { repo = String(repo.dropLast(4)) }
        // GitHub names: letters, digits, "-", "_", and "."; an owner has no "." or "_".
        let owner = parts[0]
        guard owner.range(of: #"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$"#, options: .regularExpression) != nil,
              repo.range(of: #"^[A-Za-z0-9._-]{1,100}$"#, options: .regularExpression) != nil, repo != ".", repo != ".." else { return nil }
        self.owner = owner
        self.name = repo
    }

    public var url: URL { URL(string: "https://github.com/\(owner)/\(name)")! }
    /// The default branch as a ZIP archive.
    public var archiveURL: URL { URL(string: "https://github.com/\(owner)/\(name)/archive/HEAD.zip")! }

    /// The theme's folder name, as Omarchy derives it: "omarchy-aura-theme" becomes "aura".
    public var themeName: String {
        var base = name.lowercased()
        if base.hasPrefix("omarchy-") { base = String(base.dropFirst("omarchy-".count)) }
        if base.hasSuffix("-theme") { base = String(base.dropLast("-theme".count)) }
        return base.isEmpty ? name.lowercased() : base
    }

    public static let maxDownloadBytes = 150 * 1024 * 1024

    /// Downloads the archive. Stops at `maxDownloadBytes`.
    public func download(session: URLSession = .shared) async throws -> Data {
        var request = URLRequest(url: archiveURL)
        request.timeoutInterval = 60
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw SceneError.failed("GitHub sent no answer") }
        guard http.statusCode == 200 else {
            throw SceneError.failed(http.statusCode == 404 ? "\(owner)/\(name) does not exist on GitHub, or it is private" : "GitHub answered \(http.statusCode)")
        }
        var data = Data()
        if http.expectedContentLength > 0 {
            guard http.expectedContentLength <= Self.maxDownloadBytes else { throw SceneError.failed("the repository is larger than 150 MB") }
            data.reserveCapacity(Int(http.expectedContentLength))
        }
        var buffer = [UInt8]()
        buffer.reserveCapacity(1 << 16)
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count == 1 << 16 {
                data.append(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
                guard data.count <= Self.maxDownloadBytes else { throw SceneError.failed("the repository is larger than 150 MB") }
            }
        }
        data.append(contentsOf: buffer)
        return data
    }
}

extension ThemeLibrary {
    /// Paths in a repository archive that Scene reads, below the archive's top folder.
    static let repositoryPath = #"^[^/]+/(theme\.json|README\.md|colors\.toml|alacritty\.toml|wallpapers/[^/]+|backgrounds/[^/]+|apps/[^/]+\.json)$"#

    /// Installs the theme in a GitHub repository archive. A theme.json makes it a Scene theme, a colors.toml (or,
    /// without one, an alacritty.toml) an Omarchy theme.
    /// The Omarchy theme gets its name from the repository, as Omarchy names it.
    @discardableResult
    public func installRepository(archive: Data, repository: GitHubRepository) throws -> Theme {
        let limits = ZipLimits(maxEntries: 20_000, maxEntryUncompressedBytes: 40 * 1024 * 1024,
                               maxTotalUncompressedBytes: 300 * 1024 * 1024, maxCompressionRatio: 200)
        let files = try ZipArchive.read(archive, limits: limits) { $0.range(of: Self.repositoryPath, options: .regularExpression) != nil }
        let roots = Set(files.keys.map { String($0.prefix { $0 != "/" }) })
        guard roots.count <= 1 else { throw SceneError.invalid("the archive has more than one top folder") }
        let relative = Dictionary(uniqueKeysWithValues: files.map { (String($0.key.drop { $0 != "/" }.dropFirst()), $0.value) })
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("scene-github-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        let folder = staging.appendingPathComponent(repository.themeName)
        if relative["theme.json"] != nil {
            for (path, data) in relative where path.range(of: Self.allowedPath, options: .regularExpression) != nil {
                try FileOps.write(data, to: folder.appendingPathComponent(path))
            }
            return try install(folder)
        }
        guard OmarchyImporter.colorFiles.contains(where: { relative[$0] != nil }) else {
            throw SceneError.invalid("\(repository.owner)/\(repository.name) has no theme.json, colors.toml, or alacritty.toml at its top level")
        }
        for (path, data) in relative where OmarchyImporter.colorFiles.contains(path) || path.hasPrefix("backgrounds/") {
            try FileOps.write(data, to: folder.appendingPathComponent(path))
        }
        return try importOmarchy(folder: folder)
    }
}
