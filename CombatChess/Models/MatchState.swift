import Foundation

// MARK: - Serializable match state (PRD §5.2)

struct MatchState: Codable {
    var board: Board
    var difficulty: Difficulty
    var playerCards: Int
    var aiCards: Int
    var playerCardsStart: Int
    var aiCardsStart: Int
    /// Plies played (each side's move counts as one).
    var moveCount: Int = 0
    /// Symbols of AI pieces removed from the board (captured or KO'd).
    var capturedByPlayer: [String] = []
    /// Symbols of player pieces removed from the board.
    var capturedByAI: [String] = []
    /// Position-key counts for threefold repetition.
    var repetitionCounts: [String: Int] = [:]
    var fightLogs: [FightLog] = []
    /// Online play: a capture move awaiting the defender's challenge decision
    /// at the start of their turn (docs/ONLINE_MULTIPLAYER.md §3). The board
    /// state is pre-move while this is set.
    var pendingCaptureMove: Move?

    init(difficulty: Difficulty) {
        self.board = Board.initial
        self.difficulty = difficulty
        self.playerCards = difficulty.playerCards
        self.aiCards = difficulty.aiCards
        self.playerCardsStart = difficulty.playerCards
        self.aiCardsStart = difficulty.aiCards
        self.repetitionCounts = [board.positionKey: 1]
    }

    var playerCardsUsed: Int { return playerCardsStart - playerCards }
    var aiCardsUsed: Int { return aiCardsStart - aiCards }
}

// MARK: - Fight setup / result / log

struct FightSetup: Identifiable {
    let id = UUID()
    /// The player's (white) piece in the fight.
    let playerPiece: Piece
    /// The AI's (black) piece in the fight.
    let aiPiece: Piece
    /// True when the player's piece made the capture being challenged.
    let playerIsAttacker: Bool
    let difficulty: Difficulty
    /// True when this is a check-challenge: a king fighting for survival.
    var isCheckFight: Bool = false
    /// Seed for all game-affecting fight randomness. In online play both
    /// clients receive the host's seed so the sims match (deterministic
    /// lockstep — docs/ONLINE_MULTIPLAYER.md §2).
    var fightSeed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)
}

/// A card-challenge against a check: the checked side's king fights the
/// checking piece. King wins → checker removed (turn consumed).
/// King loses → king captured, game over.
struct CheckFight {
    let checker: Piece
    let checkerSquare: Int
    let king: Piece
    let kingSquare: Int
    /// "player" or "ai" — the side that spent the card.
    let challengedBy: String
}

struct FightResult {
    let playerWon: Bool
    /// Remaining HP after the fight (loser is at 0).
    let playerHP: Int
    let aiHP: Int
    let durationSec: Double
}

struct FightLog: Codable {
    var moveNumber: Int
    var attackerType: String
    var defenderType: String
    /// "player" or "ai" — who spent the card.
    var initiatedBy: String
    var playerWon: Bool
    /// Positive when the player's piece beat a higher-value piece.
    var upsetDelta: Int
    var durationSec: Double
}

// MARK: - Pending capture awaiting a challenge decision

struct PendingCapture {
    let move: Move
    let attacker: Piece
    let defender: Piece
    /// Actual square of the defender (differs from move.to for en passant).
    let defenderSquare: Int
    /// "player" or "ai" — the side that would spend a card to challenge.
    let challenger: String
}

// MARK: - In-flight match snapshot (resume after force-quit, PRD §7.5)

enum MatchSnapshotStore {
    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("combatchess_inflight.json")
    }

    static func save(_ state: MatchState) {
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    static func load() -> MatchState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(MatchState.self, from: data)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    static var hasSnapshot: Bool {
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
}
