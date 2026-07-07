# Combat Chess — V1 (iOS)

Chess where captures can be challenged into a Punch-Out-style fight. Built per the Combat Chess PRD v1.0.

## Requirements

- **Xcode 16 or newer** (the project uses Xcode's folder-synchronized project format)
- iOS 17.0+ device or simulator

## Build & Run

1. Open `CombatChess.xcodeproj` in Xcode. Xcode will automatically resolve the
   **ChessKitEngine** Swift package (needs network access on first open).
2. Select the **CombatChess** scheme and a simulator (e.g., iPhone 16).
3. Press **Run** (⌘R).
4. To run on a physical device, set your development team under *Signing & Capabilities*.

## Chess engine: Stockfish 17 (with native fallback)

The AI opponent uses **Stockfish 17** via the MIT-licensed
[ChessKitEngine](https://github.com/chesskit-app/chesskit-engine) package
(already referenced in the project). Each difficulty maps to a **tunable Elo**
(Settings → CPU Strength): Easy 600–1400 (default 900), Medium 1200–2200
(default 1600), Hard 1800–3190 (default 2400). At 1320+ the engine is
Elo-calibrated via `UCI_LimitStrength`/`UCI_Elo`; below 1320 (Stockfish's
floor) strength is approximated with low Skill Level and shallow search.
The current Elo for each tier is shown inside its selector button on the
start screen.

**One manual step — NNUE networks.** Stockfish 17 requires two neural-network
files that aren't bundled with the package:

1. Download `nn-1111cefa1111.nnue` (large, ~75 MB) and `nn-37f18f62d772.nnue`
   (small, ~5 MB) from <https://tests.stockfishchess.org/nns> (search the
   network name).
2. Drop both files into the `CombatChess/CombatChess/` folder in Finder —
   the project picks them up automatically as bundle resources.

**Without the networks the app still works:** `EngineManager` detects that
Stockfish can't evaluate and every move silently falls back to the built-in
Swift minimax engine (the pre-Stockfish AI). The same fallback covers any
engine failure at runtime, so the match never stalls.

**Licensing:** Combat Chess is distributed under the **GNU GPLv3** (see
`LICENSE`) because it bundles Stockfish (GPLv3). Selling the app is permitted;
keeping the source secret is not. Compliance checklist for App Store release:

1. Publish this repository publicly and set the URL in
   `LicensesView.sourceURL` (Settings → Open Source & Licenses links to it —
   that screen is the GPL "Appropriate Legal Notices" + written source offer).
2. Keep `LICENSE` and the bundled `gpl-3.0.txt` in the repo/app.
3. Keep the published source in sync with each released build (GPLv3 §6d).

The ChessKitEngine wrapper is MIT. The Combat Chess *name* and pixel-art
assets can optionally be licensed separately from the GPL'd code to
discourage verbatim App Store clones (consult a lawyer for that split).

**App Store submission checklist (remaining manual steps):**

- Set your real source-repo URL in `LicensesView.sourceURL`.
- Privacy: `PrivacyInfo.xcprivacy` is included (UserDefaults CA92.1, file
  timestamps C617.1); complete the App Privacy questionnaire in App Store
  Connect (no tracking, no data collection) and provide a privacy policy URL.
- Encryption: `ITSAppUsesNonExemptEncryption = NO` is set via build settings;
  confirm the key appears in the built Info.plist (add manually if not).
- Device QA on hardware: full matches per difficulty, every fight trigger,
  force-quit resume, and online matches between two sandbox accounts.
- Store metadata: screenshots, description, keywords, age rating
  (cartoon/fantasy violence), support URL.

## How to Play

You play white. Standard chess rules apply. Each side has a finite number of **Action Cards** (you: 3; AI: 2 on Easy, 3 otherwise).

- When the AI captures your piece, you get a 10-second prompt to spend a card and **challenge** the capture.
- When you capture an AI piece, the AI may spend its own card to challenge you.
- Challenges launch a real-time fight with **six on-screen buttons** (SF2-style):
  - **L PUNCH** — fast lead jab (low damage, short cooldown, −8 stamina)
  - **R PUNCH** — rear cross (high damage, wind-up + long cooldown, −16 stamina)
  - **L BLOCK / R BLOCK** (hold) — guard that side. Foe's **LIGHT** attacks hit your LEFT, **HEAVY** attacks hit your RIGHT (watch the telegraph cue). Correct side = 80% reduction; wrong side = 45%. Holding block drains stamina; absorbing a blocked hit drains more.
  - **DODGE** — timed and risky: pressed just before impact it negates ALL damage and fills the counter meter (full meter unlocks **★ SUPER**, 2.5× damage — 3 perfect dodges on Easy/Medium, **5 on Hard**). It always costs stamina, and a **mistimed dodge leaves you off-balance for ~0.5 s — hits during that window deal 1.4×**.
- **Stamina** (teal bar): every action drains it — punching, dodging, holding block, eating blocked hits. Only standing idle regenerates it. At zero you're **EXHAUSTED**: you can't punch, block, or dodge, and you take **1.5× damage** until you recover to 30. The AI runs the same stamina rules — bait its punches, drain its guard, and punish the slump.
- **No mashing:** rapid button presses build *heat* that multiplies stamina costs (up to ~3×) and makes held blocks drain faster. The enemy attacks fast (telegraphs down to ~0.36 s on Hard), so clean reads beat spam every time.
- Piece stats scale with chess point value (`HP = 50 + 25×P`, `jab = 8 + 2×P`). A pawn *can* beat a queen, but it had better dodge everything.
- **Damage persists for the whole match.** Fought pieces show an HP bar on the board (both sides — open information).
- If a fight times out (60 s), the fighter with the higher HP percentage wins; ties go to the attacker.
- Win the fight as attacker → the capture stands. Win as defender → the attacker is removed from the board instead.
- **The king never falls without a fight (no exceptions):** every match ends in the ring. **Checkmate always resolves through a mandatory, free final fight** — the doomed king duels the mating piece. Win it and the checker is slain, the mate is broken, and the game continues (the fight consumes that side's turn); lose and the king is **captured — game over**. Any direct king capture on the board resolves the same way. This applies to both sides: checkmate the AI and you must finish its king yourself — and it can turn your mate around by beating your piece.
- **Check (before mate)** still offers choices: move out of harm's way, resign, or **spend a card** to send your king after the checking piece early. The AI does this too when the duel favors its king. Kings are the tankiest fighters in the game — **300 HP**, more than even the queen — but punch at a mid-tier (jab 16), and their damage persists across fights, so a king who survives multiple last stands is living on borrowed time.

## Design language (v1.2)

The app uses a unified retro-arcade pixel style inspired by Street Fighter 2:

- **Fights are side-view** with 96px jointed pixel fighters in classic SF1-brawler anatomy — bare muscled torsos (pecs/abs/traps in 4-tone skin), baggy fold-shaded pants, bare fists with heraldic wristbands. The White army fights in pale trousers with blue accents, the Black army in dark trousers with red; the rook is a stone golem and the queen fights in her gown. Every piece has 14 animation frames (idle ×3 stance-bob, left/right wind-ups, punches, blocks, two-stage dodge, hit, exhausted, KO sprawl). SF2-style HUD: dual HP + stamina bars converging on a center timer, telegraph side cues, FIGHT!/K.O.! banners, hit sparks, damage pops.
- **Stages per difficulty:** Suburban Dojo (Easy), Dusk Rooftop (Medium), Throne Room (Hard).
- **Board** uses textured pixel tiles and pixel piece icons; the landing screen is an arcade title screen with pixel logo and marquee fighters.
- All 100+ assets are generated by `pixelgen.py` (Python/Pillow) in the repo root — edit it and re-run to restyle everything. Rendering uses nearest-neighbor everywhere (`PixelKit.swift`) so sprites stay crisp.

## Online multiplayer (in progress)

Head-to-head play over Game Center — turn-based chess via `GKTurnBasedMatch`
plus live fights via real-time `GKMatch` with deterministic lockstep — is
designed in **`docs/ONLINE_MULTIPLAYER.md`**. The foundation is already in
the codebase: seeded deterministic fight randomness (`SplitMix64`,
`FightSetup.fightSeed`), the `GameKitManager` (auth, matchmaker, fight
session skeleton), the `NetMessage` wire protocol, and the Game Center
entitlement. Requires an Apple Developer account with the Game Center
capability enabled on the App ID before the entitlement will sign.

## Project Layout

```
CombatChess/
├── CombatChessApp.swift        App entry, SwiftData container
├── Models/
│   ├── ChessTypes.swift        Pieces, squares, moves, stat formulas (PRD §2.2, §2.4)
│   ├── ChessBoard.swift        Full FIDE rules engine (PRD §2.1)
│   ├── Difficulty.swift        Chess + fight tuning per tier (PRD §4)
│   ├── MatchState.swift        Serializable match state, fight types, resume store
│   └── MatchController.swift   Turn/challenge/fight state machine (PRD §5.2)
├── Engine/ChessAI.swift        Minimax AI + card challenge policy
├── Fight/FightScene.swift      SpriteKit Punch-Out minigame (PRD §2.4)
├── Views/                      Landing, Match/Board, Fight, History, Settings
├── Persistence/Records.swift   SwiftData match/fight history (PRD §6)
└── Support/Haptics.swift       Haptics + system SFX
```

## Deliberate deviations from the PRD

- **Native minimax engine instead of Stockfish** — resolves the GPL/App Store question (PRD §8 Q2). Difficulty comes from search depth (1/2/3) plus a blunder rate, rather than UCI Elo limits. Hard is solid casual-level, not ~2000 Elo; swap in a stronger engine later if desired behind the same `ChessAI.bestMove` interface.
- **Player is locked to white** (PRD §8 Q1 default).
- **Pawn promotion is auto-queen** in V1 (no underpromotion picker). The promotion-capture-challenge rule from §2.7 is fully implemented, including HP-percentage scaling.
- **Audio uses system sounds** — no bundled audio assets yet; haptics are fully implemented.
- **No skippable/auto-resolved fights** (PRD §8 Q4) — flagged as a post-V1 accessibility setting.

## Status vs. V1 acceptance criteria (PRD §7)

Implemented: full rules incl. castling, en passant, promotion, 50-move, threefold repetition, insufficient material; challenge flow with card ledger on both sides; persistent HP across fights; defender-win removal + correct turn order; promotion-challenge edge case; SwiftData history surviving restarts; in-flight match resume after force-quit; three distinct difficulty tiers in both layers. Recommended before shipping: run a perft suite against `Board.legalMoves` and profile the fight scene on target hardware.
