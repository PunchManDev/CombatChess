import Foundation
import GameKit
import Observation

// MARK: - Wire protocol (docs/ONLINE_MULTIPLAYER.md)

/// Messages exchanged between players. Chess-layer messages travel inside
/// `GKTurnBasedMatch` turn data; fight-layer messages over real-time `GKMatch`.
enum NetMessage: Codable {
    // Chess layer (turn-based payload)
    case chessMove(uci: String)
    case cardChallenge(accepted: Bool)
    case checkFight
    case fightResult(defenderWon: Bool, attackerHP: Int, defenderHP: Int, inputHash: UInt64)
    case resignation
    // Fight layer (real-time session)
    case fightStart(seed: UInt64)
    case fightInput(tick: Int, inputs: [FightInput])
    case fightChecksum(tick: Int, checksum: UInt64)
    case fightStateSnapshot(tick: Int, hpA: Int, hpB: Int, staminaA: Int, staminaB: Int)
}

/// One tick's worth of player input in the fight sim (lockstep, M3).
enum FightInput: String, Codable {
    case none
    case punchL, punchR
    case blockLDown, blockLUp
    case blockRDown, blockRUp
    case dodge
    case star
}

// MARK: - Game Center manager

/// Online-play foundation: Game Center authentication, turn-based chess
/// matches, and real-time fight sessions.
///
/// Status: auth + matchmaking entry points are functional; turn routing into
/// `MatchController` lands with milestone M1 (docs/ONLINE_MULTIPLAYER.md §6).
@Observable
final class GameKitManager: NSObject {
    static let shared = GameKitManager()

    var isAuthenticated = false
    var authErrorMessage: String?
    /// The online match currently open on this device (drives the match UI).
    var activeCoordinator: OnlineMatchCoordinator?
    /// Matches where the local player is an invited-but-unjoined participant
    /// (docs/INVITE_FLOW.md). Drives the "Challenge waiting" UI on the
    /// landing screen — the invite-to-install recovery path.
    var pendingInvites: [GKTurnBasedMatch] = []
    /// In-progress matches the local player has joined (status open/matching,
    /// local participant `.active`). Drives the "Your Games" list on the
    /// landing screen. Invited-but-unjoined matches live in `pendingInvites`.
    var activeMatches: [GKTurnBasedMatch] = []

    private var listenerRegistered = false

    /// One invite blurb everywhere (matchmaker sheet + Game Center resends).
    static let inviteMessage = "Combat Chess — your pieces won't capture themselves."

    // MARK: Authentication

