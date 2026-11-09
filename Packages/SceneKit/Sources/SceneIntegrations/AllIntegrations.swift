import Foundation
import SceneEngine

/// Every integration the app runs, in the order the Apps page and the Apply sheet list them. The live tests use the
/// same list, so a full switch in a test is the app's switch.
public enum AllIntegrations {
    /// - Parameter scripts: the user's scripts from Settings, read at each detect.
    public static func make(scripts: @escaping @Sendable () -> [String]) -> [Integration] {
        [WallpaperIntegration(), AppearanceIntegration(), BordersIntegration(), AccentColorIntegration(),
         IconStyleIntegration(), GhosttyIntegration(), ITermIntegration(), KittyIntegration(),
         AlacrittyIntegration(), WarpIntegration(), RioIntegration(), RexIntegration(), BateriIntegration(), HerdrAppIntegration(),
         TerminalAppIntegration(), NeovimIntegration()] + VSCodeFamilyIntegration.all
            + [ZedIntegration(), XcodeIntegration(), HelixIntegration(), TmuxIntegration(), BatIntegration(), BtopIntegration(), DoomEmacsIntegration(),
               HerdrIntegration(), LazygitIntegration(), K9sIntegration(), ZapFastIntegration(), ScriptsIntegration(scripts: scripts)]
    }
}
