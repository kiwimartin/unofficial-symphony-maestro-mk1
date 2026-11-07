import SwiftUI
import LegacyMaestroUI

/// Separate unsigned developer GUI. No shipping AppState, Sparkle updater,
/// driver activation, reconnect timers, MK I control writes or audio startup.
@main
struct LegacyMaestroPreviewApp: App {
    var body: some Scene {
        WindowGroup("Legacy Symphony – Developer Preview") {
            ScrollView {
                LegacyControlWorkspaceView().padding(24)
            }.frame(minWidth: 950, minHeight: 600)
        }.defaultSize(width: 1100, height: 800)
    }
}
