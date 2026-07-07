import Foundation

/// Full FIDE rules board: legal move generation, check detection, castling,
/// en passant, promotion, halfmove clock (PRD §2.1).
struct Board: Codable, Equatable {
    var squares: [Piece?]
    var turn: PieceColor = .white
    var castling = CastlingRights()
    /// Square "behind" a pawn that just double-pushed (the capture target square).
    var enPassantTarget: Int?
    var halfmoveClock: Int = 0
    var fullmoveNumber: Int = 1

    // MARK: - Setup

    static var initial: Board {
        var b = Board(squares: Array(repeating: nil, count: 64))
        let back: [PieceType] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
        for f in 0..<8 {
            b.squares[SquareUtil.index(file: f, rank: 0)] = Piece(type: back[f], color: .white)
            b.squares[SquareUtil.index(file: f, rank: 1)] = Piece(type: .pawn, color: .white)
            b.squares[SquareUtil.index(file: f, rank: 6)] = Piece(type: .pawn, color: .black)
            b.squares[SquareUtil.index(file: f, rank: 7)] = Piece(type: back[f], color: .black)
        }
        return b
    }

    // MARK: - Attack detection

    private static let knightDeltas = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
    private static let kingDeltas = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
    private static let bishopDirs = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    private static let rookDirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]

    /// Is `sq` attacked by any piece of `color`?
    func isAttacked(_ sq: Int, by color: PieceColor) -> Bool {
        let f = SquareUtil.file(sq)
        let r = SquareUtil.rank(sq)

        // Pawn attacks: a pawn of `color` on (f±1, r - forward) attacks sq.
        let forward = color == .white ? 1 : -1
        for df in [-1, 1] {
            let pf = f + df
            let pr = r - forward
            if SquareUtil.isValid(file: pf, rank: pr),
               let p = squares[SquareUtil.index(file: pf, rank: pr)],
               p.color == color, p.type == .pawn {
                return true
            }
        }

        // Knights
        for (df, dr) in Board.knightDeltas {
            let nf = f + df
            let nr = r + dr
            if SquareUtil.isValid(file: nf, rank: nr),
               let p = squares[SquareUtil.index(file: nf, rank: nr)],
               p.color == color, p.type == .knight {
                return true
            }
        }

        // King adjacency
        for (df, dr) in Board.kingDeltas {
            let nf = f + df
            let nr = r + dr
            if SquareUtil.isValid(file: nf, rank: nr),
               let p = squares[SquareUtil.index(file: nf, rank: nr)],
               p.color == color, p.type == .king {
                return true
            }
        }

        // Diagonal sliders
        for (df, dr) in Board.bishopDirs {
            var nf = f + df
            var nr = r + dr
            while SquareUtil.isValid(file: nf, rank: nr) {
                if let p = squares[SquareUtil.index(file: nf, rank: nr)] {
                    if p.color == color && (p.type == .bishop || p.type == .queen) {
                        return true
                    }
                    break
                }
                nf += df
                nr += dr
            }
        }

        // Straight sliders
        for (df, dr) in Board.rookDirs {
            var nf = f + df
            var nr = r + dr
            while SquareUtil.isValid(file: nf, rank: nr) {
                if let p = squares[SquareUtil.index(file: nf, rank: nr)] {
                    if p.color == color && (p.type == .rook || p.type == .queen) {
                        return true
                    }
                    break
                }
                nf += df
                nr += dr
            }
        }

        return false
    }

    func kingSquare(of color: PieceColor) -> Int? {
        for i in 0..<64 {
            if let p = squares[i], p.type == .king, p.color == color {
                return i
            }
        }
        return nil
    }

    func isInCheck(_ color: PieceColor) -> Bool {
        guard let k = kingSquare(of: color) else { return false }
        return isAttacked(k, by: color.opposite)
    }

    /// Squares of enemy pieces currently giving check to `color`'s king.
    /// Used by the check-challenge rule (card-challenge only on single check).
    func checkers(of color: PieceColor) -> [Int] {
        guard let kingSq = kingSquare(of: color) else { return [] }
        var result: [Int] = []
        let enemyMoves = pseudoMoves(for: color.opposite)
        for move in enemyMoves where move.to == kingSq {
            if !result.contains(move.from) {
                result.append(move.from)
            }
        }
        return result
    }

    // MARK: - Move generation

    func pseudoMoves(for color: PieceColor) -> [Move] {
        var moves: [Move] = []
        for sq in 0..<64 {
            guard let piece = squares[sq], piece.color == color else { continue }
            switch piece.type {
            case .pawn:
                pawnMoves(from: sq, color: color, into: &moves)
            case .knight:
                stepMoves(from: sq, color: color, deltas: Board.knightDeltas, into: &moves)
            case .bishop:
                slideMoves(from: sq, color: color, dirs: Board.bishopDirs, into: &moves)
            case .rook:
                slideMoves(from: sq, color: color, dirs: Board.rookDirs, into: &moves)
            case .queen:
                slideMoves(from: sq, color: color, dirs: Board.bishopDirs + Board.rookDirs, into: &moves)
            case .king:
                stepMoves(from: sq, color: color, deltas: Board.kingDeltas, into: &moves)
                castleMoves(from: sq, color: color, into: &moves)
            }
        }
        return moves
    }

    private func pawnMoves(from sq: Int, color: PieceColor, into moves: inout [Move]) {
        let f = SquareUtil.file(sq)
        let r = SquareUtil.rank(sq)
        let forward = color == .white ? 1 : -1
        let startRank = color == .white ? 1 : 6
        let promoRank = color == .white ? 7 : 0

        // Push
        let oneRank = r + forward
        if SquareUtil.isValid(file: f, rank: oneRank) {
            let one = SquareUtil.index(file: f, rank: oneRank)
            if squares[one] == nil {
                appendPawnMove(from: sq, to: one, promoRank: promoRank, into: &moves)
                // Double push
                if r == startRank {
                    let two = SquareUtil.index(file: f, rank: r + 2 * forward)
                    if squares[two] == nil {
                        moves.append(Move(from: sq, to: two))
                    }
                }
            }
        }

        // Captures + en passant
        for df in [-1, 1] {
            let nf = f + df
            let nr = r + forward
            guard SquareUtil.isValid(file: nf, rank: nr) else { continue }
            let target = SquareUtil.index(file: nf, rank: nr)
            if let victim = squares[target], victim.color != color {
                appendPawnMove(from: sq, to: target, promoRank: promoRank, into: &moves)
            } else if let ep = enPassantTarget, ep == target {
                moves.append(Move(from: sq, to: target, isEnPassant: true))
            }
        }
    }

    private func appendPawnMove(from: Int, to: Int, promoRank: Int, into moves: inout [Move]) {
        if SquareUtil.rank(to) == promoRank {
            // V1: auto-queen (see README).
            moves.append(Move(from: from, to: to, promotion: .queen))
        } else {
            moves.append(Move(from: from, to: to))
        }
    }

    private func stepMoves(from sq: Int, color: PieceColor, deltas: [(Int, Int)], into moves: inout [Move]) {
        let f = SquareUtil.file(sq)
        let r = SquareUtil.rank(sq)
        for (df, dr) in deltas {
            let nf = f + df
            let nr = r + dr
            guard SquareUtil.isValid(file: nf, rank: nr) else { continue }
            let target = SquareUtil.index(file: nf, rank: nr)
            if let p = squares[target] {
                if p.color != color {
                    moves.append(Move(from: sq, to: target))
                }
            } else {
                moves.append(Move(from: sq, to: target))
            }
        }
    }

    private func slideMoves(from sq: Int, color: PieceColor, dirs: [(Int, Int)], into moves: inout [Move]) {
        let f = SquareUtil.file(sq)
        let r = SquareUtil.rank(sq)
        for (df, dr) in dirs {
            var nf = f + df
            var nr = r + dr
            while SquareUtil.isValid(file: nf, rank: nr) {
                let target = SquareUtil.index(file: nf, rank: nr)
                if let p = squares[target] {
                    if p.color != color {
                        moves.append(Move(from: sq, to: target))
                    }
                    break
                }
                moves.append(Move(from: sq, to: target))
                nf += df
                nr += dr
            }
        }
    }

    private func castleMoves(from sq: Int, color: PieceColor, into moves: inout [Move]) {
        let homeRank = color == .white ? 0 : 7
        guard sq == SquareUtil.index(file: 4, rank: homeRank) else { return }
        guard !isInCheck(color) else { return }
        let enemy = color.opposite

        let kingside = color == .white ? castling.whiteKingside : castling.blackKingside
        if kingside {
            let f1 = SquareUtil.index(file: 5, rank: homeRank)
            let g1 = SquareUtil.index(file: 6, rank: homeRank)
            let h1 = SquareUtil.index(file: 7, rank: homeRank)
            if squares[f1] == nil, squares[g1] == nil,
               let rook = squares[h1], rook.type == .rook, rook.color == color,
               !isAttacked(f1, by: enemy), !isAttacked(g1, by: enemy) {
                moves.append(Move(from: sq, to: g1, isCastleKingside: true))
            }
        }

        let queenside = color == .white ? castling.whiteQueenside : castling.blackQueenside
        if queenside {
            let d1 = SquareUtil.index(file: 3, rank: homeRank)
            let c1 = SquareUtil.index(file: 2, rank: homeRank)
            let b1 = SquareUtil.index(file: 1, rank: homeRank)
            let a1 = SquareUtil.index(file: 0, rank: homeRank)
            if squares[d1] == nil, squares[c1] == nil, squares[b1] == nil,
               let rook = squares[a1], rook.type == .rook, rook.color == color,
               !isAttacked(d1, by: enemy), !isAttacked(c1, by: enemy) {
                moves.append(Move(from: sq, to: c1, isCastleQueenside: true))
            }
        }
    }

    func legalMoves(for color: PieceColor) -> [Move] {
        return pseudoMoves(for: color).filter { move in
            var copy = self
            copy.apply(move)
            return !copy.isInCheck(color)
        }
    }

    // MARK: - Captures

    /// Square of the piece a move would capture, accounting for en passant.
    func capturedSquare(of move: Move) -> Int? {
        if move.isEnPassant {
            guard let mover = squares[move.from] else { return nil }
            let forward = mover.color == .white ? 1 : -1
            return move.to - 8 * forward
        }
        return squares[move.to] != nil ? move.to : nil
    }

    func capturedPiece(of move: Move) -> Piece? {
        guard let sq = capturedSquare(of: move) else { return nil }
        return squares[sq]
    }

    // MARK: - Applying moves

    mutating func apply(_ move: Move) {
        guard var piece = squares[move.from] else { return }
        let isCapture = capturedSquare(of: move) != nil

        halfmoveClock += 1
        if piece.type == .pawn || isCapture {
            halfmoveClock = 0
        }

        // En passant victim removal
        if move.isEnPassant, let victimSq = capturedSquare(of: move) {
            squares[victimSq] = nil
        }

        // Captured rook affects castling rights
        clearRights(forCorner: move.to)

        squares[move.from] = nil

        // Promotion: keep HP percentage against the new max (PRD §2.7).
        if let promo = move.promotion {
            let pct = piece.hpFraction
            piece.type = promo
            piece.currentHP = max(1, Int((Double(piece.maxHP) * pct).rounded()))
        }

        squares[move.to] = piece

        // Castling rook hop
        let homeRank = piece.color == .white ? 0 : 7
        if move.isCastleKingside {
            let h = SquareUtil.index(file: 7, rank: homeRank)
            let f = SquareUtil.index(file: 5, rank: homeRank)
            squares[f] = squares[h]
            squares[h] = nil
        } else if move.isCastleQueenside {
            let a = SquareUtil.index(file: 0, rank: homeRank)
            let d = SquareUtil.index(file: 3, rank: homeRank)
            squares[d] = squares[a]
            squares[a] = nil
        }

        // Rights lost by moving king/rook
        if piece.type == .king {
            if piece.color == .white {
                castling.whiteKingside = false
                castling.whiteQueenside = false
            } else {
                castling.blackKingside = false
                castling.blackQueenside = false
            }
        }
        clearRights(forCorner: move.from)

        // New en passant target
        if piece.type == .pawn, abs(SquareUtil.rank(move.to) - SquareUtil.rank(move.from)) == 2 {
            enPassantTarget = (move.from + move.to) / 2
        } else {
            enPassantTarget = nil
        }

        if turn == .black {
            fullmoveNumber += 1
        }
        turn = turn.opposite
    }

    /// Clear castling rights tied to a corner square (rook moved, captured, or KO'd in a fight).
    mutating func clearRights(forCorner sq: Int) {
        switch sq {
        case 0: castling.whiteQueenside = false
        case 7: castling.whiteKingside = false
        case 56: castling.blackQueenside = false
        case 63: castling.blackKingside = false
        default: break
        }
    }

    // MARK: - FEN / UCI interop (Stockfish integration)

    /// Standard FEN string for the current position.
    var fen: String {
        var placement: [String] = []
        for rank in (0..<8).reversed() {
            var row = ""
            var empty = 0
            for file in 0..<8 {
                if let piece = squares[SquareUtil.index(file: file, rank: rank)] {
                    if empty > 0 {
                        row += String(empty)
                        empty = 0
                    }
                    let code = piece.type.code
                    row += piece.color == .white ? code.uppercased() : code
                } else {
                    empty += 1
                }
            }
            if empty > 0 {
                row += String(empty)
            }
            placement.append(row)
        }
        let side = turn == .white ? "w" : "b"
        let ep = enPassantTarget.map { SquareUtil.name($0) } ?? "-"
        return placement.joined(separator: "/")
            + " \(side) \(castling.key) \(ep) \(halfmoveClock) \(fullmoveNumber)"
    }

    /// Converts a UCI move string (e.g. "e2e4", "e7e8q") into one of the
    /// current legal moves, so castle/en-passant flags come out correct.
    func move(fromUCI uci: String) -> Move? {
        let chars = Array(uci.lowercased())
        guard chars.count >= 4 else { return nil }

        func fileIndex(_ c: Character) -> Int? {
            guard let v = c.asciiValue else { return nil }
            let idx = Int(v) - 97
            return (0..<8).contains(idx) ? idx : nil
        }
        func rankIndex(_ c: Character) -> Int? {
            guard let v = c.wholeNumberValue else { return nil }
            let idx = v - 1
            return (0..<8).contains(idx) ? idx : nil
        }
        guard let f0 = fileIndex(chars[0]), let r0 = rankIndex(chars[1]),
              let f1 = fileIndex(chars[2]), let r1 = rankIndex(chars[3]) else { return nil }
        let from = SquareUtil.index(file: f0, rank: r0)
        let to = SquareUtil.index(file: f1, rank: r1)

        var promotion: PieceType?
        if chars.count >= 5 {
            switch chars[4] {
            case "q": promotion = .queen
            case "r": promotion = .rook
            case "b": promotion = .bishop
            case "n": promotion = .knight
            default: promotion = nil
            }
        }

        let legal = legalMoves(for: turn)
        if let exact = legal.first(where: { $0.from == from && $0.to == to && $0.promotion == promotion }) {
            return exact
        }
        // Promotion-piece mismatch fallback (our generator auto-queens).
        return legal.first { $0.from == from && $0.to == to }
    }

    // MARK: - Status

    /// Position key for threefold repetition tracking.
    var positionKey: String {
        var s = ""
        for i in 0..<64 {
            if let p = squares[i] {
                s += p.color == .white ? p.type.code.uppercased() : p.type.code
            } else {
                s += "."
            }
        }
        s += turn == .white ? "w" : "b"
        s += castling.key
        s += enPassantTarget.map { String($0) } ?? "-"
        return s
    }

    /// Evaluate status for the side to move. Repetition count supplied by the match controller.
    func status(repetitionCount: Int) -> GameStatus {
        if legalMoves(for: turn).isEmpty {
            if isInCheck(turn) {
                return .checkmate(winner: turn.opposite)
            }
            return .stalemate
        }
        if halfmoveClock >= 100 {
            return .drawFiftyMove
        }
        if repetitionCount >= 3 {
            return .drawRepetition
        }
        if hasInsufficientMaterial {
            return .drawInsufficientMaterial
        }
        return .ongoing
    }

    private var hasInsufficientMaterial: Bool {
        var minors = 0
        for i in 0..<64 {
            guard let p = squares[i] else { continue }
            switch p.type {
            case .king:
                continue
            case .knight, .bishop:
                minors += 1
            default:
                return false // pawn, rook, or queen on board
            }
        }
        return minors <= 1
    }
}
