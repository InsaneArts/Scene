import Foundation
import SceneFoundation

/// Scene's command line for theme authors and agents. It checks and builds a theme draft with the same code as the
/// Theme Maker:
///
///     Scene --check-theme draft.json
///     Scene --build-theme draft.json <folder> [--install]
///
/// Each problem is one line that starts with `error` or `warning`. The exit status is 0 when the draft has no errors,
/// 1 when it has errors, and 2 for a wrong command.
public enum ThemeTool {
    public static let usage = """
    usage: Scene --check-theme <draft.json>
           Scene --build-theme <draft.json> <folder> [--install]
    """

    /// Runs a command, or returns nil when the arguments hold none. `install` adds a built theme folder to Scene.
    public static func run(_ arguments: [String], install: (URL) throws -> Void, print: (String) -> Void) -> Int32? {
        guard let index = arguments.firstIndex(where: { $0 == "--check-theme" || $0 == "--build-theme" }) else { return nil }
        let building = arguments[index] == "--build-theme"
        let rest = Array(arguments[(index + 1)...])
        let paths = rest.filter { !$0.hasPrefix("-") }
        guard let path = paths.first, !building || paths.count >= 2 else { print(usage); return 2 }

        let draft: ThemeDraft
        do { draft = try ThemeDraft.read(URL(fileURLWithPath: path)) }
        catch { print("error   \(error)"); return 1 }
        let issues = draft.check()
        for issue in issues { print("\(issue.isError ? "error  " : "warning") \(issue.message)") }
        guard !issues.contains(where: \.isError) else { print("Fix the errors, then run this again."); return 1 }
        guard building else { print("ok      \(draft.name) is ready to build"); return 0 }

        let folder = URL(fileURLWithPath: paths[1])
        do {
            try draft.write(to: folder)
            print("ok      Built \(draft.name) in \(folder.standardizedFileURL.path)")
            if rest.contains("--install") {
                try install(folder)
                print("ok      Installed \(draft.name) in Scene")
            }
            return 0
        } catch let error as ThemeLoadError {
            error.errors.forEach { print("error   \($0)") }
            return 1
        } catch {
            print("error   \(error)")
            return 1
        }
    }
}
