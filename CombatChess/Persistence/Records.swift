import Foundation
import SwiftData

/// Completed-match history (PRD §6). All data is local; no backend in V1.
@Model
final class MatchRecord {
    var date: Date
    var difficulty: String
    /// "win" / "loss" / "draw" from the player's perspective.
    var result: String
    var resultDetail: String
    var moveCount: Int
    var playerCardsUsed: Int
    var aiCardsUsed: Int
    @Relationship(deleteRule: .cascade) var fights: [FightRecord]

    init(date: Date, difficulty: String, result: String, resultDetail: String,
         moveCount: Int, playerCardsUsed: Int, aiCardsUsed: Int, fights: [FightRecord]) {
        self.date = date
        self.difficulty = difficulty
        self.result = result
        self.resultDetail = resultDetail
        self.moveCount = moveCount
        self.playerCardsUsed = playerCardsUsed
        self.aiCardsUsed = aiCardsUsed
        self.fights = fights
    }
}

@Model
final class FightRecord {
    var moveNumber: Int
    var attackerType: String
    var defenderType: String
    var initiatedBy: String
    var playerWon: Bool
    var upsetDelta: Int
    var durationSec: Double

    init(moveNumber: Int, attackerType: String, defenderType: String,
         initiatedBy: String, playerWon: Bool, upsetDelta: Int, durationSec: Double) {
        self.moveNumber = moveNumber
        self.attackerType = attackerType
        self.defenderType = defenderType
        self.initiatedBy = initiatedBy
        self.playerWon = playerWon
        self.upsetDelta = upsetDelta
        self.durationSec = durationSec
    }
}
