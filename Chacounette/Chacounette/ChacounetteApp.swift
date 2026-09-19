import SwiftUI

@main
struct ChacounetteApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    // Garde le rappel quotidien programmé (s'il est activé)
                    NotificationManager.shared.refreshIfEnabled()
                }
        }
    }
}
