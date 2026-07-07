import Foundation

/// Difficulty affects both the chess layer and the fight layer (PRD §4).
enum Difficulty: String, Codable, CaseIterable, Identifiable {
    case easy, medium, hard

    var id: String { return rawValue }
    var label: String { return rawValue.capitalized }

    /// Minimax search depth (native engine; replaces the PRD's Stockfish Elo tiers).
    var searchDepth: Int {
        switch self {
        case .easy: return 1
        case .medium: return 2
        case .hard: return 3
        }
    }

    /// Chance the AI plays a random (blunder-prone) move instead of the best one.
    var blunderChance: Double {
        switch self {
        case .easy: return 0.45
        case .medium: return 0.12
        case .hard: return 0.0
        }
    }

    /// AI's action card count (PRD §4). Player always gets `playerCards`.
    var aiCards: Int {
        switch self {
        case .easy: return 2
        case .medium, .hard: return 3
        }
    }

    var playerCards: Int { return 3 }

    // MARK: - Fight tuning (PRD §4)

    /// Enemy telegraph wind-up in seconds. Deliberately tight: blocking on
    /// reaction takes real skill above Easy.
    var telegraphDuration: Double {
        switch self {
        case .easy: return 0.8
        case .medium: return 0.52
        case .hard: return 0.36
        }
    }

    /// Enemy post-strike recovery (the punish window).
    var aiRecoverDuration: Double {
        switch self {
        case .easy: return 0.85
        case .medium: return 0.6
        case .hard: return 0.42
        }
    }

    /// Chance the AI blocks a player jab outside the recovery window.
    var aiBlockChance: Double {
        switch self {
        case .easy: return 0.20
        case .medium: return 0.45
        case .hard: return 0.65
        }
    }

    /// Chance the AI dodges a player heavy outside the recovery window.
    var aiDodgeChance: Double {
        switch self {
        case .easy: return 0.30
        case .medium: return 0.55
        case .hard: return 0.75
        }
    }

    /// Chance a telegraphed attack is a heavy.
    var aiHeavyChance: Double {
        switch self {
        case .easy: return 0.15
        case .medium: return 0.25
        case .hard: return 0.35
        }
    }

    /// Idle time range between AI attacks.
    var idleRange: ClosedRange<Double> {
        switch self {
        case .easy: return 0.9...1.7
        case .medium: return 0.55...1.2
        case .hard: return 0.35...0.9
        }
    }

    /// When the AI blocks, chance it picks the matching side (full reduction).
    var aiCorrectSideChance: Double {
        switch self {
        case .easy: return 0.30
        case .medium: return 0.55
        case .hard: return 0.75
        }
    }

    /// Perfect dodges required to charge the ★ SUPER punch.
    var superMeterMax: Int {
        switch self {
        case .easy, .medium: return 3
        case .hard: return 5
        }
    }

    /// AI stamina discipline: harder AI stops attacking earlier to avoid exhaustion.
    var aiStaminaFloor: Double {
        switch self {
        case .easy: return 2
        case .medium: return 14
        case .hard: return 26
        }
    }

    // MARK: - Stockfish Elo gradient (user-tunable per tier in Settings)

    /// Adjustable Elo band for each tier.
    var eloRange: ClosedRange<Double> {
        switch self {
        case .easy: return 600...1400
        case .medium: return 1200...2200
        case .hard: return 1800...3190     // 3190 = Stockfish's UCI_Elo ceiling
        }
    }

    var defaultElo: Double {
        switch self {
        case .easy: return 900
        case .medium: return 1600
        case .hard: return 2400
        }
    }

    /// UserDefaults key for this tier's tuned Elo.
    var eloKey: String {
        return "elo_\(rawValue)"
    }

    /// The Elo currently configured for this tier (Settings slider), clamped
    /// to the tier's band. Unset (0) means the default.
    var configuredElo: Int {
        let stored = UserDefaults.standard.double(forKey: eloKey)
        let value = stored == 0 ? defaultElo : stored
        return Int(min(max(value, eloRange.lowerBound), eloRange.upperBound))
    }
}
