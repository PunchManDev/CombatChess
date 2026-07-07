import Foundation
import Observation

/// Orchestrates the match flow (PRD §5.2):
/// playerTurn ↔ aiTurn, capture → challengeWindow → fight → resolve → checkEvaluation.
@Observable
final class MatchController {

    enum Phase: Equatable {
        case playerTurn
        case aiThinking
        /// Online: the remote player's turn is in progress elsewhere.
        case waitingForOpponent
        /// AI captured a player piece; the player has 10 s to challenge.
        case awaitingChallengeDecision
        /// A fight is about to start (card challenge or mandatory king fight).
        case aiChallengeBanner
        case fighting
        case gameOver
    }

    var state: MatchState
    var phase: Phase = .playerTurn
    var selectedSquare: Int?
    var legalTargets: [Move] = []
    var pending: PendingCapture?
    var pendingCheck: CheckFight?
    var fightSetup: FightSetup?
    var lastMove: Move?
    /// "win" / "loss" / "draw" from the player's perspective.
    var gameResult: String?
    var gameResultDetail: String = ""
    var challengeDeadline: Date?
    var playerInCheck: Bool = false
    /// Text shown on the pre-fight banner overlay.
    var bannerText: String = "OPPONENT CHALLENGES!"

    // MARK: - Opponent kind (docs/ONLINE_MULTIPLAYER.md M1)

    enum OpponentKind {
        case cpu
        case remote
    }

    var opponentKind: OpponentKind = .cpu
    /// The side this device controls (.white offline; assigned online).
    var localColor: PieceColor = .white
    var remoteOpponentName: String = "OPPONENT"
    /// Online: called when the local player's actions are done and the state
    /// should ship to the opponent as turn data.
    var onTurnEnded: ((MatchState) -> Void)?
    /// Online: called when the match ends locally ("win"/"loss"/"draw").
    var onMatchEnded: ((String) -> Void)?

    var playerColor: PieceColor { return localColor }

    // Color-keyed card/tray accessors: MatchState stores white in
    // `playerCards`/`capturedByPlayer` and black in the `ai` fields, so the
    // same state is interpreted identically on both devices.
    var localCards: Int {
        return localColor == .white ? state.playerCards : state.aiCards
    }
    var localCardsStart: Int {
        return localColor == .white ? state.playerCardsStart : state.aiCardsStart
    }
    var opponentCards: Int {
        return localColor == .white ? state.aiCards : state.playerCards
    }
    var opponentCardsStart: Int {
        return localColor == .white ? state.aiCardsStart : state.playerCardsStart
    }
    var capturedByLocal: [String] {
        return localColor == .white ? state.capturedByPlayer : state.capturedByAI
    }
    var capturedByOpponent: [String] {
        return localColor == .white ? state.capturedByAI : state.capturedByPlayer
    }

    private func spendLocalCard() {
        if localColor == .white {
            state.playerCards -= 1
        } else {
            state.aiCards -= 1
        }
    }

    private let challengeWindowSeconds: TimeInterval = 10

    // MARK: - Init

    init(difficulty: Difficulty) {
        self.state = MatchState(difficulty: difficulty)
        persistIfOffline()
        // Warm up Stockfish (NNUE load) so the first AI move is instant.
        Task.detached(priority: .utility) {
            await EngineManager.shared.warmUp()
        }
    }

    init(resuming state: MatchState) {
        self.state = state
        if state.board.turn != playerColor {
            phase = .aiThinking
        }
        refreshCheckFlag()
    }

    /// Online match (docs/ONLINE_MULTIPLAYER.md M1): state arrives from
    /// Game Center turn data; incoming turns route via `applyIncomingTurn`.
    init(onlineState state: MatchState, localColor: PieceColor, opponentName: String) {
        self.state = state
        self.localColor = localColor
        self.opponentKind = .remote
        self.remoteOpponentName = opponentName
        self.phase = state.board.turn == localColor ? .playerTurn : .waitingForOpponent
        refreshCheckFlag()
    }

