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
    /// The last move applied to the board, so the receiving device can animate
    /// the opponent's move (the board itself is already at the post-move state).
    var lastAppliedMove: Move?
    /// Color-absolute summary of the most recent fight, so the player who
    /// didn't watch it can be shown the outcome (QoL). Version increments per
    /// fight so each side shows it exactly once.
    var lastFightSummary: FightSummary?
    var fightSummaryVersion: Int = 0

    init(difficulty: Difficulty) {
        self.board = Board.initial
        self.difficulty = difficulty
        self.playerCards = difficulty.playerCards
        self.aiCards = difficulty.aiCards
        self.playerCardsStart = difficulty.playerCards
        self.aiCardsStart = difficulty.aiCards
        self.repetitionCounts = [board.positionKey: 1]
    }

    // MARK: - Forward/backward-compatible decoding
    //
    // CRITICAL: Swift's synthesized `Codable` IGNORES inline property defaults
    // when decoding — a missing key throws. That would make save files and
    // Game Center turn data written by a different app version undecodable,
    // and an undecodable online turn is destructive (see OnlineMatchCoordinator).
    // So every field added after the original format decodes with
    // `decodeIfPresent` and falls back to its default. New fields MUST follow
    // this pattern; never rely on an inline default alone.

    private enum CodingKeys: String, CodingKey {
        case board, difficulty, playerCards, aiCards, playerCardsStart, aiCardsStart
        case moveCount, capturedByPlayer, capturedByAI, repetitionCounts, fightLogs
        case pendingCaptureMove, lastAppliedMove, lastFightSummary, fightSummaryVersion
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Core fields: present in every version; a genuine absence is corruption.
        board = try c.decode(Board.self, forKey: .board)
        difficulty = try c.decode(Difficulty.self, forKey: .difficulty)
        playerCards = try c.decode(Int.self, forKey: .playerCards)
        aiCards = try c.decode(Int.self, forKey: .aiCards)
        playerCardsStart = try c.decode(Int.self, forKey: .playerCardsStart)
        aiCardsStart = try c.decode(Int.self, forKey: .aiCardsStart)
        // Everything below tolerates absence (older or newer peers).
        moveCount = try c.decodeIfPresent(Int.self, forKey: .moveCount) ?? 0
        capturedByPlayer = try c.decodeIfPresent([String].self, forKey: .capturedByPlayer) ?? []
        capturedByAI = try c.decodeIfPresent([String].self, forKey: .capturedByAI) ?? []
        repetitionCounts = try c.decodeIfPresent([String: Int].self, forKey: .repetitionCounts) ?? [:]
        fightLogs = try c.decodeIfPresent([FightLog].self, forKey: .fightLogs) ?? []
        pendingCaptureMove = try c.decodeIfPresent(Move.self, forKey: .pendingCaptureMove)
        lastAppliedMove = try c.decodeIfPresent(Move.self, forKey: .lastAppliedMove)
        lastFightSummary = try c.decodeIfPresent(FightSummary.self, forKey: .lastFightSummary)
        fightSummaryVersion = try c.decodeIfPresent(Int.self, forKey: .fightSummaryVersion) ?? 0
    }

    /// A decoded state is only usable if the board survived the trip. Turn data
    /// arrives from a remote device, so treat it as untrusted: the engine and
    /// views index `squares` over a hard 0..<64 range and would crash otherwise.
    var isStructurallyValid: Bool {
        return board.squares.count == 64
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

/// Color-absolute record of a fight's result — interpreted identically on
/// both devices to build the waiting player's outcome recap.
struct FightSummary: Codable {
    var attackerType: String
    var attackerColor: PieceColor
    var defenderType: String
    var defenderColor: PieceColor
    /// True if the capturing (attacking) piece won, i.e. the capture stood.
    var attackerWon: Bool
    var isCheckFight: Bool
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
        guard let state = try? JSONDecoder().decode(MatchState.self, from: data),
              state.isStructurallyValid else {
            // A save from an incompatible/corrupt build: discard it rather than
            // resuming into a crash. The player just starts a new game.
            print("CombatChess: discarding unreadable saved game")
            clear()
            return nil
        }
        return state
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    static var hasSnapshot: Bool {
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
}
