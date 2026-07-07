# ♞🥊 Combat Chess

**Chess where captures don't go quietly.** Every capture can be challenged
into a real-time, Street Fighter-style pixel brawl — and the piece that wins
the fight keeps the square. Checkmate isn't the end either: the king always
gets one last stand in the ring.

![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)
![Platform: iOS 17+](https://img.shields.io/badge/Platform-iOS%2017%2B-lightgrey.svg)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange.svg)
![Engine: Stockfish 17](https://img.shields.io/badge/Engine-Stockfish%2017-green.svg)

A native iOS game in SwiftUI + SpriteKit. Free software under the GPLv3 —
clone it, build it, mod it, learn from it.

---

## Features

- **Full FIDE chess** — native Swift rules engine (castling, en passant,
  promotion, all draw conditions) with **Stockfish 17** as the CPU opponent,
  tunable on an Elo gradient per difficulty (600 → 3190) in Settings.
- **Action-card challenges** — each side gets 3 cards per match. When your
  piece is captured, spend one to force a fight: the winner stays on the
  board. Damage persists for the whole match.
- **SF2-style fight minigame** — six-button combat (L/R punch, L/R block,
  timed dodge, star punch), a stamina economy that punishes button-mashing,
  side-matched blocking, and exhaustion states.
- **The king's last stand** — checkmate always resolves through one final
  fight. Win it and the mate is broken; lose and the king is captured.
- **Online multiplayer (Game Center)** — async turn-based matches with
  friend invites; live lockstep fights are on the roadmap
  ([design doc](docs/ONLINE_MULTIPLAYER.md)).
- **100% procedurally generated pixel art** — every sprite, stage, tile,
  card, logo, and the app icon come from one Python script
  ([`pixelgen.py`](pixelgen.py)). Re-theme the entire game by editing
  palettes and re-running it.

## How it plays

You command the White army. Standard chess until a capture is contested —
then both pieces enter a side-view arena. Fight stats scale with chess value
(`HP = 50 + 25×points`, pawns are scrappy underdogs, queens are monsters,
kings are 300 HP tanks). Blocking the correct side absorbs 80% of a hit,
perfect dodges negate everything and charge your super, and every action
drains stamina — a fully drained fighter is helpless and takes 1.5× damage.
Spam loses; reads win.

## Getting started

**Requirements:** Xcode 16+, iOS 17+ target. No account needed for offline
play; online play needs an Apple Developer account (see below).

1. Clone the repo and open `CombatChess.xcodeproj`. Xcode resolves the single
   package dependency ([ChessKitEngine](https://github.com/chesskit-app/chesskit-engine), MIT).
2. **Stockfish networks (one manual step):** download
   `nn-1111cefa1111.nnue` (~75 MB) and `nn-37f18f62d772.nnue` (~5 MB) from
   <https://tests.stockfishchess.org/nns> and drop both into
   `CombatChess/CombatChess/`. They're gitignored as large binary data.
   *Without them the app still runs* — the built-in Swift minimax engine
   takes over transparently.
3. Set your team under *Signing & Capabilities* and run.
4. **Online play (optional):** requires the Game Center capability on your
   App ID and an App Store Connect app record with Game Center enabled, plus
   sandbox Game Center accounts on test devices.

## Architecture

```
CombatChess/
├── Models/          Chess rules engine (ChessBoard), match state machine
│                    (MatchController: turns, cards, fights, king rule)
├── Engine/          Stockfish adapter (EngineManager) + native minimax
│                    fallback + AI card policies (ChessAI)
├── Fight/           SpriteKit fight scene: deterministic seeded sim,
│                    stamina system, multi-frame sprite animation
├── Net/             Game Center: auth/matchmaking (GameKitManager),
│                    turn-based bridge (OnlineMatchCoordinator), wire protocol
├── Views/           SwiftUI: landing, board, fight wrapper, history, settings
├── Persistence/     SwiftData match history
├── PixelAssets/     194 generated PNGs (do not hand-edit — see pixelgen.py)
└── Support/         Pixel rendering helpers, seeded RNG, haptics
docs/                Online multiplayer technical design
pixelgen.py          The entire art pipeline (Python 3 + Pillow)
```

Key design decisions worth knowing before you dig in: the fight simulation
routes all game-affecting randomness through a seeded `SplitMix64`
(deterministic replays / future lockstep netcode); `MatchState` is fully
`Codable` and is the single source of truth shipped in online turn data;
Stockfish strength comes from `UCI_Elo`/Skill Level with a hard `movetime`
cap so moves stay fast.

## The asset pipeline

Run `python3 pixelgen.py` from the repo root (needs `pip install pillow`) to
regenerate all 194 assets: 168 fighter sprites (6 pieces × 2 armies × 14
animation frames), 3 stages, board tiles, piece icons, action cards, pixel
logos, and the app icon. Palettes, poses, and body proportions are all data
at the top of the script — a full visual re-theme is an afternoon, not a
rewrite.

## Roadmap / where help is wanted

- **M3: live lockstep fights online** — the big one. Fixed-tick sim
  refactor + input-delay lockstep ([design](docs/ONLINE_MULTIPLAYER.md) §2).
- **Rules-engine test suite** — perft validation of `ChessBoard.legalMoves`.
- **Move-replay validation** of incoming online turn data (anti-tamper).
- **Sound design** — currently system sounds + haptics only.
- **Accessibility** — auto-resolve fight option, VoiceOver on the board.
- **Match list UI** for juggling multiple online games.

## Contributing

Issues and PRs welcome. Keep PRs focused (one system per PR), match the
existing code style (plain Swift, no additional dependencies without
discussion), and note that **all contributions are accepted under GPLv3**.
For gameplay-balance changes, include your reasoning — tuning constants live
at the top of `FightScene.swift` and in `Difficulty.swift` and are
deliberately easy to experiment with. Art contributions should modify
`pixelgen.py`, not the PNGs.

## License

Combat Chess is licensed under the **GNU General Public License v3** — see
[LICENSE](LICENSE). It bundles [Stockfish](https://stockfishchess.org)
(GPLv3, © the Stockfish developers) and uses
[ChessKitEngine](https://github.com/chesskit-app/chesskit-engine) (MIT).
The app displays these notices in *Settings → Open Source & Licenses*,
which also links back to this repository as the Corresponding Source.

You may sell builds of this software; you may not close its source. If you
ship a modified version, GPLv3 §5 requires prominent notice of your changes
and this same license.

## Maintainer release checklist (App Store)

Privacy manifest (`PrivacyInfo.xcprivacy`) and encryption-exemption flag are
in the project; iPhone-only targeting is set. Before each submission: sync
this repo with the shipped source (that's the GPL compliance), complete the
App Privacy questionnaire + privacy policy URL in App Store Connect, and run
the device QA pass (all fight triggers, force-quit resume, online matches
between two sandbox accounts).