    /// Call once the UI is on screen. Re-evaluates the position so resumed
    /// matches land in the right phase (including a checkmate last-stand).
    func start() {
        guard gameResult == nil else { return }
        if opponentKind == .remote {
            // Online phases are driven by the coordinator; just settle idle state.
            if phase == .playerTurn || phase == .waitingForOpponent {
                phase = state.board.turn == localColor ? .playerTurn : .waitingForOpponent
            }
            return
        }
        guard phase == .playerTurn || phase == .aiThinking else { return }
        continueAfterBoardChange()
    }

    /// Persist the in-flight snapshot for offline matches only; online
    /// matches live in Game Center.
    private func persistIfOffline() {
        if opponentKind == .cpu {
            persistIfOffline()
        }
    }

    // MARK: - Player input

    func tapSquare(_ sq: Int) {
        guard phase == .playerTurn else { return }
        if selectedSquare != nil, let move = legalTargets.first(where: { $0.to == sq }) {
            deselect()
            performPlayerMove(move)
            return
        }
        if let piece = state.board.squares[sq], piece.color == playerColor {
            selectedSquare = sq
            legalTargets = state.board.legalMoves(for: playerColor).filter { $0.from == sq }
        } else {
            deselect()
        }
    }

    private func deselect() {
        selectedSquare = nil
        legalTargets = []
    }

    func resign() {
        guard gameResult == nil else { return }
        finishGame(result: "loss", detail: "Resigned")
    }

    // MARK: - Check challenges (king last-stand rule)

    /// True when the player can spend a card to have their king fight the
    /// (single) checking piece.
    var canChallengeCheck: Bool {
        guard gameResult == nil, localCards > 0 else { return false }
        guard state.board.turn == playerColor, state.board.isInCheck(playerColor) else { return false }
        return state.board.checkers(of: playerColor).count == 1
    }

    /// Type of the piece currently checking the player (for UI labels).
    var currentCheckerType: PieceType? {
        guard let sq = state.board.checkers(of: playerColor).first else { return nil }
        return state.board.squares[sq]?.type
    }

    /// Player spends a card: their king fights the checker (instead of moving).
    func playerChallengesCheck() {
        guard phase == .playerTurn else { return }
        guard localCards > 0,
              state.board.checkers(of: playerColor).count == 1,
              let checkerSq = state.board.checkers(of: playerColor).first,
              let checker = state.board.squares[checkerSq],
              let kingSq = state.board.kingSquare(of: playerColor),
              let king = state.board.squares[kingSq] else { return }
        spendLocalCard()
        deselect()
        pendingCheck = CheckFight(checker: checker, checkerSquare: checkerSq,
                                  king: king, kingSquare: kingSq, challengedBy: "player")
        fightSetup = FightSetup(playerPiece: king, aiPiece: checker,
                                playerIsAttacker: false,
                                difficulty: state.difficulty, isCheckFight: true)
        phase = .fighting
    }

    /// AI spends a card: its king fights the player's checking piece.
    private func aiChallengesCheck(checkerSq: Int, checker: Piece,
                                   kingSq: Int, king: Piece) {
        state.aiCards -= 1
        pendingCheck = CheckFight(checker: checker, checkerSquare: checkerSq,
                                  king: king, kingSquare: kingSq, challengedBy: "ai")
        bannerText = "THE ENEMY KING FIGHTS BACK!"
        beginPendingCheckFightAfterBanner()
    }

