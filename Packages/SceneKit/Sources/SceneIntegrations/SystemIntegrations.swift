import Foundation
import SceneEngine
import SceneRenderers
import SceneThemes
import SceneFoundation

/// Foundation also declares `Operation`. This makes the engine's type win everywhere in this module.
typealias Operation = SceneEngine.Operation

// MARK: - Wallpaper

public struct WallpaperIntegration: Integration {
    public let id = "wallpaper"
    public let displayName = "Wallpaper"
    public let kind = IntegrationKind.system
    public init() {}

    public func detect(_ env: SceneEnvironment, _ services: SystemServices) async -> Detection {
        let displays = await services.displays()
        return Detection(installed: !displays.isEmpty,
                         detail: displays.count == 1 ? "1 display" : "\(displays.count) displays",
                         context: ["displays": displays.map(String.init).joined(separator: ",")])
    }

    public func plan(_ request: ApplyRequest, _ detection: Detection, _ env: SceneEnvironment) throws -> IntegrationPlan {
        guard let wallpaper = request.wallpaper else {
            return IntegrationPlan(notes: ["This theme has no wallpaper for \(request.current.appearance.rawValue) mode"])
        }
        // Copy into Scene's folder so the wallpaper keeps working if the theme is removed or the app moves.
        // Each wallpaper gets its own file. Scene checks a display's wallpaper by path, so a new image needs a new path.
        let safeID = request.current.themeID.replacingOccurrences(of: "/", with: "-")
        let destination = env.appSupport.appendingPathComponent("Wallpapers/\(safeID)-\(wallpaper.name)")
        let data = try Data(contentsOf: wallpaper.url)
        var operations: [Operation] = [.writeManagedFile(path: destination.path, contents: data)]
        for id in detection.context["displays", default: ""].split(separator: ",").compactMap({ UInt32($0) }) {
            operations.append(.setWallpaper(displayID: id, imagePath: destination.path, fit: wallpaper.fit))
        }
        return IntegrationPlan(operations: operations, notes: ["macOS changes the current Space of each display"])
    }

    public func verify(_ plan: IntegrationPlan, _ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> Verification {
        for op in plan.operations {
            if case let .setWallpaper(id, path, _) = op {
                let actual = await services.wallpaper(displayID: id)
                if actual != path { return .mismatch("Display \(id) shows \(actual.map { ($0 as NSString).lastPathComponent } ?? "no wallpaper"), not the theme's wallpaper") }
            }
        }
        return Self.verifyFiles(plan)
    }
}

// MARK: - Light/Dark

public struct AppearanceIntegration: Integration {
    public let id = "appearance"
    public let displayName = "Light/Dark"
    public let kind = IntegrationKind.system
    public init() {}

    public func detect(_ env: SceneEnvironment, _ services: SystemServices) async -> Detection {
        let state = await services.appearance()
        let privatePath = services.tweakAvailability("appearance") == .available
        let detail = (state.auto ? "Auto, currently " : "") + (state.dark ? "Dark" : "Light")
        return Detection(installed: true, detail: detail, support: privatePath ? .experimental(tested: true) : .scripting,
                         context: ["dark": state.dark ? "1" : "0", "auto": state.auto ? "1" : "0",
                                   "private": privatePath ? "1" : "0", "canRestoreAuto": services.canRestoreAuto() ? "1" : "0"])
    }

    public func plan(_ request: ApplyRequest, _ detection: Detection, _ env: SceneEnvironment) throws -> IntegrationPlan {
        guard let forced = request.forcedAppearance else {
            return IntegrationPlan(notes: ["Keeps your macOS setting. Apps switch between the light and dark variants on their own."])
        }
        let dark = forced == .dark
        var plan = IntegrationPlan(operations: [.setAppearance(dark: dark)])
        if detection.context["private"] != "1" { plan.requirements.append(.automation("System Events")) }
        if detection.context["auto"] == "1" {
            plan.notes.append(detection.context["canRestoreAuto"] == "1"
                ? "Your Mac switches Light and Dark automatically. Restore turns Auto back on."
                : "Your Mac switches Light and Dark automatically. Scene can set \(dark ? "Dark" : "Light") but cannot turn Auto back on unless the experimental setting is on.")
        }
        return plan
    }

    public func verify(_ plan: IntegrationPlan, _ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> Verification {
        guard case let .setAppearance(dark)? = plan.operations.first else { return .matches }
        return await services.appearance().dark == dark ? .matches : .mismatch("macOS did not switch to \(dark ? "Dark" : "Light")")
    }
}

// MARK: - Experimental: accent color

public struct AccentColorIntegration: Integration {
    public let id = "accent"
    public let displayName = "Accent color"
    public let kind = IntegrationKind.experimental
    public init() {}

    public func detect(_ env: SceneEnvironment, _ services: SystemServices) async -> Detection {
        if case .disabled(let reason) = services.tweakAvailability("accent") {
            return Detection(installed: true, support: .experimental(tested: false), setup: .blocked(reason))
        }
        var detail = "Experimental"
        if case .number(let value)? = try? await services.tweakGet("accent"), let preset = AccentPreset(rawValue: Int(value)) {
            detail = "Currently \(preset.name)"
        }
        return Detection(installed: true, detail: detail, support: .experimental(tested: true))
    }

    public func plan(_ request: ApplyRequest, _ detection: Detection, _ env: SceneEnvironment) throws -> IntegrationPlan {
        guard let accent = request.current.system.accent else { return IntegrationPlan(notes: ["This theme does not set an accent color"]) }
        return IntegrationPlan(operations: [.setTweak(id: "accent", value: .number(Double(accent.rawValue)))],
                               notes: ["Uses a private macOS call (experimental). Accent: \(accent.name)."])
    }