    /// Call once at launch (idempotent). Presents Apple's sign-in sheet when
    /// Game Center needs it.
    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            DispatchQueue.main.async {
                if let viewController = viewController {
                    Self.topViewController()?.present(viewController, animated: true)
                    return
                }
                guard let self = self else { return }
                self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                self.authErrorMessage = error?.localizedDescription
                if self.isAuthenticated && !self.listenerRegistered {
                    GKLocalPlayer.local.register(self)
                    self.listenerRegistered = true
                }
                if self.isAuthenticated {
                    // Invite-to-install: a player who installed the app
                    // because of an invite never got the push (it fired
                    // pre-install), but the invited match is waiting on
                    // their Game Center account. Sweep for it now (also
                    // fills the "Your Games" list).
                    self.refreshMatches()
                }
            }
        }
    }

    // MARK: Turn-based chess matches (M1)

    /// Presents the system matchmaker (friend invites + auto-match).
    /// Pass `recipients` to pre-fill the invitees (e.g. when Game Center
    /// asks us to start a match with specific players).
    func presentMatchmaker(recipients: [GKPlayer]? = nil) {
        guard isAuthenticated else { return }
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        request.recipients = recipients
        request.inviteMessage = Self.inviteMessage
        let controller = GKTurnBasedMatchmakerViewController(matchRequest: request)
        controller.turnBasedMatchmakerDelegate = self
        Self.topViewController()?.present(controller, animated: true)
    }

    // MARK: Invitations (docs/INVITE_FLOW.md)

    /// Sweeps Game Center for the local player's turn-based matches and
    /// splits them into `pendingInvites` (participant status `.invited` —
    /// finds invites that arrived while the app wasn't installed, since Game
    /// Center stores them server-side; no deep link required) and
    /// `activeMatches` (participant `.active` — the games in progress shown
    /// in the "Your Games" list). Ended matches are excluded from both.
    func refreshMatches() {
        guard isAuthenticated else { return }
        GKTurnBasedMatch.loadMatches { [weak self] matches, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    print("CombatChess online: loadMatches failed — \(error.localizedDescription)")
                    return
                }
                let localID = GKLocalPlayer.local.gamePlayerID
                let live = (matches ?? []).filter {
                    $0.status == .open || $0.status == .matching
                }
                self.pendingInvites = live.filter { match in
                    match.participants.contains {
                        $0.player?.gamePlayerID == localID && $0.status == .invited
                    }
                }
                self.activeMatches = live.filter { match in
                    match.participants.contains {
                        $0.player?.gamePlayerID == localID && $0.status == .active
                    }
                }
            }
        }
    }

    /// Opens an existing in-progress match chosen from the "Your Games"
    /// list. The coordinator reloads the authoritative match data itself, so
    /// a possibly-stale `GKTurnBasedMatch` from the sweep is fine here.
    func openMatch(_ match: GKTurnBasedMatch) {
        if let coordinator = activeCoordinator,
           coordinator.match.matchID == match.matchID {
            coordinator.refresh(from: match)
            return
        }
        activeCoordinator = OnlineMatchCoordinator(match: match)
    }

    /// Accepts a pending invitation and opens the match UI.
    func acceptInvite(_ match: GKTurnBasedMatch) {
        match.acceptInvite { [weak self] accepted, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.pendingInvites.removeAll { $0.matchID == match.matchID }
                if let error = error {
                    print("CombatChess online: acceptInvite failed — \(error.localizedDescription)")
                    return
                }
                guard let accepted = accepted else { return }
                self.activeCoordinator = OnlineMatchCoordinator(match: accepted)
            }
        }
    }

    /// Declines a pending invitation.
    func declineInvite(_ match: GKTurnBasedMatch) {
        match.declineInvite { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.pendingInvites.removeAll { $0.matchID == match.matchID }
                if let error = error {
                    print("CombatChess online: declineInvite failed — \(error.localizedDescription)")
                }
            }
        }
    }

    /// Encodes the full match state + the triggering message as turn data.
    func encodeTurnData(state: MatchState, message: NetMessage) throws -> Data {
        let envelope = TurnEnvelope(schema: TurnEnvelope.currentSchema,
                                    state: state, message: message)
        return try JSONEncoder().encode(envelope)
    }

    func decodeTurnData(_ data: Data) throws -> TurnEnvelope {
        return try JSONDecoder().decode(TurnEnvelope.self, from: data)
    }

    /// The wire format for one turn.
    ///
    /// `schema` lets an app detect turn data written by a NEWER version it
    /// can't safely interpret, so it can tell the player to update instead of
    /// silently mangling a live game. `MatchState` itself decodes leniently
    /// (see its `init(from:)`), so simply ADDING fields keeps old and new
    /// builds interoperable and does not require a schema bump — bump it only
    /// on a breaking change (a field's meaning or type changes).
    struct TurnEnvelope: Codable {
        static let currentSchema = 1

        var schema: Int
        let state: MatchState
        let message: NetMessage

        /// Data from a future, incompatible build.
        var isFromNewerApp: Bool { return schema > Self.currentSchema }

        private enum CodingKeys: String, CodingKey {
            case schema, state, message
        }

        init(schema: Int, state: MatchState, message: NetMessage) {
            self.schema = schema
            self.state = state
            self.message = message
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // Turn data from the pre-versioning build has no `schema` key.
            schema = try c.decodeIfPresent(Int.self, forKey: .schema) ?? 1
            state = try c.decode(MatchState.self, forKey: .state)
            message = try c.decode(NetMessage.self, forKey: .message)
        }
    }

    /// Result of trying to read incoming turn data. Decoding failures used to
    /// be swallowed — which either hung the match or (worse) replaced a live
    /// game with a fresh board and shipped it. Now the failure is explicit and
    /// callers must handle it without touching game state.
    enum TurnDataResult {
        case ok(TurnEnvelope)
        /// Written by a newer app version than this one.
        case needsAppUpdate
        /// Missing, empty, corrupt, or structurally invalid (e.g. not 64 squares).
        case unreadable
    }

    /// Safely interpret turn data. Never fabricates state.
    func readTurnData(_ data: Data?) -> TurnDataResult {
        guard let data = data, !data.isEmpty else { return .unreadable }
        guard let envelope = try? decodeTurnData(data) else { return .unreadable }
        if envelope.isFromNewerApp { return .needsAppUpdate }
        guard envelope.state.isStructurallyValid else { return .unreadable }
        return .ok(envelope)
    }

    // MARK: Real-time fight sessions (M2/M3)

    /// Live connection for one fight. Created when a challenge is accepted
    /// with both players online; falls back to the CPU-proxy fight if the
    /// session doesn't connect in time (docs §1).
    final class FightSession: NSObject, GKMatchDelegate {
        private let match: GKMatch
        var onMessage: ((NetMessage) -> Void)?
        var onDisconnect: (() -> Void)?

        init(match: GKMatch) {
            self.match = match
            super.init()
            match.delegate = self
        }

        func send(_ message: NetMessage, reliable: Bool) {
            guard let data = try? JSONEncoder().encode(message) else { return }
            try? match.sendData(toAllPlayers: data, with: reliable ? .reliable : .unreliable)
        }

        func close() {
            match.disconnect()
        }

        // GKMatchDelegate
        func match(_ match: GKMatch, didReceive data: Data, fromRemotePlayer player: GKPlayer) {
            if let message = try? JSONDecoder().decode(NetMessage.self, from: data) {
                onMessage?(message)
            }
        }

        func match(_ match: GKMatch, player: GKPlayer, didChange state: GKPlayerConnectionState) {
            if state == .disconnected {
                onDisconnect?()
            }
        }
    }

    // MARK: Helpers

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

