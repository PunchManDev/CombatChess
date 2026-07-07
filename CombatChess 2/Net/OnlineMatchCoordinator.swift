import Foundation
import GameKit

/// Bridges one `GKTurnBasedMatch` to a `MatchController` (M1,
/// docs/ONLINE_MULTIPLAYER.md): decodes incoming turn data, ships completed
/// local turns, and settles match outcomes. Fights run locally against a
/// CPU proxy of the opponent's piece until M3 lockstep lands.
final class OnlineMatchCoordinator: Identifiable {
    private(set) var match: GKTurnBasedMatch
    let controller: MatchController

    var id: String { return match.matchID }

    private var localPlayerID: String {
        return GKLocalPlayer.local.gamePlayerID
    }

    init(match: GKTurnBasedMatch) {
        self.match = match

        // Participant order fixes colors: the match creator is White.
        let localIndex = match.participants.firstIndex {
            $0.player?.gamePlayerID == GKLocalPlayer.local.gamePlayerID
        } ?? 0
        let localColor: PieceColor = localIndex == 0 ? .white : .black
        let opponentName = match.participants.first {
            $0.player?.gamePlayerID != GKLocalPlayer.local.gamePlayerID
        }?.player?.displayName ?? "OPPONENT"

        var state: MatchState
        if let data = match.matchData, !data.isEmpty,
           let envelope = try? GameKitManager.shared.decodeTurnData(data) {
            state = envelope.state
        } else {
            // Fresh online match: fixed 3-card loadout for both armies.
            var fresh = MatchState(difficulty: .medium)
            fresh.aiCards = 3
            fresh.aiCardsStart = 3
            state = fresh
        }

        let controller = MatchController(onlineState: state,
                                         localColor: localColor,
                                         opponentName: opponentName.uppercased())
        self.controller = controller
        controller.onTurnEnded = { [weak self] updatedState in
            self?.sendTurn(updatedState)
        }
        controller.onMatchEnded = { [weak self] result in
            self?.endMatch(localResult: result)
        }

        // If it's already our turn, ingest the opponent's last actions
        // (may surface an async capture-challenge prompt).
        if isLocalTurn(in: match) {
            controller.applyIncomingTurn(state)
        }
    }

    // MARK: - Incoming events

    /// Called by `GameKitManager` on every turn event for this match.
    func refresh(from updated: GKTurnBasedMatch) {
        match = updated

        if updated.status == .ended {
            let local = updated.participants.first {
                $0.player?.gamePlayerID == localPlayerID
            }
            let result: String
            switch local?.matchOutcome {
            case .won: result = "win"
            case .tied: result = "draw"
            default: result = "loss"
            }
            var finalState: MatchState?
            if let data = updated.matchData,
               let envelope = try? GameKitManager.shared.decodeTurnData(data) {
                finalState = envelope.state
            }
            controller.applyRemoteMatchEnd(finalState, localOutcome: result,
                                           detail: "Match ended")
            return
        }

        guard isLocalTurn(in: updated) else { return }
        if let data = updated.matchData,
           let envelope = try? GameKitManager.shared.decodeTurnData(data) {
            controller.applyIncomingTurn(envelope.state)
        }
    }

    // MARK: - Outgoing

    private func sendTurn(_ state: MatchState) {
        let next = match.participants.filter {
            $0.player?.gamePlayerID != localPlayerID
        }
        guard let data = try? GameKitManager.shared.encodeTurnData(
            state: state, message: .chessMove(uci: "")) else { return }
        match.endTurn(withNextParticipants: next,
                      turnTimeout: GKTurnTimeoutDefault,
                      match: data) { _ in }
    }

    private func endMatch(localResult: String) {
        for participant in match.participants {
            let isLocal = participant.player?.gamePlayerID == localPlayerID
            if localResult == "draw" {
                participant.matchOutcome = .tied
            } else {
                let localWon = localResult == "win"
                participant.matchOutcome = (localWon == isLocal) ? .won : .lost
            }
        }
        let data = (try? GameKitManager.shared.encodeTurnData(
            state: controller.state, message: .resignation)) ?? Data()
        if isLocalTurn(in: match) {
            match.endMatchInTurn(withMatch: data) { _ in }
        } else {
            match.participantQuitOutOfTurn(
                with: localResult == "win" ? .won : .lost) { _ in }
        }
    }

    private func isLocalTurn(in match: GKTurnBasedMatch) -> Bool {
        return match.currentParticipant?.player?.gamePlayerID == localPlayerID
    }
}
