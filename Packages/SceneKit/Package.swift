// swift-tools-version: 6.0
import PackageDescription

// Scene's core, as modules with one-way dependencies:
// SceneFoundation ← SceneThemes ← SceneRenderers, SceneEngine ← SceneIntegrations. SceneSwitcher stands alone.
let package = Package(
    name: "SceneKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SceneFoundation", targets: ["SceneFoundation"]),
        .library(name: "SceneThemes", targets: ["SceneThemes"]),
        .library(name: "SceneRenderers", targets: ["SceneRenderers"]),
        .library(name: "SceneEngine", targets: ["SceneEngine"]),
        .library(name: "SceneIntegrations", targets: ["SceneIntegrations"]),
        .library(name: "SceneSwitcher", targets: ["SceneSwitcher"]),
    ],
    targets: [
        // ZIP, JSONC, safe file writes, anchor blocks, processes. Knows nothing about themes.
        .target(name: "SceneFoundation"),
        // The theme format: colors, model, validation, library, and the Omarchy importer.
        .target(name: "SceneThemes", dependencies: ["SceneFoundation"]),
        // Pure functions from a resolved theme to each app's files.
        .target(name: "SceneRenderers", dependencies: ["SceneThemes", "SceneFoundation"]),
        // Plans, apply, journal, ledger, restore, system services, and the experimental tier.
        .target(name: "SceneEngine", dependencies: ["SceneThemes", "SceneFoundation"]),
        // One integration per app or system surface.
        .target(name: "SceneIntegrations", dependencies: ["SceneEngine", "SceneRenderers", "SceneThemes", "SceneFoundation"]),
        // Carousel selection and global shortcut rules for the theme switcher.
        .target(name: "SceneSwitcher"),

        // Fixture homes, fake system services, and repository paths for the test targets.
        .target(name: "SceneTestSupport", dependencies: ["SceneEngine", "SceneRenderers", "SceneThemes", "SceneFoundation"]),
        .testTarget(name: "SceneFoundationTests", dependencies: ["SceneFoundation"]),
        .testTarget(name: "SceneThemesTests", dependencies: ["SceneThemes", "SceneFoundation", "SceneTestSupport"]),
        .testTarget(name: "SceneRenderersTests", dependencies: ["SceneRenderers", "SceneThemes", "SceneFoundation", "SceneTestSupport"]),
        .testTarget(name: "SceneEngineTests", dependencies: ["SceneEngine", "SceneFoundation", "SceneTestSupport"]),
        .testTarget(name: "SceneIntegrationsTests", dependencies: ["SceneIntegrations", "SceneEngine", "SceneRenderers", "SceneThemes", "SceneFoundation", "SceneTestSupport"]),
        .testTarget(name: "SceneSwitcherTests", dependencies: ["SceneSwitcher"]),
        // Changes this Mac's real setup, so it only runs with SCENE_LIVE=1 and stays out of the app scheme.
        .testTarget(name: "SceneLiveTests", dependencies: ["SceneIntegrations", "SceneEngine", "SceneThemes", "SceneFoundation", "SceneTestSupport"]),
    ]
)
