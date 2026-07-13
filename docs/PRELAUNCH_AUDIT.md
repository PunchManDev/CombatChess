# Combat Chess — Pre-Launch Audit (2026-07-12)

Scope: full read of all 23 Swift sources, project.pbxproj, entitlements, privacy
manifest, assets, docs, and Apple's current rules (cited inline). Findings are
ordered **Blockers → High risk → Nice-to-have**. File paths are relative to the
repo root; line numbers are from the audited revision.

---

## A. BLOCKERS — fix before submitting

### A1. Game Center turn-data decoding has no version tolerance, and v1.0 is *already* incompatible with the earlier TestFlight build

This is the single most dangerous issue in the codebase.

**The mechanism.** `MatchState` (Models/MatchState.swift:5–32) relies on
*synthesized* `Codable`. Swift's synthesized `init(from:)` **does not use inline
property defaults** — a missing key for any non-Optional property (`moveCount`,
`capturedByPlayer`, `repetitionCounts`, `fightLogs`, `fightSummaryVersion`)
throws `keyNotFound`. Only the Optionals (`pendingCaptureMove`,
`lastAppliedMove`, `lastFightSummary`) tolerate absence.

**The existing skew.** `fightSummaryVersion: Int = 0` (MatchState.swift:32) was
added in the post-TestFlight "fight recap" pass (along with `lastAppliedMove`
and `lastFightSummary`). Turn data written by the earlier TestFlight build has
no `fightSummaryVersion` key → **the current build cannot decode any in-flight
match last touched by the previous build.** The reverse direction is fine
(JSONDecoder ignores unknown keys), which makes the failure asymmetric and
confusing to debug.

**What happens on decode failure — both outcomes are catastrophic:**

1. `OnlineMatchCoordinator.init` (Net/OnlineMatchCoordinator.swift:44–53):
   `try?` fails → it silently substitutes a **fresh `MatchState`** (new board,
   medium difficulty). If it's the local player's turn, they see a reset board;
   their next move ships the fresh state via `endTurn`, **silently wiping the
   real game for both players.**
2. `process(match:data:)` (Net/OnlineMatchCoordinator.swift:142–144): `try?`
   fails → `return` with no error, no log for the decode itself → the match
   sits on "WAITING FOR THEIR MOVE…" **forever**, on the device whose turn it
   actually is.

There is no protocol version field anywhere in `TurnEnvelope`
(Net/GameKitManager.swift:195–198), so an old-build opponent cannot even be
detected, let alone told to update.

**Fix (before 1.0 ships, because 1.0 freezes the wire format):**
- Hand-write `init(from decoder:)` for `MatchState` using
  `decodeIfPresent(_:forKey:) ?? default` for every field added after the first
  networked build, and do the same for any future field forever.
- Add `let version: Int` to `TurnEnvelope`. On decode failure or
  `version > supported`, show an explicit "opponent is on a newer/older
  version" state instead of a fresh board; never construct a playable fresh
  `MatchState` from undecodable data for an existing match.
- Add a unit test that decodes a frozen JSON fixture of the v1.0 wire format;
  run it on every model change.

### A2. Bundle ID in the project is `com.punchmandev.combatchessgame1` — not the `com.punchmandev.combatchess` everyone believes

`PRODUCT_BUNDLE_IDENTIFIER = com.punchmandev.combatchessgame1`
(CombatChess.xcodeproj/project.pbxproj:271 and :306, Debug and Release).

Whichever of the two IDs the App Store Connect record actually uses, the
discrepancy must be reconciled before submission: Game Center turn-based
matchmaking, the GC entitlement, push-driven turn events, and TestFlight
history are all bound to the app record's bundle ID. If the ASC record is
`…combatchess` the archive won't attach to it; if the record is really
`…combatchessgame1`, the store listing/GC config people set up under the other
name doesn't apply. Related inconsistency: the **project-level** configs say
`DEVELOPMENT_TEAM = 958ZEX84P5` (pbxproj:164, :221) while the **target-level**
configs say `LZN3227TNV` (pbxproj:255, :290). The target wins at build time,
but confirm `LZN3227TNV` is the team that owns the ASC record, and clean up the
stale project-level value.

### A3. Privacy policy link is required *in the app*, not just in App Store Connect — and there is none

