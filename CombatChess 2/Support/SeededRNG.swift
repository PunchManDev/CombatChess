import Foundation

/// Deterministic SplitMix64 generator.
///
/// Online-play cornerstone (docs/ONLINE_MULTIPLAYER.md §2): every
/// game-affecting random roll in a fight flows through one of these, seeded
/// from `FightSetup.fightSeed`. Two clients with the same seed and the same
/// input stream compute byte-identical fights — the basis for lockstep
/// multiplayer and for verifying fight results by replay.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
