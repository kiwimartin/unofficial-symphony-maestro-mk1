import SwiftUI
import AppKit
import Foundation
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
                .onAppear {
                    // CI exercises real dyld/SwiftUI/AppKit startup, with no
                    // diagnostic refresh, driver activation or audio operation.
                    if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            guard NSApplication.shared.windows.contains(where: { $0.isVisible && !$0.frame.isEmpty }) else {
                                FileHandle.standardError.write(Data("Preview window was not visible\n".utf8))
                                exit(3)
                            }
                            FileHandle.standardOutput.write(Data("LEGACY_PREVIEW_SMOKE_OK\n".utf8))
                            NSApplication.shared.terminate(nil)
                        }
                    }
                }
        }.defaultSize(width: 1100, height: 800)
    }
}
