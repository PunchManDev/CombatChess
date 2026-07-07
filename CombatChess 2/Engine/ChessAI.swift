import Foundation

/// Native minimax chess AI with alpha-beta pruning.
/// Replaces the PRD's Stockfish suggestion (§5.1) to avoid GPL/App Store friction.
enum ChessAI {

    private static let mateScore = 100_000

    // Piece-square-lite: small bonus for central control.
    private static let centerSquares: Set<Int> = [27, 28, 35, 36]
    private static let extendedCenter: Set<Int> = [18, 19, 20, 21, 26, 29, 34, 37, 42, 43, 44, 45]

    // MARK: - Move selection

    static func bestMove(board: Board, difficulty: Difficulty) -> Move? {
        let moves = board.legalMoves(for: board.turn)
        guard !moves.isEmpty else { return nil }

        // Easy-tier blunders: sometimes just play a random legal move.
        if Double.random(in: 0..<1) < difficulty.blunderChance {
            return moves.randomElement()
        }

        var scored: [(move: Move, score: Int)] = []
        for move in moves {
            var copy = board
            copy.apply(move)
            let score = -search(board: copy, depth: difficulty.searchDepth - 1,
                                alpha: -mateScore * 2, beta: mateScore * 2)
            scored.append((move, score))
        }
        scored.sort { $0.score > $1.score }

        // Easy picks from a loose band of decent moves for variety.
        if difficulty == .easy {
            let best = scored[0].score
            let band = scored.filter { $0.score >= best - 120 }
            return band.randomElement()?.move ?? scored[0].move
        }
        return scored[0].move
    }

    /// Negamax over pseudo-legal moves; king captures resolve legality implicitly.
    private static func search(board: Board, depth: Int, alpha: Int, beta: Int) -> Int {
        if depth <= 0 {
            return evaluate(board)
        }
        var alpha = alpha
        var moves = board.pseudoMoves(for: board.turn)
        // Order captures first (MVV-lite) for pruning efficiency.
        moves.sort { a, b in
            let av = board.capturedPiece(of: a)?.type.points ?? -1
            let bv = board.capturedPiece(of: b)?.type.points ?? -1
            return av > bv
        }

        var best = -mateScore * 2
        for move in moves {
            if let victim = board.capturedPiece(of: move), victim.type == .king {
                // Opponent's king can be captured: previous move was illegal / mate line.
                return mateScore - (10 - depth)
            }
            var copy = board
            copy.apply(move)
            let score = -search(board: copy, depth: depth - 1, alpha: -beta, beta: -alpha)
            if score > best {
                best = score
            }
            if best > alpha {
                alpha = best
            }
            if alpha >= beta {
                break
            }
        }
        return best
    }

    /// Static evaluation from the perspective of the side to move (centipawns).
    private static func evaluate(_ board: Board) -> Int {
        var score = 0
        for sq in 0..<64 {
            guard let p = board.squares[sq] else { continue }
            var value = p.type.points * 100
            if p.type == .king {
                value = 0
            }
            if centerSquares.contains(sq) && p.type != .king {
                value += 15
            } else if extendedCenter.contains(sq) && (p.type == .knight || p.type == .bishop || p.type == .pawn) {
                value += 8
            }
            // Encourage pawn advancement slightly.
            if p.type == .pawn {
                let advance = p.color == .white ? SquareUtil.rank(sq) - 1 : 6 - SquareUtil.rank(sq)
                value += advance * 3
            }
            score += p.color == .white ? value : -value
        }
        return board.turn == .white ? score : -score
    }

    // MARK: - Challenge decision policy (PRD §4)

    /// Should the AI spend an action card to challenge the capture of `defender` by `attacker`?
    /// Kings never fight (PRD §2.6), so this is never called with a king on either side.
    static func shouldChallenge(defender: Piece, attacker: Piece,
                                cardsLeft: Int, difficulty: Difficulty) -> Bool {
        guard cardsLeft > 0 else { return false }
        guard attacker.type != .king, defender.type != .king else { return false }

        let defScore = Double(defender.type.points) * defender.hpFraction
        let atkScore = Double(attacker.type.points) * attacker.hpFraction

        switch difficulty {
        case .easy:
            // Scrappy: fights for most pieces, even the odd pawn.
            if defender.type.points >= 3 {
                return Double.random(in: 0..<1) < 0.65
            }
            return Double.random(in: 0..<1) < 0.25
        case .medium:
            // Value-based, but willing: fights for anything competitive,
            // always for rooks/queens, plus an occasional surprise.
            if defender.type.points >= 5 {
                return true
            }
            if defender.type.points >= 3
                && defender.hpFraction > 0.35
                && defScore >= atkScore * 0.6 {
                return true
            }
            return Double.random(in: 0..<1) < 0.2
        case .hard:
            // Value + HP-aware; saves the last card for queen/rooks (PRD §4).
            if cardsLeft == 1 && defender.type.points < 5 {
                return false
            }
            if defender.type.points >= 4 {
                return defender.hpFraction > 0.25
            }
            // Also punishes wounded attackers with cheap defenders.
            if attacker.hpFraction < 0.35 && defender.hpFraction > 0.5 {
                return true
            }
            return defender.hpFraction > 0.3 && defScore >= atkScore * 0.5
        }
    }

    /// Should the AI spend a card to have its king fight the checking piece
    /// (instead of moving out of check)? Losing this fight loses the game,
    /// so it only takes clearly favorable duels.
    static func shouldChallengeCheck(king: Piece, checker: Piece, cardsLeft: Int,
                                     isMate: Bool, difficulty: Difficulty) -> Bool {
        guard cardsLeft > 0 else { return false }
        let kingScore = Double(king.type.fightPoints) * king.hpFraction
        let checkerScore = Double(checker.type.fightPoints) * checker.hpFraction
        switch difficulty {
        case .easy:
            return false
        case .medium:
            return kingScore > checkerScore * 1.5
        case .hard:
            return kingScore > checkerScore * 1.25
        }
    }
}
