import SwiftUI
import AppKit

@main
struct MacTouchBarBetaApp: App {
    @StateObject private var monitor = SystemMonitor()
    @StateObject private var profileManager = ProfileManager()
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(monitor)
                .environmentObject(profileManager)
                .frame(minWidth: 960, minHeight: 620)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .appInfo) {
                Button("Sobre o MacTouchBar Studio Beta") {
                    NSApplication.shared.orderFrontStandardAboutPanel(
                        options: [
                            NSApplication.AboutPanelOptionKey.applicationName: "MacTouchBar Studio Beta",
                            NSApplication.AboutPanelOptionKey.version: "1.0.0-beta"
                        ]
                    )
                }
            }
        }
    }
}