    /// Shared banner → fight transition for every king fight.
    private func beginPendingCheckFightAfterBanner() {
        phase = .aiChallengeBanner
        Haptics.warning()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self, let cf = self.pendingCheck else { return }
            let kingIsPlayers = cf.king.color == self.playerColor
            self.fightSetup = FightSetup(playerPiece: kingIsPlayers ? cf.king : cf.checker,
                                         aiPiece: kingIsPlayers ? cf.checker : cf.king,
                                         playerIsAttacker: !kingIsPlayers,
                                         difficulty: self.state.difficulty,
                                         isCheckFight: true)
            self.phase = .fighting
        }
    }

    /// Mandatory rule: a king is never simply taken. Checkmate (or a direct
    /// board capture) always resolves through one final fight — the king's
    /// last opportunity to turn the attack around. No card required.
    private func startFinalStand(defender: PieceColor) {
        let checkers = state.board.checkers(of: defender)
        guard let kingSq = state.board.kingSquare(of: defender),
              let king = state.board.squares[kingSq],
              !checkers.isEmpty else {
            finishGame(result: defender == playerColor ? "loss" : "win", detail: "Checkmate")
            return
        }
        // Duel the mating piece: prefer the piece that just moved, else the strongest checker.
        let checkerSq = checkers.first(where: { $0 == lastMove?.to })
            ?? checkers.max(by: {
                (state.board.squares[$0]?.type.fightPoints ?? 0) <
                (state.board.squares[$1]?.type.fightPoints ?? 0)
            })!
        guard let checker = state.board.squares[checkerSq] else {
            finishGame(result: defender == playerColor ? "loss" : "win", detail: "Checkmate")
            return
        }
        pendingCheck = CheckFight(checker: checker, checkerSquare: checkerSq,
                                  king: king, kingSquare: kingSq, challengedBy: "rule")
        bannerText = defender == playerColor
            ? "CHECKMATE! YOUR KING'S LAST STAND!"
            : "CHECKMATE! THE ENEMY KING'S FINAL STAND!"
        beginPendingCheckFightAfterBanner()
    }

    /// A move tried to capture a king outright (possible after fight-created
    /// discovered attacks): the capture resolves through a fight instead.
    private func startKingCaptureFight(move: Move, attacker: Piece, king: Piece) {
        let kingSq = state.board.capturedSquare(of: move) ?? move.to
        deselect()
        pendingCheck = CheckFight(checker: attacker, checkerSquare: move.from,
                                  king: king, kingSquare: kingSq, challengedBy: "rule")
        bannerText = king.color == playerColor
            ? "YOUR KING FIGHTS FOR HIS LIFE!"
            : "THE ENEMY KING DEFENDS TO THE DEATH!"
        beginPendingCheckFightAfterBanner()
    }

    /// Looks up the AI's (single) checker + king if a check challenge is possible.
    private func aiCheckFightCandidates() -> (checkerSq: Int, checker: Piece, kingSq: Int, king: Piece)? {
        let checkers = state.board.checkers(of: playerColor.opposite)
        guard checkers.count == 1,
              let checkerSq = checkers.first,
              let checker = state.board.squares[checkerSq],
              let kingSq = state.board.kingSquare(of: playerColor.opposite),
              let king = state.board.squares[kingSq] else { return nil }
        return (checkerSq, checker, kingSq, king)
    }

    // MARK: - Player move → possible AI challenge (PRD §2.3)

    private func performPlayerMove(_ move: Move) {
        let board = state.board
        guard let attacker = board.squares[move.from] else { return }
        let victim = board.capturedPiece(of: move)

        // Capturing a king always resolves through a final king fight
        // (fought locally vs. a CPU proxy in online play).
        if let victim = victim, victim.type == .king {
            startKingCaptureFight(move: move, attacker: attacker, king: victim)
            return
        }

        // Online: a challengeable capture defers to the defender's turn —
        // ship the pre-move state with the pending capture attached.
        if opponentKind == .remote {
            if let victim = victim,
               attacker.type != .king,
               victim.type != .king,
               opponentCards > 0 {
                state.pendingCaptureMove = move
                lastMove = move
                phase = .waitingForOpponent
                onTurnEnded?(state)
                return
            }
            commitMove(move, mover: localColor)
            continueAfterBoardChange()
            return
        }

        // Offline: the CPU decides instantly. Kings never fight over
        // ordinary captures (PRD §2.6).
        if let victim = victim,
           attacker.type != .king,
           state.aiCards > 0,
           ChessAI.shouldChallenge(defender: victim, attacker: attacker,
                                   cardsLeft: state.aiCards, difficulty: state.difficulty) {
            state.aiCards -= 1
            pending = PendingCapture(move: move, attacker: attacker, defender: victim,
                                     defenderSquare: board.capturedSquare(of: move)!,
                                     challenger: "ai")
            bannerText = "OPPONENT CHALLENGES!"
            phase = .aiChallengeBanner
            Haptics.warning()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.beginFight()
            }
            return
        }

        commitMove(move, mover: localColor)
        continueAfterBoardChange()
    }

    // MARK: - Incoming online turns

    /// Ingest the opponent's turn data (docs/ONLINE_MULTIPLAYER.md §3).
    func applyIncomingTurn(_ incoming: MatchState) {
        guard gameResult == nil else { return }
        state = incoming
        lastMove = nil
        refreshCheckFlag()

        // Opponent captured one of our pieces and we may challenge it.
        if let pendingMove = state.pendingCaptureMove {
            state.pendingCaptureMove = nil
            let board = state.board
            if let attacker = board.squares[pendingMove.from],
               let victim = board.capturedPiece(of: pendingMove),
               let victimSq = board.capturedSquare(of: pendingMove),
               victim.color == localColor,
               localCards > 0 {
                pending = PendingCapture(move: pendingMove, attacker: attacker,
                                         defender: victim, defenderSquare: victimSq,
                                         challenger: "player")
                phase = .awaitingChallengeDecision
                challengeDeadline = nil        // async: no countdown
                Haptics.warning()
                return
            }
            // No card / not challengeable: the capture resolves.
            commitMove(pendingMove, mover: localColor.opposite)
            continueAfterBoardChange()
            return
        }
        continueAfterBoardChange()
    }

    /// The remote match ended (opponent's device or Game Center authority).
    func applyRemoteMatchEnd(_ incoming: MatchState?, localOutcome: String, detail: String) {
        guard gameResult == nil else { return }
        if let incoming = incoming {
            state = incoming
        }
        refreshCheckFlag()
        finishGame(result: localOutcome, detail: detail)
    }

    // MARK: - AI turn

    private func runAITurn() {
        phase = .aiThinking
        let boardSnapshot = state.board
        let difficulty = state.difficulty
        Task.detached(priority: .userInitiated) { [weak self] in
            // Small floor so instant moves still feel deliberate.
            let started = Date()

            // Stockfish first; native minimax as a guaranteed fallback
            // (missing NNUE networks, engine failure, or unparsable move).
            var move: Move?
            if let uci = await EngineManager.shared.bestMove(fen: boardSnapshot.fen,
                                                             difficulty: difficulty) {
                move = boardSnapshot.move(fromUCI: uci)
            }
            if move == nil {
                move = ChessAI.bestMove(board: boardSnapshot, difficulty: difficulty)
            }

            let elapsed = Date().timeIntervalSince(started)
            if elapsed < 0.6 {
                try? await Task.sleep(nanoseconds: UInt64((0.6 - elapsed) * 1_000_000_000))
            }
            await MainActor.run {
                self?.aiMoveComputed(move)
            }
        }
    }

    private func aiMoveComputed(_ move: Move?) {
        guard gameResult == nil else { return }
        guard let move = move else {
            // Should be unreachable (status is checked before every turn).
            finishGame(result: "win", detail: "Opponent has no moves")
            return
        }
        let board = state.board
        let attacker = board.squares[move.from]
        let victim = board.capturedPiece(of: move)

        // Capturing a king always resolves through a final king fight.
        if let victim = victim, let attacker = attacker, victim.type == .king {
            startKingCaptureFight(move: move, attacker: attacker, king: victim)
            return
        }

        // Offer the challenge window when the AI captures a player piece (PRD §3.2).
        if let victim = victim,
           let attacker = attacker,
           attacker.type != .king,
           state.playerCards > 0 {
            pending = PendingCapture(move: move, attacker: attacker, defender: victim,
                                     defenderSquare: board.capturedSquare(of: move)!,
                                     challenger: "player")
            phase = .awaitingChallengeDecision
            challengeDeadline = Date().addingTimeInterval(challengeWindowSeconds)
            Haptics.warning()
            return
        }

        commitMove(move, mover: localColor.opposite)
        continueAfterBoardChange()
    }

    // MARK: - Challenge decisions (player side)

    func playerDeclinesChallenge() {
        guard phase == .awaitingChallengeDecision, let p = pending else { return }
        pending = nil
        challengeDeadline = nil
        commitMove(p.move, mover: localColor.opposite)
        continueAfterBoardChange()
    }

    func playerAcceptsChallenge() {
        guard phase == .awaitingChallengeDecision, localCards > 0 else { return }
        spendLocalCard()
        challengeDeadline = nil
        beginFight()
    }

    // MARK: - Fight lifecycle (PRD §2.4, §2.7)

    private func beginFight() {
        guard let p = pending else { return }
        let playerIsAttacker = p.attacker.color == playerColor
        fightSetup = FightSetup(playerPiece: playerIsAttacker ? p.attacker : p.defender,
                                aiPiece: playerIsAttacker ? p.defender : p.attacker,
                                playerIsAttacker: playerIsAttacker,
                                difficulty: state.difficulty)
        phase = .fighting
    }

    func fightEnded(_ result: FightResult) {
        guard let setup = fightSetup else { return }
        fightSetup = nil
        if let checkFight = pendingCheck {
            pendingCheck = nil
            resolveCheckFight(checkFight, result: result)
            return
        }
        guard let p = pending else { return }
        pending = nil

        var attacker = p.attacker
        var defender = p.defender
        let attackerIsPlayers = setup.playerIsAttacker
        attacker.currentHP = max(0, attackerIsPlayers ? result.playerHP : result.aiHP)
        defender.currentHP = max(0, attackerIsPlayers ? result.aiHP : result.playerHP)
        attacker.hasFought = true
        defender.hasFought = true

        let attackerWon = (result.playerWon == attackerIsPlayers)

        // Log for history (PRD §3.4, §6).
        let playersPiece = attackerIsPlayers ? attacker : defender
        let aisPiece = attackerIsPlayers ? defender : attacker
        let upset = result.playerWon ? aisPiece.type.points - playersPiece.type.points : 0
        state.fightLogs.append(FightLog(moveNumber: state.moveCount + 1,
                                        attackerType: attacker.type.rawValue,
                                        defenderType: defender.type.rawValue,
                                        initiatedBy: p.challenger,
                                        playerWon: result.playerWon,
                                        upsetDelta: max(0, upset),
                                        durationSec: result.durationSec))

        if attackerWon {
            // Capture stands: write updated attacker HP back, then apply the move
            // (handles promotion HP scaling, castling rights, clocks, turn flip).
            state.board.squares[p.move.from] = attacker
            state.board.apply(p.move)
            recordRemoval(of: defender)
        } else {
            // Capture repelled (PRD §2.7): attacker removed, defender keeps its square.
            state.board.squares[p.move.from] = nil
            state.board.clearRights(forCorner: p.move.from)
            state.board.squares[p.defenderSquare] = defender
            state.board.enPassantTarget = nil
            state.board.halfmoveClock = 0
            if state.board.turn == .black {
                state.board.fullmoveNumber += 1
            }
            state.board.turn = state.board.turn.opposite
            recordRemoval(of: attacker)
        }

        state.moveCount += 1
        trackRepetition()
        lastMove = p.move
        persistIfOffline()
        continueAfterBoardChange()
    }

    /// Resolve a king-vs-checker fight (PRD king rules superseded by the
    /// last-stand feature): king wins → checker removed, turn consumed.
    /// King loses → captured, game over.
    private func resolveCheckFight(_ cf: CheckFight, result: FightResult) {
        var king = cf.king
        var checker = cf.checker
        let kingIsPlayers = cf.king.color == playerColor
        king.currentHP = max(0, kingIsPlayers ? result.playerHP : result.aiHP)
        checker.currentHP = max(0, kingIsPlayers ? result.aiHP : result.playerHP)
        king.hasFought = true
        checker.hasFought = true
        let kingWon = (result.playerWon == kingIsPlayers)

        let playersPoints = kingIsPlayers ? king.type.fightPoints : checker.type.fightPoints
        let foesPoints = kingIsPlayers ? checker.type.fightPoints : king.type.fightPoints
        state.fightLogs.append(FightLog(moveNumber: state.moveCount + 1,
                                        attackerType: checker.type.rawValue,
                                        defenderType: king.type.rawValue,
                                        initiatedBy: cf.challengedBy,
                                        playerWon: result.playerWon,
                                        upsetDelta: result.playerWon ? max(0, foesPoints - playersPoints) : 0,
                                        durationSec: result.durationSec))

        if kingWon {
            // Checker slain: remove it, king keeps his square, turn is consumed.
            state.board.squares[cf.checkerSquare] = nil
            state.board.clearRights(forCorner: cf.checkerSquare)
            state.board.squares[cf.kingSquare] = king
            recordRemoval(of: checker)
            state.board.enPassantTarget = nil
            state.board.halfmoveClock = 0
            if state.board.turn == .black {
                state.board.fullmoveNumber += 1
            }
            state.board.turn = state.board.turn.opposite
            state.moveCount += 1
            trackRepetition()
            persistIfOffline()
            continueAfterBoardChange()
        } else {
            // King captured — the game ends on the spot.
            state.board.squares[cf.kingSquare] = nil
            finishGame(result: kingIsPlayers ? "loss" : "win", detail: "King captured")
        }
    }

    private func recordRemoval(of piece: Piece) {
        recordCaptureTray(piece, capturer: piece.color.opposite)
    }

    // MARK: - Commit + status evaluation

    private func commitMove(_ move: Move, mover: PieceColor) {
        if let victim = state.board.capturedPiece(of: move) {
            recordCaptureTray(victim, capturer: mover)
        }
        state.board.apply(move)
        state.moveCount += 1
        lastMove = move
        trackRepetition()
        persistIfOffline()
    }

    private func recordCaptureTray(_ victim: Piece, capturer: PieceColor) {
        if capturer == .white {
            state.capturedByPlayer.append(victim.type.symbol)
        } else {
            state.capturedByAI.append(victim.type.symbol)
        }
    }

    private func trackRepetition() {
        let key = state.board.positionKey
        state.repetitionCounts[key, default: 0] += 1
    }

    private func continueAfterBoardChange() {
        // King captured on the board (possible via fight-created discovered
        // attacks): the game stops immediately — hard win/loss condition.
        if state.board.kingSquare(of: playerColor.opposite) == nil {
            finishGame(result: "win", detail: "King captured")
            return
        }
        if state.board.kingSquare(of: playerColor) == nil {
            finishGame(result: "loss", detail: "King captured")
            return
        }

        refreshCheckFlag()
        let repCount = state.repetitionCounts[state.board.positionKey] ?? 0
        let status = state.board.status(repetitionCount: repCount)
        switch status {
        case .ongoing:
            if state.board.turn == playerColor {
                phase = .playerTurn
            } else if opponentKind == .remote {
                // Ship the completed local actions to the opponent.
                phase = .waitingForOpponent
                onTurnEnded?(state)
            } else {
                // AI in (non-mate) check may spend a card on a king fight
                // instead of moving out of harm's way.
                if state.board.isInCheck(playerColor.opposite),
                   let c = aiCheckFightCandidates(),
                   ChessAI.shouldChallengeCheck(king: c.king, checker: c.checker,
                                                cardsLeft: state.aiCards,
                                                isMate: false,
                                                difficulty: state.difficulty) {
                    aiChallengesCheck(checkerSq: c.checkerSq, checker: c.checker,
                                      kingSq: c.kingSq, king: c.king)
                    return
                }
                runAITurn()
            }
        case .checkmate(let winner):
            // No exceptions: checkmate always resolves through the king's
            // final fight — his last chance to turn the attack around.
            startFinalStand(defender: winner.opposite)
        case .stalemate:
            finishGame(result: "draw", detail: "Stalemate")
        case .drawFiftyMove:
            finishGame(result: "draw", detail: "50-move rule")
        case .drawRepetition:
            finishGame(result: "draw", detail: "Threefold repetition")
        case .drawInsufficientMaterial:
            finishGame(result: "draw", detail: "Insufficient material")
        }
    }

    private func refreshCheckFlag() {
        playerInCheck = state.board.isInCheck(playerColor)
    }

    private func finishGame(result: String, detail: String) {
        gameResult = result
        gameResultDetail = detail
        phase = .gameOver
        if opponentKind == .cpu {
            MatchSnapshotStore.clear()
        } else {
            onMatchEnded?(result)
        }
        Haptics.success()
    }
}
