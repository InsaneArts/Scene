import Foundation
import Observation
import Sparkle

/// Sparkle, wrapped so the rest of the app never imports it: Settings reads this and calls one method.
/// Updates come from the appcast attached to the latest GitHub release (SUFeedURL), and Sparkle installs
/// one only if its EdDSA signature matches SUPublicEDKey in Config/Scene-Info.plist.
@MainActor
@Observable
final class Updater {
    static let shared = Updater()

    /// False until Sparkle starts, and while a check runs.
    private(set) var canCheckForUpdates = false
    private(set) var lastChecked: Date?
    var checksAutomatically = false {
        didSet { if controller?.updater.automaticallyChecksForUpdates != checksAutomatically { controller?.updater.automaticallyChecksForUpdates = checksAutomatically } }
    }

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private let delegate = Delegate()
    @ObservationIgnored private var observation: NSKeyValueObservation?

    /// "0.1.0 (4)", from the app's Info.plist.
    static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    /// Starts Sparkle once, at launch. Snapshot mode skips it: it never checks for updates or shows Sparkle's windows.
    func start() {
        guard controller == nil, Snapshot.folder == nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: delegate, userDriverDelegate: nil)
        self.controller = controller
        let updater = controller.updater
        checksAutomatically = updater.automaticallyChecksForUpdates
        lastChecked = updater.lastUpdateCheckDate
        canCheckForUpdates = updater.canCheckForUpdates
        observation = updater.observe(\.canCheckForUpdates, options: [.new]) { _, change in
            let can = change.newValue ?? false
            Task { @MainActor in Updater.shared.canCheckForUpdates = can }
        }
    }

    /// A check the user asked for. Sparkle shows its own window, "You're up to date" included.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    fileprivate func finishedCheck(at date: Date?) {
        lastChecked = date
    }
}

private final class Delegate: NSObject, SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        let date = updater.lastUpdateCheckDate
        Task { @MainActor in Updater.shared.finishedCheck(at: date) }
    }
}