Guideline 5.1.1(i): "All apps must include a link to their privacy policy in
the App Store Connect metadata field **and within the app** in an easily
accessible manner"
(https://developer.apple.com/app-store/review/guidelines/#5.1.1).

`SettingsView`/`LicensesView` (Views/SettingsView.swift) has GPL text and a
source link but no privacy policy link. Also required in ASC before you can
submit at all: privacy policy URL, App Privacy questionnaire answers, age
rating questionnaire, support URL, category (category is already set in the
binary: `LSApplicationCategoryType = public.app-category.board-games`,
pbxproj:260).

**Fix:** host a one-paragraph policy (the GitHub repo works: "no data
collected; Game Center is operated by Apple — see Apple's Game Center privacy
disclosure"), put the URL in ASC, and add a `Link` row in Settings next to
"Open Source & Licenses".

- **App Privacy questionnaire:** "Data Not Collected" is defensible. Apple's
  own guidance says you are not responsible for disclosing data collected
  solely by Apple (Game Center data goes to Apple, not to you)
  (https://developer.apple.com/app-store/app-privacy-details/,
  https://www.apple.com/legal/privacy/data/en/game-center/). The app itself
  sends nothing off-device except GC turn payloads.
- **Age rating:** the fight minigame is punching with KO's — answer
  "Cartoon or Fantasy Violence: Mild/Infrequent" (expect a 9+ rating).
  Answering "None" while your screenshots show KO screens is an easy metadata
  rejection.

---

## B. HIGH RISK — likely to bite in review or week one

### B1. A failed `endTurn` permanently strands both players (error is print-only)

`OnlineMatchCoordinator.sendTurn` (Net/OnlineMatchCoordinator.swift:206–214):
`MatchController` has already flipped to `.waitingForOpponent` and cleared
local reminders **before** `endTurn` runs; the completion handler only does
`print(...)`. On any transient network failure the turn never reaches Game
Center: the local player sees "waiting", GC still thinks it's their turn, the
opponent is never notified. Same pattern in `endMatch`
(:234–246) and `resolveForfeitWin` (:177–185). By luck, reopening the match
re-ingests the last server state and effectively rolls the move back — but the
user just sees their move vanish with no explanation.

**Fix:** on `endTurn` error, revert `phase` to `.playerTurn`, restore the
pre-send state (keep a copy before mutating), and show an alert with retry.
This is exactly the class of "GameKit hang" this app has been bitten by before.

### B2. Presentation conflict between the two `fullScreenCover`s is still live

LandingView attaches the offline cover to the NavigationStack *content*
(Views/LandingView.swift:220–225) and the online cover to the NavigationStack
itself (:238–242) — the comment at :236 shows this was already fought once.
The residual bug: while the **offline** cover (or Apple's matchmaker/GC
sign-in sheet, presented via UIKit `topViewController()` —
Net/GameKitManager.swift:106, :241–249) is up, anything that sets
`activeCoordinator` — a turn event with `didBecomeActive`
(GameKitManager.swift:299–301) or a notification tap
(Net/NotificationManager.swift:223–228) — asks SwiftUI for a second
simultaneous presentation. SwiftUI drops or defers it unpredictably: user taps
"your move" banner mid-CPU-game → nothing happens.

**Fix:** route all match presentation through one source of truth (a single
`enum ActiveScreen { cpu(MatchController), online(OnlineMatchCoordinator) }`
driving one cover), and queue an incoming coordinator until the current cover
dismisses.

### B3. No validation of decoded network payloads → index-out-of-range crashes

`Board.squares` is `[Piece?]` (Models/ChessBoard.swift:6) and every consumer
hard-indexes 0..<64 (`kingSquare` :109–116, `evaluate`, `BoardView`,
`positionKey` :459–471). A truncated/corrupt/foreign turn payload that
*decodes* but has `squares.count != 64` crashes on first render or first move
generation. Turn data is remote input; treat it as untrusted.
**Fix:** after decoding a `TurnEnvelope`, validate `board.squares.count == 64`,
exactly one king per side, and card counts within 0...start values; reject to
the A1 error path otherwise.

### B4. A TestFlight user's saved CPU game silently dies on update (same Codable root cause as A1)

`MatchSnapshotStore.load()` is `try?` (Models/MatchState.swift:137–140). After
any model change, `hasSnapshot` is still true (file exists, :146–148) so the
landing screen shows "Resume Match", but tapping it just makes the button
disappear (Views/LandingView.swift:153–164). Not a crash — good — but a silent
data loss on every future update until A1's `decodeIfPresent` hardening is
done. Also delete the file when it fails to decode.

### B5. The NNUE files are one clean checkout away from silently vanishing from a release build

Verified present: `CombatChess/nn-1111cefa1111.nnue` (74.9 MB) and
`nn-37f18f62d772.nnue` (3.5 MB). But `.gitignore` excludes `*.nnue`, and the
target uses a `PBXFileSystemSynchronizedRootGroup` (pbxproj:17–23) that bundles
*whatever happens to be in the folder*. An archive from a fresh clone or CI
succeeds and ships, and `EngineManager.startIfNeeded`
(Engine/EngineManager.swift:78–82) silently flips to the native minimax — while
Settings still advertises "a Stockfish rating … up to 3190 (superhuman)"
(Views/SettingsView.swift:34) and the store copy says Stockfish 17. That's a
degraded product *and* a metadata-accuracy problem (Guideline 2.3 family —
https://developer.apple.com/app-store/review/guidelines/#2.3.1).
**Fix:** add a Run Script build phase for Release/archive builds that fails if
`Bundle` won't contain both `.nnue` files; sanity-check the .ipa size
(~85–90 MB) before every upload.

### B6. GPLv3 on the App Store — honest assessment: submission won't be blocked, but the tail risk is real and can't be engineered away

- Apple's review does **not** check code licenses; there is no guideline about
  GPL. Rejection at review time on GPL grounds is effectively unheard of.
- The historical removals (GNU Go 2010, VLC 2011) were **copyright-holder
  complaints**, after which Apple removed the apps rather than contest the
  claim that App Store Usage Rules conflict with the GPL
  (https://www.fsf.org/news/2010-05-app-store-compliance,
  https://www.fsf.org/blogs/licensing/vlc-enforcement).
- The FSF's position that App Store terms are GPL-incompatible has never been
  litigated. Meanwhile, GPL'd Stockfish ships inside many App Store apps
  (including lichess's open-source app) without incident, and the Stockfish
  team's enforcement energy has gone at *violators* (ChessBase — see
  https://fossa.com/blog/stockfish-vs-chessbase-gpl-v3/), not at compliant
  open-source apps.
- **Your posture is about as good as it gets:** whole app GPLv3, public repo,
  in-app §5d notices + full license text (`LicensesView`, gpl-3.0.txt bundled),
  source link, README documenting where the (gitignored) NNUE data comes from.
  Two nits: (a) the credits typo "Copyright ©Stockfish ."
  (Views/SettingsView.swift:73) — make it "Copyright © the Stockfish
  developers (see AUTHORS)"; (b) as the sole copyright holder of your own
  code you may optionally add a GPLv3 §7 "App Store additional permission" for
  *your* code — it cannot cover Stockfish, so it's symbolic, but it documents
  good faith.
- **Net:** ship it; the realistic risk is a future takedown demand, at which
  point compliance + dialogue with the Stockfish team is the remedy. Do not
  let anyone talk you into quietly relicensing — bundling Stockfish makes
  GPLv3 non-negotiable.

### B7. Reviewer experience of online play

The reviewer will tap "Online · Sign In" → GC sandbox → matchmaker. An
auto-match with no second player shows "ONLINE · FINDING OPPONENT…"
indefinitely (Views/GamesListView.swift:58–63). That's normal for async GC
games and usually fine, but reviewers do reject games whose headline features
can't be exercised (Guideline 2.1 completeness). **Fix:** App Review notes
should state: single-player is the complete core experience; multiplayer is
Apple Game Center turn-based (async) and requires a second account; include a
second sandbox account hint or a short video link.

### B8. "Online fights are vs a CPU proxy" — metadata honesty

Online, an accepted challenge is fought locally by the defender against a
CPU-driven proxy of the opponent's piece (Net/OnlineMatchCoordinator.swift:7,
docs/ONLINE_MULTIPLAYER.md §1); the attacker has no input into the fight. This
is a legitimate design (and the recap/notification wording is already
color-accurate), but the store description must not say or imply "fight your
friends in real time." Describe it as: async multiplayer chess; contested
captures are resolved in the arena by the defending player. Misrepresenting it
risks 2.3.1 (misleading) and — more likely — angry reviews from users who
figure it out. Longer term, an in-app one-liner on the online splash ("You
fight a proxy of RIVAL's piece") would defuse it entirely.

---

## C. NICE-TO-HAVE / MINOR (won't block, worth a pass)

1. **Display name** — no `CFBundleDisplayName`; home screen will show
   "CombatChess" (no space). Add `INFOPLIST_KEY_CFBundleDisplayName = "Combat
   Chess"` (pbxproj target configs).
2. **Build number** — `CURRENT_PROJECT_VERSION = 1` (pbxproj:254/289): bump for
   the next upload; ASC rejects duplicate build numbers per version.
3. **Hardcoded version string** — Settings shows "Version 1.0" literal
   (Views/SettingsView.swift:37); read `CFBundleShortVersionString` instead so
   it can't drift.
4. **Accessibility** — board squares are tap-gesture images with no
   `accessibilityLabel` (Views/MatchView.swift:361–375); fixed 9–10 pt
   monospaced microtext everywhere; no Dynamic Type. Not a rejection risk for a
   game, but VoiceOver users get nothing. Cheap win: label each square
   ("e4, white knight").
5. **Pin the engine package** — `chesskit-engine` is `upToNextMajorVersion`
   from 0.7.0 (pbxproj:339–346). In 0.x semver, minors may break API/behavior.
   `Package.resolved` exists and is inside the project — make sure it's
   committed, or pin `exactVersion` for the release branch.
6. **`GKLocalPlayer.authenticateHandler` reassigned on every landing-screen
   appear** (Views/LandingView.swift:229 → Net/GameKitManager.swift:67). Apple
   expects it set once at launch; move it to app init and keep only
   `refreshMatches()` in `onAppear`.
7. **`wantsToQuitMatch` not implemented** — quitting a match from the Game
   Center/matchmaker UI does nothing; only in-app Resign works
   (Net/GameKitManager.swift GKLocalPlayerListener extension). Implement
   `player(_:wantsToQuitMatch:)` → `participantQuitInTurn`/`OutOfTurn`.
8. **History pollution** — online matches are recorded into `MatchRecord` with
   `difficulty` "medium" and counted in the CPU win-rate stats
   (Views/MatchView.swift:307–328, Views/HistoryView.swift). Tag records
   offline/online.
9. **EngineManager continuation overwrite** — a second concurrent `bestMove`
   would orphan the first continuation forever (Engine/EngineManager.swift:59–66).
   Game flow currently serializes calls, but an abandoned controller plus a new
   match can race; resume any existing continuation (nil) before storing a new
   one.
10. **"Start Game" silently wipes the saved CPU game**
    (Views/LandingView.swift:132–134). Confirm if a snapshot exists.
11. **Badge clearing depends on notification permission** —
    `setBadgeCount(0)` fails if the user declined notifications
    (Net/NotificationManager.swift:124); the GC turn badge can then linger.
    The `GKGameCenterBadgingDisabled` Info.plist key (already noted in
    docs/NOTIFICATIONS.md) is the clean fix if it bothers testers.
12. **Board tap sound** — `Haptics.moveSound()` fires on *every* square tap,
    including empty deselects (Views/MatchView.swift:373). Cosmetic.
13. **Stockfish credits typo** — see B6(a).
14. **Draw-out-of-turn maps to `.lost`** in `endMatch`'s
    `participantQuitOutOfTurn` branch (Net/OnlineMatchCoordinator.swift:240–241).
    Likely unreachable today (draws are detected on the device whose turn it
    is), but wrong if flow ever changes.

---

## D. Verified-OK (so nobody re-litigates them)

- **Screenshots:** 1320×2868 RGB PNGs are the correct 6.9" spec
  (https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/).
  Ensure they show real gameplay — 2.3.3 requires screenshots "show the app in
  use," and these are script-generated; they must faithfully match the shipped
  UI (https://developer.apple.com/app-store/review/guidelines/#2.3.3).
- **Privacy manifest** (CombatChess/PrivacyInfo.xcprivacy): UserDefaults
  CA92.1 + file-timestamp C617.1, no tracking — matches actual API use
  (`UserDefaults` in Settings/Difficulty, file ops in MatchSnapshotStore).
- **Export compliance:** `ITSAppUsesNonExemptEncryption = NO` is correct — the
  app itself uses no encryption beyond Apple's OS TLS via GameKit.
- **Entitlements:** `com.apple.developer.game-center` present; turn-based GC
  needs no APNs entitlement of its own.
- **Player-ID hygiene:** `gamePlayerID` is used internally only; the UI shows
  `displayName`/`alias` — compliant with 4.5.5
  (https://developer.apple.com/app-store/review/guidelines/#4.5.5).
- **Orientation/device:** portrait-only, `TARGETED_DEVICE_FAMILY = 1`,
  generated launch screen — all fine for an iPhone-only game.
- **Crash-grep results:** only 2 `fatalError`s, both in unreachable
  `init(coder:)` (Fight/FightScene.swift:32, :205). The
  `frames["idle_a"]!`-style unwraps (FightScene:25–62) are safe because
  `pixelTexture`/`SKTexture(imageNamed:)` always returns a texture (missing
  art renders as placeholder, no crash), and the dictionary is populated for
  every key used. `capturedSquare(of:)!` at MatchController:390/:584 is
  guarded by a non-nil victim; `checkers.max(...)!` at :304 is guarded by
  `!checkers.isEmpty`. No `try!`, no `as!`.
- **Minimum functionality (4.2):** not a concern — this is a complete,
  original game.

---

## E. Pre-submission checklist (App Store Connect)

- [ ] Resolve bundle-ID question (A2); confirm team `LZN3227TNV` owns the record
- [ ] Privacy policy URL in ASC **and** linked in Settings (A3)
- [ ] App Privacy questionnaire: Data Not Collected (verify nothing changed)
- [ ] Age rating questionnaire: mild cartoon/fantasy violence (expect 9+)
- [ ] Support URL (GitHub issues page is acceptable)
- [ ] Game Center enabled on the app record & version
- [ ] Bump `CURRENT_PROJECT_VERSION`; archive from the machine that has the
      `.nnue` files; verify .ipa is ~85+ MB before upload (B5)
- [ ] App Review notes: async GC multiplayer explanation + second-account hint (B7)
- [ ] Description copy reviewed against B8 (no "real-time PvP fights" claims)

## F. Overall read

Single-player is genuinely solid: full FIDE rules engine, safe unwrap
discipline, a graceful Stockfish→minimax fallback, and resilient offline
snapshotting. The launch risk is concentrated in **online multiplayer's total
lack of version/error tolerance** (A1, B1, B3): the wire format freezes the
moment 1.0 ships, it is already incompatible with the previous TestFlight
build, and every failure mode is silent. Fix A1–A3 before submission; B1–B3
before you have real concurrent users on two versions — i.e., effectively also
before 1.0.

---

## Follow-up: stability audit & fixes (post-audit pass)

A second pass hunting exceptions/crash classes across the whole codebase.

**Clean bill of health on the classic crashers.** No `try!`, no force-casts
(`as!`), no reachable `fatalError` (only the unreachable `init(coder:)` stubs),
and no unguarded division (HistoryView's `winRate`/`streak` both guard the
empty case). The remaining `!` force-unwraps were each verified safe:
`FightScene`'s `frames["idle_a"]!` (the dictionary is populated from a fixed
key list, and `SKTexture(imageNamed:)` never returns nil), `checkers.max(by:)!`
(guarded by a preceding `!checkers.isEmpty`), and `capturedSquare(of: move)!`
(only reached when a captured piece is already known to exist).

**FIXED — leaked continuation could hang the AI forever.**
`EngineManager.bestMove` is an `actor` method that suspends on
`withCheckedContinuation`. Actors are *reentrant across suspension points*, so a
second `bestMove` call could enter while the first awaited and overwrite
`bestMoveContinuation` — leaking it. A leaked `CheckedContinuation` never
resumes, so that AI turn would hang on "thinking" permanently. Now any in-flight
continuation is retired (resumed with `nil`, so the caller falls back to the
native engine) before a new one is stored.

**FIXED — double AI turn could play two moves.** `runAITurn()` had no
re-entrancy guard; two invocations would each spawn a detached search and each
apply a move. Added `aiTurnInFlight`.

**FIXED — a stale engine move could corrupt the board.** `aiMoveComputed` applied
whatever the engine returned. If the position changed while the engine was
thinking (resign, remote match end, leaving the match), that move was applied to
a different board. It now (a) drops the result unless the phase/turn still
expect it, and (b) validates the move is legal on the *current* board, falling
back to a fresh evaluation instead of corrupting state. A previous version of
this guard incorrectly routed a stale move into `finishGame(win)` — that would
have handed the player an undeserved win; the nil-move and stale-move cases are
now distinct.
