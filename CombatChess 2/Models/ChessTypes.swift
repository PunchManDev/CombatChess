import Foundation

// MARK: - Core chess types (PRD §2.1–§2.2)

enum PieceColor: String, Codable, Equatable {
    case white, black

    var opposite: PieceColor {
        return self == .white ? .black : .white
    }

    /// Sprite team asset suffix ("white"/"black").
    var teamName: String {
        return rawValue
    }
}

enum PieceType: String, Codable, CaseIterable, Equatable {
    case pawn, knight, bishop, rook, queen, king

    /// Standard point values (PRD §2.2). King is special-cased and never fights.
    var points: Int {
        switch self {
        case .pawn: return 1
        case .knight: return 3
        case .bishop: return 3
        case .rook: return 5
        case .queen: return 9
        case .king: return 0
        }
    }

    /// Fight-stat points. The king never captures on the board, but he CAN
    /// brawl when checked (last-stand rule) — he fights at rook-adjacent tier.
    var fightPoints: Int {
        return self == .king ? 4 : points
    }

    /// Fight stat formulas (PRD §2.4): Max HP = 50 + 25 × P.
    /// Exception: the king is the tankiest fighter in the game — losing him
    /// loses the game, so his last stand outlasts even the queen (275 HP) —
    /// though he still punches at his own mid-tier (see `fightPoints`).
    var maxHP: Int {
        if self == .king {
            return 300
        }
        return 50 + 25 * fightPoints
    }

    /// Jab damage = 8 + 2 × P
    var jabDamage: Int {
        return 8 + 2 * fightPoints
    }

    /// Heavy damage = 2 × jab
    var heavyDamage: Int {
        return 2 * jabDamage
    }

    var symbol: String {
        switch self {
        case .pawn: return "♟"
        case .knight: return "♞"
        case .bishop: return "♝"
        case .rook: return "♜"
        case .queen: return "♛"
        case .king: return "♚"
        }
    }

    var displayName: String {
        return rawValue.capitalized
    }

    /// Single-character code used for position keys.
    var code: String {
        switch self {
        case .pawn: return "p"
        case .knight: return "n"
        case .bishop: return "b"
        case .rook: return "r"
        case .queen: return "q"
        case .king: return "k"
        }
    }
}

struct Piece: Codable, Equatable, Identifiable {
    var id: UUID
    var type: PieceType
    var color: PieceColor
    /// Persistent fight HP for the duration of the match (PRD §2.5).
    var currentHP: Int
    var hasFought: Bool

    init(type: PieceType, color: PieceColor) {
        self.id = UUID()
        self.type = type
        self.color = color
        self.currentHP = type.maxHP
        self.hasFought = false
    }

    var maxHP: Int {
        return type.maxHP
    }

    var hpFraction: Double {
        return maxHP > 0 ? Double(currentHP) / Double(maxHP) : 0
    }
}

// MARK: - Squares

/// Squares are 0...63; index = rank * 8 + file. a1 = 0, h1 = 7, a8 = 56.
enum SquareUtil {
    static func file(_ sq: Int) -> Int { return sq % 8 }
    static func rank(_ sq: Int) -> Int { return sq / 8 }
    static func index(file: Int, rank: Int) -> Int { return rank * 8 + file }
    static func isValid(file: Int, rank: Int) -> Bool {
        return file >= 0 && file < 8 && rank >= 0 && rank < 8
    }
    static func name(_ sq: Int) -> String {
        let files = ["a", "b", "c", "d", "e", "f", "g", "h"]
        return files[file(sq)] + String(rank(sq) + 1)
    }
}

// MARK: - Moves

struct Move: Codable, Equatable {
    var from: Int
    var to: Int
    var promotion: PieceType?
    var isEnPassant: Bool
    var isCastleKingside: Bool
    var isCastleQueenside: Bool

    init(from: Int, to: Int, promotion: PieceType? = nil,
         isEnPassant: Bool = false,
         isCastleKingside: Bool = false,
         isCastleQueenside: Bool = false) {
        self.from = from
        self.to = to
        self.promotion = promotion
        self.isEnPassant = isEnPassant
        self.isCastleKingside = isCastleKingside
        self.isCastleQueenside = isCastleQueenside
    }
}

struct CastlingRights: Codable, Equatable {
    var whiteKingside = true
    var whiteQueenside = true
    var blackKingside = true
    var blackQueenside = true

    var key: String {
        var s = ""
        if whiteKingside { s += "K" }
        if whiteQueenside { s += "Q" }
        if blackKingside { s += "k" }
        if blackQueenside { s += "q" }
        return s.isEmpty ? "-" : s
    }
}

// MARK: - Game status

enum GameStatus: Equatable {
    case ongoing
    case checkmate(winner: PieceColor)
    case stalemate
    case drawFiftyMove
    case drawRepetition
    case drawInsufficientMaterial
}
