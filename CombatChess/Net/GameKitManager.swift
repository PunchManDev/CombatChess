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

    private var listenerRegistered = false

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
            }
        }
    }

    // MARK: Turn-based chess matches (M1)

    /// Presents the system matchmaker (friend invites + auto-match).
    func presentMatchmaker() {
        guard isAuthenticated else { return }
        let request = GKMatchRequest()
        request.minPlayers = 2
        request.maxPlayers = 2
        request.inviteMessage = "Combat Chess — your pieces won't capture themselves."
        let controller = GKTurnBasedMatchmakerViewController(matchRequest: request)
        controller.turnBasedMatchmakerDelegate = self
        Self.topViewController()?.present(controller, animated: true)
    }

    /// Encodes the full match state + the triggering message as turn data.
    func encodeTurnData(state: MatchState, message: NetMessage) throws -> Data {
        let envelope = TurnEnvelope(state: state, message: message)
        return try JSONEncoder().encode(envelope)
    }

    func decodeTurnData(_ data: Data) throws -> TurnEnvelope {
        return try JSONDecoder().decode(TurnEnvelope.self, from: data)
    }

    struct TurnEnvelope: Codable {
        let state: MatchState
        let message: NetMessage
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
            // Dismiss the matchmaker sheet if it's up.
            if let top = Self.topViewController() as? GKTurnBasedMatchmakerViewController {
                top.dismiss(animated: true)
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
            if let coordinator = self.activeCoordinator,
               coordinator.match.matchID == match.matchID {
                coordinator.refresh(from: match)
            }
        }
    }
}
