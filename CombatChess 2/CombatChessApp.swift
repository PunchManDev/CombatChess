import SwiftUI
import SwiftData

@main
struct CombatChessApp: App {
    var body: some Scene {
        WindowGroup {
            LandingView()
        }
        .modelContainer(for: [MatchRecord.self, FightRecord.self])
    }
}
