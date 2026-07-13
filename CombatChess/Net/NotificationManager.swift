import Foundation
import GameKit
import Observation
import UIKit
import UserNotifications

/// Player-notification support for online matches (docs/NOTIFICATIONS.md).
///
/// The heavy lifting is serverless and free: Game Center itself pushes a
/// turn notification to the opponent's device whenever we call
/// `endTurn(withNextParticipants:turnTimeout:match:)`, and shows the text we
/// put in `GKTurnBasedMatch.message` when their app isn't frontmost. This
/// class covers the pieces GameKit leaves to us:
///
/// 1. Requesting `UNUserNotificationCenter` authorization (first online match).
/// 2. A best-effort local banner when a turn event reaches the app while it's
///    still running in the background (fallback; deduped per match).
/// 3. Acting as `UNUserNotificationCenterDelegate` so tapping one of our
///    local banners routes back into the match.
@Observable
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    /// Mirrors the system authorization state (main-thread updated).
    var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private var requestedThisLaunch = false

    // MARK: Wiring

    /// Call from the app initializer, before launching finishes, so a tap on
    /// a delivered notification can be routed even on a cold start.
    func activate() {
        UNUserNotificationCenter.current().delegate = self
        refreshAuthorizationStatus()
    }

    /// Ask for permission the first time an online match opens — the moment
    /// the value ("know when it's your move") is obvious to the player.
    /// Idempotent per launch; a no-op once the user has decided.
    func requestAuthorizationIfNeeded() {
        guard !requestedThisLaunch else { return }
        requestedThisLaunch = true
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.authorizationStatus = settings.authorizationStatus
                guard settings.authorizationStatus == .notDetermined else { return }
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            print("CombatChess online: notification authorization failed — \(error.localizedDescription)")
                        } else {
                            print("CombatChess online: notifications \(granted ? "granted" : "declined")")
                        }
                        self.refreshAuthorizationStatus()
                    }
                }
            }
        }
    }

    private func refreshAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.authorizationStatus = settings.authorizationStatus
            }
        }
    }

    // MARK: Background-turn fallback banner

    /// Posts a local banner for a turn event that arrived while the app is
    /// running in the background. Game Center's own server push normally
    /// covers this case too (docs/NOTIFICATIONS.md §2); a stable identifier
    /// per match means a repeat replaces the previous banner instead of
    /// stacking, and `clearDelivered` removes it once the match is on screen.
    func postTurnEventFallback(for match: GKTurnBasedMatch) {
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else {
            return
        }
        let localID = GKLocalPlayer.local.gamePlayerID
        // Only nudge when the event actually hands the turn to this player.
        guard match.currentParticipant?.player?.gamePlayerID == localID else { return }
        let opponentName = match.participants.first {
            $0.player?.gamePlayerID != localID
        }?.player?.displayName

        let content = UNMutableNotificationContent()
        content.title = "Combat Chess"
        // Prefer the sender's per-turn text ("ALEX captured your queen!").
        content.body = match.message ?? "Your move against \(opponentName ?? "your opponent")."
        content.sound = .default
        content.threadIdentifier = match.matchID
        content.userInfo = ["matchID": match.matchID]
        let request = UNNotificationRequest(identifier: Self.requestID(for: match.matchID),
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("CombatChess online: local notification failed — \(error.localizedDescription)")
            }
        }
    }

    /// Removes any delivered fallback banner for a match (call when the
    /// player is looking at it anyway).
    func clearDelivered(forMatchID matchID: String) {
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [Self.requestID(for: matchID)])
    }

    /// Wipe every delivered notification and the app-icon badge. Called each
    /// time the app becomes active: once the player is back in, stale banners
    /// and a lingering badge are just noise.
    ///
    /// Only DELIVERED notifications are removed — pending ones (the scheduled
    /// daily inactivity reminders) survive, so a player who opens the app but
    /// still doesn't move will keep being reminded before they forfeit.
    func clearAllDelivered() {
        let center = UNUserNotificationCenter.current()
        center.removeAllDeliveredNotifications()
        center.setBadgeCount(0) { error in
            if let error = error {
                print("CombatChess online: badge clear failed — \(error.localizedDescription)")
            }
        }
    }

    private static func requestID(for matchID: String) -> String {
        return "turn-\(matchID)"
    }

    // MARK: Daily inactivity reminders (auto-forfeit window)

    /// Schedule up to three once-a-day reminders leading up to the match's
    /// forfeit `deadline` (docs/NOTIFICATIONS.md). These fire locally on the
    /// waiting player's own device — reliable even offline — and are anchored
    /// to the real Game Center turn-timeout deadline, so "N days left" stays
    /// accurate no matter when the player last opened the app. Rescheduling
    /// replaces any earlier set for the same match.
    func scheduleTurnReminders(matchID: String, opponentName: String, deadline: Date) {
        cancelTurnReminders(matchID: matchID)
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else {
            return
        }
        let center = UNUserNotificationCenter.current()
        let day: TimeInterval = 24 * 60 * 60
        // Fire at (deadline − 3d), (−2d), (−1d): "3 / 2 / 1 day(s) left".
        for daysLeft in [3, 2, 1] {
            let fireDate = deadline.addingTimeInterval(-Double(daysLeft) * day)
            let delay = fireDate.timeIntervalSinceNow
            guard delay > 60 else { continue }   // skip windows already past

            let content = UNMutableNotificationContent()
            content.title = "Combat Chess"
            let plural = daysLeft == 1 ? "day" : "days"
            content.body = daysLeft == 1
                ? "Final day! Move against \(opponentName) or forfeit the match."
                : "\(opponentName) is waiting — it's your move. \(daysLeft) \(plural) left before you forfeit."
            content.sound = .default
            content.threadIdentifier = matchID
            content.userInfo = ["matchID": matchID]

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            let request = UNNotificationRequest(
                identifier: Self.reminderID(for: matchID, daysLeft: daysLeft),
                content: content, trigger: trigger)
            center.add(request) { error in
                if let error = error {
                    print("CombatChess online: reminder schedule failed — \(error.localizedDescription)")
                }
            }
        }
    }

    /// Cancel a match's pending inactivity reminders (the player moved, the
    /// match ended, or it's no longer their turn).
    func cancelTurnReminders(matchID: String) {
        let ids = [3, 2, 1].map { Self.reminderID(for: matchID, daysLeft: $0) }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func reminderID(for matchID: String, daysLeft: Int) -> String {
        return "reminder-\(matchID)-\(daysLeft)"
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Foreground presentation: suppress the banner when the match it refers
    /// to is already open on screen; show it otherwise.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let matchID = notification.request.content.userInfo["matchID"] as? String
        if let matchID = matchID,
           GameKitManager.shared.activeCoordinator?.match.matchID == matchID {
            completionHandler([])
            return
        }
        completionHandler([.banner, .sound, .list])
    }

    /// The player tapped one of our fallback banners: load the match fresh
    /// from Game Center and open (or refresh) its coordinator.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        guard let matchID = response.notification.request.content.userInfo["matchID"] as? String else {
            return
        }
        GKTurnBasedMatch.load(withID: matchID) { match, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("CombatChess online: load(withID:) failed — \(error.localizedDescription)")
                    return
                }
                guard let match = match else { return }
                if let coordinator = GameKitManager.shared.activeCoordinator,
                   coordinator.match.matchID == match.matchID {
                    coordinator.refresh(from: match)
                } else {
                    GameKitManager.shared.activeCoordinator = OnlineMatchCoordinator(match: match)
                }
            }
        }
    }
}
