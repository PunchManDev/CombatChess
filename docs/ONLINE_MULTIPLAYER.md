# Combat Chess — Online Multiplayer Technical Design

Target: full head-to-head play via Apple Game Center — the chess board **and**
the fight minigame, player vs. player, with friend challenges.

## 1. Architecture: hybrid session model

Two Game Center technologies, one per layer:

| Layer | Tech | Why |
|---|---|---|
| Chess match | `GKTurnBasedMatch` | Async turns, push notifications, friend invites via the system matchmaker UI, 64 KB state per turn (our `MatchState` JSON is ~4 KB). Matches survive app kills; players can run several at once. |
| Fight minigame | `GKMatch` (real-time) | Sub-100 ms peer messaging for live punch/block/dodge exchanges. A session is created **on demand** when a fight triggers, and torn down after the KO. |

Flow: chess proceeds turn-based. When a challenge is accepted (or a king
fight triggers), both clients receive a `fightStart` handshake in the turn
data, open a real-time `GKMatch` scoped to the two participants, play the
fight live, then the authoritative result is written back into the
turn-based match data and the real-time session closes.

**Fallback:** if the real-time session can't connect within 10 s (one player
offline/NAT failure), the fight downgrades to the single-player model — the
challenged side fights a CPU-controlled proxy of the opponent's piece, and
the result is still binding. This keeps async matches playable end-to-end.

## 2. Fight netcode: deterministic lockstep

The fight becomes a **deterministic simulation driven only by (seed, input
streams)**. Requirements, in order:

1. **Seeded RNG** ✅ *(implemented)* — all game-affecting randomness in
   `FightScene` (AI attack choice, block/dodge rolls, idle timing) now flows
   through a `SplitMix64` generator seeded from `FightSetup.fightSeed`. Both
   clients receive the seed in the `fightStart` handshake; identical seeds +
   identical inputs ⇒ identical fights.
2. **Fixed-tick simulation** *(M3)* — fight logic moves from wall-clock
   `update(_:)` deltas to a 60 Hz tick counter. All timers (telegraphs,
   cooldowns, stamina drain/regen) become tick counts. SpriteKit actions stay
   for *visuals only*; they must never drive game state.
3. **Input-delay lockstep** *(M3)* — each client samples its buttons every
   tick and sends `fightInput(tick, action)` (unreliable + redundant: each
   packet carries the last 5 ticks of input). Inputs execute at `tick + 3`
   (~50 ms delay) on both sides. If a remote input hasn't arrived by its
   execution tick, the sim stalls (classic lockstep) — acceptable at 3-tick
   delay on same-region connections.
4. **Desync detection** *(M3)* — every 60 ticks each client sends a checksum
   of (both HP, both stamina, tick). On mismatch: the **fight host** (the
   challenged side) is authoritative — it sends a state snapshot and the
   guest rebases. Repeated desync (>2) ends the fight via host resolution.
5. **Disconnect rule** — if a peer drops mid-fight and doesn't reconnect
   within 10 s, the connected player wins the fight at current HP values.
   Rage-quitting a fight therefore loses the piece (or the king).

Note on rollback (GGPO-style): not needed for v1. Punch windows here are
150–300 ms — an input delay of 50 ms is playable. Rollback can come later
without protocol changes since the sim is already deterministic.

## 3. Turn-based flow changes

- **Participant abstraction** *(M1)*: `MatchController` gains
  `enum Opponent { case cpu(Difficulty), case remote(GKTurnBasedMatch) }`.
  All `runAITurn`/`ChessAI` call sites route through it; remote turns arrive
  via `GKTurnBasedEventListener` and replay the opponent's `NetMessage`s.
- **Challenge windows**: the 10 s capture-challenge prompt works only when
  both players are live. Online rules:
  - If both connected (real-time channel open): keep the 10 s prompt.
  - Otherwise the capture-challenge decision happens **at the start of the
    defender's next turn** ("Your queen was taken — spend a card?"), before
    their move. Turn data encodes the pending capture.
- **Card plays, king fights, resignations** all ship as `NetMessage` values
  inside the turn payload (see `Net/GameKitManager.swift`).
- **Match state authority**: full `MatchState` JSON travels with every turn;
  receivers validate the opponent's moves against their own rules engine
  (both clients run identical logic) and flag divergence.

## 4. Cheating stance

Friendly-play trust model, with tamper checks: both clients re-validate every
chess move; fight results embed the input-stream hash so a falsified result
can be detected by replaying the deterministic sim. No server, so a
determined cheater with a modified client can win fights — acceptable for
friends-and-matchmaking play; a relay server is the eventual fix if needed.

## 5. Prerequisites & ops

- Apple Developer Program account; app record in App Store Connect with
  **Game Center capability** enabled (the `com.apple.developer.game-center`
  entitlement is already in the project).
- Testing requires sandbox Game Center accounts on two devices/simulators;
  real-time `GKMatch` testing needs TestFlight or two physical devices for
  realistic latency.

## 6. Milestones

| Milestone | Scope | Effort |
|---|---|---|
| **M1 — Turn-based online** | Auth ✅ (manager built), matchmaker UI, participant refactor, turn send/receive with full-state validation, async challenge flow, match list screen. Fights play vs. CPU proxy. | ~2–3 wks |
| **M2 — Live fight handshake** | Real-time session open/close around fights, `fightStart` seed exchange, CPU-proxy fallback path. | ~1 wk |
| **M3 — Deterministic lockstep fights** | Fixed-tick sim refactor, input-delay lockstep, checksums, host authority, disconnect rules. | ~3–4 wks |
| **M4 — Polish** | Reconnection, spectating the opponent's king fights, emotes, leaderboards (win streaks), rematch flow. | ~1–2 wks |

Status: **M1 implemented** — `MatchController` supports remote opponents
(`opponentKind`/`localColor`, color-keyed cards & trays, board flip for
Black), challengeable captures defer via `MatchState.pendingCaptureMove` to
the defender's turn (async prompt, no countdown), fights run locally vs. CPU
proxy, and `OnlineMatchCoordinator` bridges everything to
`GKTurnBasedMatch` (turn send/receive, outcomes, resignation). Turn events
route through `GameKitManager`'s `GKLocalPlayerListener`.

M1 known gaps (next passes): full move-replay validation of incoming states
(currently trusted), fight-log/history semantics for the black-side player,
and a match list for juggling multiple concurrent games (currently the most
recently activated match opens). M2 (live fight handshake) is next.
