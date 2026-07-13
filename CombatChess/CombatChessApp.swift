import SwiftUI
import SwiftData

@main
struct CombatChessApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Install the notification delegate before launching finishes so a
        // tap on a delivered match banner routes into the match even on a
        // cold start (docs/NOTIFICATIONS.md).
        NotificationManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            LandingView()
        }
        .modelContainer(for: [MatchRecord.self, FightRecord.self])
        .onChange(of: scenePhase) { _, phase in
            // The player is back in the app: clear stale banners and the
            // app-icon badge so notifications don't pile up. Pending daily
            // reminders are untouched (docs/NOTIFICATIONS.md).
            if phase == .active {
                NotificationManager.shared.clearAllDelivered()
            }
        }
    }
}