// MARK: - Matchmaker delegate

extension GameKitManager: GKTurnBasedMatchmakerViewControllerDelegate {
    func turnBasedMatchmakerViewControllerWasCancelled(_ viewController: GKTurnBasedMatchmakerViewController) {
        viewController.dismiss(animated: true)
    }

    func turnBasedMatchmakerViewController(_ viewController: GKTurnBasedMatchmakerViewController,
                                           didFailWithError error: Error) {
        viewController.dismiss(animated: true)
    }
}

// MARK: - Turn events (M1)

extension GameKitManager: GKLocalPlayerListener {
    /// Fired when the user selects a match in the matchmaker, when a turn
    /// arrives via push, and when a match becomes active.
    func player(_ player: GKPlayer, receivedTurnEventFor match: GKTurnBasedMatch,
                didBecomeActive: Bool) {
        DispatchQueue.main.async {
            // Backgrounded-but-running: mirror the event as a local banner
            // (Game Center's own push usually covers this; the fallback is
            // deduped per match — docs/NOTIFICATIONS.md). Anywhere else the
            // player is about to see the match, so clear stale banners.
            if UIApplication.shared.applicationState == .background {
                NotificationManager.shared.postTurnEventFallback(for: match)
            } else {
                NotificationManager.shared.clearDelivered(forMatchID: match.matchID)
            }
            // Dismiss the matchmaker sheet if it's up.
            if let top = Self.topViewController() as? GKTurnBasedMatchmakerViewController {
                top.dismiss(animated: true)
            }
            // Any turn event for a match supersedes its "pending invite"
            // entry (the player accepted it via system UI, or it advanced).
            self.pendingInvites.removeAll { $0.matchID == match.matchID }
            // Keep the "Your Games" list current without another network
            // sweep: a turn event always carries a joined, live match.
            if let idx = self.activeMatches.firstIndex(where: { $0.matchID == match.matchID }) {
                self.activeMatches[idx] = match
            } else if match.status == .open || match.status == .matching {
                self.activeMatches.append(match)
            }
            if let coordinator = self.activeCoordinator,
               coordinator.match.matchID == match.matchID {
                coordinator.refresh(from: match)
            } else if didBecomeActive {
                self.activeCoordinator = OnlineMatchCoordinator(match: match)
            }
        }
    }

    func player(_ player: GKPlayer, matchEnded match: GKTurnBasedMatch) {
        DispatchQueue.main.async {
            self.activeMatches.removeAll { $0.matchID == match.matchID }
            if let coordinator = self.activeCoordinator,
               coordinator.match.matchID == match.matchID {
                coordinator.refresh(from: match)
            }
        }
    }

    /// The player used Game Center UI (Games app / dashboard) to start a
    /// Combat Chess match with specific players — open the matchmaker with
    /// those recipients pre-filled (GKTurnBasedEventListener).
    func player(_ player: GKPlayer, didRequestMatchWithOtherPlayers playersToInvite: [GKPlayer]) {
        DispatchQueue.main.async {
            self.presentMatchmaker(recipients: playersToInvite)
        }
    }

    /// GKInviteEventListener. Only real-time (`GKMatch`) invites arrive
    /// here; Combat Chess matches are turn-based, so their invite
    /// acceptances come through `player(_:receivedTurnEventFor:didBecomeActive:)`
    /// instead. Logged for diagnostics; becomes actionable if M2+ ever
    /// sends real-time fight invites.
    func player(_ player: GKPlayer, didAccept invite: GKInvite) {
        print("CombatChess online: unexpected real-time invite from \(invite.sender.displayName) — ignored (turn-based game)")
    }
}
