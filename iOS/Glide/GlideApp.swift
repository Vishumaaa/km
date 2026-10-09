import SwiftUI

@main
struct GlideApp: App {
    @StateObject private var app = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .onChange(of: scenePhase) { _, phase in
                    // Drop the session when backgrounded so the Mac never keeps a stuck button.
                    if phase == .background { app.disconnect() }
                }
        }
    }
}