    public func verify(_ plan: IntegrationPlan, _ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> Verification {
        guard case let .setTweak(_, value)? = plan.operations.first else { return .matches }
        return (try? await services.tweakGet("accent")) == value ? .matches : .mismatch("The accent color did not change")
    }
}

// MARK: - Experimental: icon and widget style

public struct IconStyleIntegration: Integration {
    public let id = "iconStyle"
    public let displayName = "Icon & widget style"
    public let kind = IntegrationKind.experimental
    public init() {}

    public func detect(_ env: SceneEnvironment, _ services: SystemServices) async -> Detection {
        if case .disabled(let reason) = services.tweakAvailability("iconStyle") {
            return Detection(installed: true, support: .experimental(tested: false), setup: .blocked(reason))
        }
        var detail = "Experimental"
        if case .object(let members)? = try? await services.tweakGet("iconStyle"),
           case .string(let style)? = members.first(where: { $0.key == "style" })?.value {
            detail = "Currently \(style)"
        }
        return Detection(installed: true, detail: detail, support: .experimental(tested: true))
    }

    public func plan(_ request: ApplyRequest, _ detection: Detection, _ env: SceneEnvironment) throws -> IntegrationPlan {
        let variant = request.current
        guard let style = variant.system.iconStyle else { return IntegrationPlan(notes: ["This theme does not set an icon style"]) }
        let followsSystem = request.forcedAppearance == nil && request.theme.variants.count == 2
        let tone = followsSystem ? "Automatic" : (variant.appearance == .dark ? "Dark" : "Light")
        let name: String
        switch style {
        case .default: name = "RegularLight"
        case .dark: name = "RegularDark"
        case .clear: name = "Clear\(tone)"
        case .tinted: name = "Tinted\(tone)"
        }
        var members = [JSONMember("style", .string(name))]
        if style == .tinted {
            switch variant.system.iconTint {
            case .preset(let preset)?: members.append(JSONMember("tint", .string(Self.tintName(preset))))
            case .custom(let color)?: members.append(JSONMember("tint", .string("Other"))); members.append(JSONMember("custom", .string(color.hex)))
            case nil: members.append(JSONMember("tint", .string("Other"))); members.append(JSONMember("custom", .string(variant.interface.accent.hex)))
            }
        }
        return IntegrationPlan(operations: [.setTweak(id: "iconStyle", value: .object(members))],
                               notes: ["Uses a private macOS call (experimental). Apps with older icon formats keep their icons."])
    }

    static func tintName(_ preset: AccentPreset) -> String {
        switch preset {
        case .graphite: "Graphite"
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .blue: "Blue"
        case .purple: "Purple"
        case .pink: "Pink"
        case .multicolor, .hardware: "Hardware"
        }
    }

    public func verify(_ plan: IntegrationPlan, _ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> Verification {
        guard case let .setTweak(_, .object(wanted))? = plan.operations.first,
              case .object(let current)? = try? await services.tweakGet("iconStyle") else { return .mismatch("Could not read the icon style back") }
        let style = { (m: [JSONMember]) in m.first { $0.key == "style" }?.value }
        return style(wanted) == style(current) ? .matches : .mismatch("The icon style did not change")
    }
}

// MARK: - JankyBorders

public struct BordersIntegration: Integration {
    public let id = "borders"
    public let displayName = "JankyBorders"
    public let kind = IntegrationKind.system
    public init() {}

    /// borders runs `~/.config/borders/bordersrc`, or `~/.bordersrc`, when it starts without arguments. It ignores XDG_CONFIG_HOME.
    static func script(_ env: SceneEnvironment) -> URL {
        let candidates = [env.home.appendingPathComponent(".config/borders/bordersrc"), env.home.appendingPathComponent(".bordersrc")]
        return candidates.first { FileOps.exists($0) } ?? candidates[0]
    }

    public func detect(_ env: SceneEnvironment, _ services: SystemServices) async -> Detection {
        guard let borders = env.locateExecutable("borders") else { return .notInstalled() }
        let script = Self.script(env)
        return Detection(installed: true, detail: Operation.tilde(script.path),
                         conflicts: ["borders reads this file only when it starts without arguments. If something starts it with arguments, such as AeroSpace, the colors last until borders restarts."],
                         context: ["borders": borders.path, "script": script.path])
    }

    public func plan(_ request: ApplyRequest, _ detection: Detection, _ env: SceneEnvironment) throws -> IntegrationPlan {
        // The block comes last, so its colors win over the options before it.
        let line = (["borders"] + BordersRenderer.arguments(request.current)).joined(separator: " ")
        return IntegrationPlan(operations: [
            .ensureAnchor(path: detection.context["script"]!, block: Anchor.block(lines: [line], comment: "#"), placement: .end),
        ], conflicts: detection.conflicts)
    }

    /// Sends the file's colors to the running instance. `borders` with arguments starts a new instance when none runs,
    /// so it is called only while one runs.
    public func reload(_ detection: Detection, _ env: SceneEnvironment, _ services: SystemServices) async -> ReloadResult {
        guard let borders = detection.context["borders"], let script = detection.context["script"] else { return .notNeeded }
        guard !services.processes(named: "borders").isEmpty else { return .notRunning }
        let colors = FileOps.read(URL(fileURLWithPath: script)).map { BordersRenderer.colors(in: String(decoding: $0, as: UTF8.self)) } ?? []
        guard !colors.isEmpty else { return .needsRestart("Restart borders to see your own colors again.") }
        guard let result = try? await services.run(borders, colors, environment: nil) else { return .failed("could not run borders") }
        return result.status == 0 ? .reloaded : .failed(result.stderr)
    }
}
