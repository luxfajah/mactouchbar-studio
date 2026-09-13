import SwiftUI

@main
struct MacTouchBarApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .statusBar(hidden: true)
                .persistentSystemOverlays(.hidden)
                .edgesIgnoringSafeArea(.all)
        }
    }
}
