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

    /// Highest fight version already conveyed to (or received from) the
    /// opponent, so the outgoing turn notification mentions a fight outcome
    /// exactly once — and never a fight the opponent's own device played
    /// (docs/NOTIFICATIONS.md).
    private var lastNotifiedFightVersion = 0

    /// A player who doesn't move within this window forfeits; the opponent
    /// wins by default (docs/NOTIFICATIONS.md). Enforced by Game Center via
    /// the `endTurn` turnTimeout, then resolved to a match end on the winner's
    /// device when the turn returns to them.
    static let forfeitTimeout: TimeInterval = 4 * 24 * 60 * 60

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

        // Best-effort initial state; the authoritative data is reloaded
        // asynchronously right after (init's matchData can be stale/nil).
        //
        // A fresh board is used ONLY when the match genuinely has no data yet
        // (a brand-new match). If data exists but can't be read, we must NOT
        // fabricate a board — shipping that would wipe a live game for both
        // players. `process(...)` handles the unreadable/needs-update cases and
        // refuses to touch game state.
        var state: MatchState
        if case .ok(let envelope) = GameKitManager.shared.readTurnData(match.matchData) {
            state = envelope.state
        } else {
            var fresh = MatchState(difficulty: .medium)   // fixed 3-card loadout
            fresh.aiCards = 3
            fresh.aiCardsStart = 3
            state = fresh
        }

        let controller = MatchController(onlineState: state,
                                         localColor: localColor,
                                         opponentName: opponentName.uppercased())
        self.controller = controller
        self.lastNotifiedFightVersion = state.fightSummaryVersion
        controller.onTurnEnded = { [weak self] updatedState, notice in
            self?.sendTurn(updatedState, notice: notice)
        }
        controller.onMatchEnded = { [weak self] result in
            self?.endMatch(localResult: result)
        }

        // First online match is the moment notifications become valuable —
        // ask now (no-op once the player has decided; docs/NOTIFICATIONS.md).
        NotificationManager.shared.requestAuthorizationIfNeeded()

        // Always pull the authoritative data before acting on the turn.
        reloadAndApply(match)
    }

    // MARK: - Incoming events

    /// Called by `GameKitManager` on every turn event for this match.
    func refresh(from updated: GKTurnBasedMatch) {
        match = updated
        reloadAndApply(updated)
    }

    /// Explicitly load the match's current data (the object delivered in a
    /// turn event frequently has stale/nil `matchData` for the recipient —
    /// reading it directly is what hung the match after the first exchange).
    private func reloadAndApply(_ target: GKTurnBasedMatch) {
        target.loadMatchData { [weak self] data, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let error = error {
                    print("CombatChess online: loadMatchData failed — \(error.localizedDescription)")
                }
                self.process(match: target, data: data)
            }
        }
    }

    private func process(match updated: GKTurnBasedMatch, data: Data?) {
        match = updated

        if updated.status == .ended {
            NotificationManager.shared.cancelTurnReminders(matchID: updated.matchID)
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
            if case .ok(let envelope) = GameKitManager.shared.readTurnData(data) {
                finalState = envelope.state
            }
            // The outcome is authoritative even if the payload is unreadable.
            controller.applyRemoteMatchEnd(finalState, localOutcome: result,
                                           detail: "Match ended")
            return
        }

        // Only ingest the opponent's actions when it's now our turn.
        guard isLocalTurn(in: updated) else {
            // Not our turn: the opponent is on the clock. Their reminders live
            // on their own device; make sure ours are cleared.
            NotificationManager.shared.cancelTurnReminders(matchID: updated.matchID)
            return
        }

        // The turn returned to us because the opponent abandoned the match:
        // a participant marked `.done` while the match is still open has quit
        // or timed out. We're the current participant, so we can end it —
        // opponent forfeits, we win by default.
        if let foe = updated.participants.first(where: {
            $0.player?.gamePlayerID != localPlayerID
        }), foe.status == .done {
            NotificationManager.shared.cancelTurnReminders(matchID: updated.matchID)
            resolveForfeitWin()
            return
        }

        // Read the opponent's turn. A failure here must never mutate or
        // fabricate game state — it surfaces to the player instead.
        let envelope: GameKitManager.TurnEnvelope
        switch GameKitManager.shared.readTurnData(data) {
        case .ok(let e):
            envelope = e
        case .needsAppUpdate:
            print("CombatChess online: turn data from a newer app version — update required")
            controller.onlineError = .needsAppUpdate
            return
        case .unreadable:
            print("CombatChess online: turn data unreadable — refusing to alter the match")
            controller.onlineError = .unreadableTurn
            return
        }
        controller.onlineError = nil
        // Any fight version arriving FROM the opponent is one their device
        // played or already knows — never re-announce it back at them.
        lastNotifiedFightVersion = max(lastNotifiedFightVersion,
                                       envelope.state.fightSummaryVersion)
        controller.applyIncomingTurn(envelope.state)

        // It's our move now: (re)arm the daily inactivity reminders anchored
        // to the real forfeit deadline, unless the match already ended (e.g.
        // an incoming checkmate/king-capture resolved it).
        if controller.gameResult == nil {
            let deadline = updated.currentParticipant?.timeoutDate
                ?? Date().addingTimeInterval(Self.forfeitTimeout)
            NotificationManager.shared.scheduleTurnReminders(
                matchID: updated.matchID,
                opponentName: controller.remoteOpponentName,
                deadline: deadline)
        } else {
            NotificationManager.shared.cancelTurnReminders(matchID: updated.matchID)
        }
    }

    /// Opponent abandoned/timed out: end the match with the local player as
    /// the winner (we are the current participant here).
    private func resolveForfeitWin() {
        for participant in match.participants {
            let isLocal = participant.player?.gamePlayerID == localPlayerID
            participant.matchOutcome = isLocal ? .won : .quit
        }
        let data = (try? GameKitManager.shared.encodeTurnData(
            state: controller.state, message: .resignation)) ?? Data()
        match.message = "\(GKLocalPlayer.local.alias) wins — opponent forfeited."
        match.endMatchInTurn(withMatch: data) { [weak self] error in
            if let error = error {
                print("CombatChess online: forfeit endMatch failed — \(error.localizedDescription)")
            }
            DispatchQueue.main.async {
                self?.controller.applyRemoteMatchEnd(nil, localOutcome: "win",
                                                     detail: "Opponent forfeited")
            }
        }
    }

    // MARK: - Outgoing

    private func sendTurn(_ state: MatchState, notice: TurnNotice) {
        let next = match.participants.filter {
            $0.player?.gamePlayerID != localPlayerID
        }
        guard let data = try? GameKitManager.shared.encodeTurnData(
            state: state, message: .chessMove(uci: "")) else {
            print("CombatChess online: failed to encode turn data")
            return
        }
        // We moved: clear our own inactivity reminders — the clock is now on
        // the opponent (their reminders live on their device).
        NotificationManager.shared.cancelTurnReminders(matchID: match.matchID)
        // Game Center pushes a turn notification to the opponent for free;
        // `message` (set before endTurn) is the text on that banner when
        // their app isn't frontmost (docs/NOTIFICATIONS.md). The 4-day
        // turnTimeout makes Game Center enforce the forfeit window.
        match.message = turnMessage(for: state, notice: notice)
        match.endTurn(withNextParticipants: next,
                      turnTimeout: Self.forfeitTimeout,
                      match: data) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let error = error else {
                    self.controller.onlineError = nil
                    return
                }
                // The turn never reached Game Center. The controller has
                // already flipped to `.waitingForOpponent`, so without this the
                // match hangs forever on a move the opponent never receives.
                // Surface it and let the player retry the send.
                print("CombatChess online: endTurn failed — \(error.localizedDescription)")
                self.controller.onlineError = .sendFailed
                self.failedTurn = (state, notice)
            }
        }
    }

    /// A turn whose `endTurn` failed, kept so the player can retry it.
    private var failedTurn: (state: MatchState, notice: TurnNotice)?

    /// Retry a turn whose send failed (driven by the match screen's alert).
    func retryFailedTurn() {
        guard let pending = failedTurn else { return }
        failedTurn = nil
        controller.onlineError = nil
        sendTurn(pending.state, notice: pending.notice)
    }

    private func endMatch(localResult: String) {
        NotificationManager.shared.cancelTurnReminders(matchID: match.matchID)
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
        // Match-end events also push to the opponent; give the banner a
        // result line (receiver's perspective — docs/NOTIFICATIONS.md).
        match.message = matchEndMessage(localResult: localResult)
        if isLocalTurn(in: match) {
            match.endMatchInTurn(withMatch: data) { error in
                if let error = error {
                    print("CombatChess online: endMatchInTurn failed — \(error.localizedDescription)")
                }
            }
        } else {
            match.participantQuitOutOfTurn(
                with: localResult == "win" ? .won : .lost) { error in
                if let error = error {
                    print("CombatChess online: quitOutOfTurn failed — \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Notification text (docs/NOTIFICATIONS.md)

    /// One line describing the local player's turn, written for the opponent
    /// who reads it on a lock-screen banner. Uses the plain `message`
    /// property (not `setLocalizableMessageWithKey`) — the app ships
    /// English-only strings throughout.
    private func turnMessage(for state: MatchState, notice: TurnNotice) -> String {
        let name = GKLocalPlayer.local.alias
        // A fight the opponent hasn't witnessed is the headline: they've been
        // waiting on its outcome since they shipped the capture attempt.
        if state.fightSummaryVersion > lastNotifiedFightVersion,
           let summary = state.lastFightSummary {
            lastNotifiedFightVersion = state.fightSummaryVersion
            return fightMessage(summary, senderName: name)
        }
        let inCheck = state.board.isInCheck(controller.localColor.opposite)
        switch notice {
        case .challenged(let type):
            return "\(name) is attacking your \(type.displayName.lowercased()) — challenge the capture or let it stand!"
        case .captured(let type):
            return inCheck
                ? "\(name) captured your \(type.displayName.lowercased()) — check!"
                : "\(name) captured your \(type.displayName.lowercased())! Your move."
        case .moved:
            return inCheck
                ? "\(name) moved — check!"
                : "\(name) moved. Your turn."
        }
    }

    /// Fight outcomes are color-absolute in `FightSummary`; rephrase for the
    /// receiving opponent. Online fights resolve on the defender's device
    /// (CPU-proxy model, docs/ONLINE_MULTIPLAYER.md §1), so from here the
    /// defender is normally the local side — but both orientations are
    /// handled in case that model changes with M3.
    private func fightMessage(_ summary: FightSummary, senderName name: String) -> String {
        let attacker = (PieceType(rawValue: summary.attackerType) ?? .pawn)
            .displayName.lowercased()
        let defender = (PieceType(rawValue: summary.defenderType) ?? .pawn)
            .displayName.lowercased()
        let opponentColor = controller.localColor.opposite

        if summary.isCheckFight {
            // A survived last stand (a lost one ends the match instead).
            return summary.defenderColor == opponentColor
                ? "Your king survived his last stand and slew \(name)'s \(attacker)!"
                : "\(name)'s king survived his last stand — your \(attacker) is slain!"
        }
        if summary.attackerColor == opponentColor {
            // The receiver attacked; the local defender chose to fight.
            return summary.attackerWon
                ? "Your \(attacker) won the fight and took \(name)'s \(defender)!"
                : "\(name)'s \(defender) fought off your \(attacker)!"
        }
        // The receiver defended against the local player's attack.
        return summary.attackerWon
            ? "\(name)'s \(attacker) beat your \(defender) in the fight!"
            : "Your \(defender) repelled \(name)'s \(attacker)!"
    }

    /// Result line for the opponent's match-ended banner.
    private func matchEndMessage(localResult: String) -> String {
        let name = GKLocalPlayer.local.alias
        switch localResult {
        case "win": return "\(name) won the match!"
        case "draw": return "Your match with \(name) ended in a draw."
        default: return "You won the match against \(name)!"
        }
    }

    private func isLocalTurn(in match: GKTurnBasedMatch) -> Bool {
        return match.currentParticipant?.player?.gamePlayerID == localPlayerID
    }
}
