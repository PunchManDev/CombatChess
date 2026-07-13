# Combat Chess — Player Notifications

## Clearing notifications on re-entry

Every time the app becomes active (`scenePhase == .active` in
`CombatChessApp`), `NotificationManager.clearAllDelivered()` runs:
`removeAllDeliveredNotifications()` wipes stale banners from Notification
Center / the Lock Screen, and `setBadgeCount(0)` clears the app-icon badge
(Game Center badges the icon for pending turns, and it does not clear itself).

Only **delivered** notifications are removed. **Pending** ones — the scheduled
daily inactivity reminders leading up to the 4-day forfeit — deliberately
survive, so a player who opens the app but still doesn't move keeps getting
reminded. If icon badging ever feels noisy, the `GKGameCenterBadgingDisabled`
Info.plist key turns Game Center's badging off entirely.



## Abandonment: 4-day auto-forfeit + daily reminders

An online player who does not move within **4 days** forfeits; the opponent
wins by default. During that window the waiting player gets **one reminder
per day** telling them a move is pending.

**How the forfeit is enforced (serverless).** Every `endTurn` now passes
`turnTimeout: OnlineMatchCoordinator.forfeitTimeout` (4 days), so Game Center
puts the current participant on a server-side clock. When the clock expires,
Game Center marks that participant `.done` and hands the turn to the opponent.
The opponent's device sees a non-local participant with `status == .done`
while the match is still `.open`, and — as the current participant — calls
`endMatchInTurn` declaring itself the winner and the abandoner `.quit`
(`resolveForfeitWin()`). The abandoner receives the standard match-ended
event and records a loss. No server, no scheduled jobs.

**How the daily reminders work.** When the turn lands on the local player,
the coordinator schedules up to three local notifications at `deadline − 3d`,
`− 2d`, `− 1d` ("3 / 2 / 1 day(s) left … or forfeit"), anchored to the real
Game Center `currentParticipant.timeoutDate`. Because they're anchored to the
true deadline (not "now"), the countdown stays accurate no matter when the
player last opened the app; rescheduling on each view simply refreshes them.
They're cancelled the moment the player moves, the match ends, or the turn
passes away. These fire **locally on the waiting player's own device**, so
they're reliable even offline — the one caveat below.

**Honest limitation.** Local reminders can only be *scheduled* while the app
runs, so the day-1/2/3 reminders require the player to have opened the app at
least once after the opponent's move (the initial "your move" push — delivered
by Game Center server-side — is what brings them in). A fully uninstalled or
never-opened app can't schedule local reminders; only a real APNs backend
could push daily to such a device, which remains out of scope. Game Center
also emits its own timeout-approaching reminders as a server-side backup.



Goal: a player who is *not* in the app learns that their opponent acted —
moved, captured, forced a challenge decision, resolved a fight — so they come
back and take their turn. Combat Chess has **no backend server**, so the
design leans entirely on what Game Center delivers for free, plus
`UNUserNotificationCenter` for the narrow cases the app itself can cover.

## 1. What GameKit gives us for free (verified against Apple docs)

**Game Center sends the turn push itself, server-side.** When the current
participant calls `endTurn(withNextParticipants:turnTimeout:match:)`,
`endMatchInTurn(withMatch:)`, or forfeits, Game Center notifies the other
participants — no APNs certificates, no `aps-environment` entitlement, no
remote-notification background mode, and no server of ours. The existing
`com.apple.developer.game-center` entitlement is all it takes.

- <https://developer.apple.com/documentation/gamekit/gkturnbasedmatch/endturn(withnextparticipants:turntimeout:match:completionhandler:)> —
  "Passes the turn from the current participant to the next participant. …
  To receive turn-based events that this method generates, register a
  listener…"
- <https://developer.apple.com/documentation/gamekit/sending-messages-to-players-in-turn-based-games> —
  "You can also send a notification to other participants when they're not
  running your game. … If the game isn't running or is in the background,
  the message you provide appears immediately at the top of the screen as a
  notification."

**The banner text is settable per turn.** `GKTurnBasedMatch.message` is a
read-write `String?`: "A message from the current participant to all other
participants when you end a turn, forfeit a match, or end a match. Set this
property only when the local player is the current participant and before
you invoke a method that generates a turn-based event."
(<https://developer.apple.com/documentation/gamekit/gkturnbasedmatch/message>)
Apple's own sample is exactly our pattern:

```swift
match.message = "We're all counting on you!"
try await match.endTurn(withNextParticipants: nextParticipants,
                        turnTimeout: GKTurnTimeoutDefault, match: gameData)
```

If the recipient's app is foregrounded instead, no banner appears; the text
is readable from the match object in
`player(_:receivedTurnEventFor:didBecomeActive:)`.

**Localized variant.** `setLocalizableMessageWithKey(_:arguments:)` resolves
a key against the *receiver's* `Localizable.strings`
(<https://developer.apple.com/documentation/gamekit/gkturnbasedmatch/setlocalizablemessagewithkey(_:arguments:)>).
Combat Chess ships English-only UI strings and has no `.strings` files, so
we use plain `message`. If the app localizes later, swap `turnMessage(…)` to
emit keys + arguments and add them to `Localizable.strings`.

**Reminders.** `sendReminder(to:localizableMessageKey:arguments:completionHandler:)`
lets the *waiting* player poke the current one ("hurry up"); rate-limited to
one per 10 minutes (`GKServerTurnBasedMaxSessionOtherError` beyond that) and
only shown when the recipient's game isn't running. Not wired up yet — a
natural follow-up as a "nudge" button on the waiting screen.

**Tapping the banner** launches/foregrounds the game and fires
`player(_:receivedTurnEventFor:didBecomeActive: true)`, which
`GameKitManager` already routes into an `OnlineMatchCoordinator`.

## 2. The honest serverless boundary

| Scenario | Covered? | By what |
|---|---|---|
| Opponent ends their turn; our app is killed or backgrounded | ✅ | Game Center's own push, with our per-turn `message` text |
| Opponent's move ends the match (checkmate, resign) | ✅ | Same mechanism via `endMatchInTurn` / forfeit, with our result text |
| Turn event reaches the app while it's background-but-running | ✅ (belt-and-braces) | GC banner, plus our deduped local `UNNotificationRequest` fallback |
| App foregrounded when the turn arrives | ✅ | In-app UI (board animates, phase flips) — no banner wanted |
| Turn-timeout warnings, "3 days left to move" schedules | ⚠️ partial | Game Center handles timeout *passing* server-side; we could schedule local time-based reminders, but they can't know about remote state changes |
| Arbitrary pushes for remote events with the app not running (e.g. "opponent is typing", marketing, re-engagement) | ❌ | Requires APNs + a server. Local notifications cannot fire in response to a remote event the app never received. Out of scope by design. |
| Custom notification sound/artwork on the GC turn push | ❌ | The banner is composed by the system/Game Center; only the text is ours |

The one structural limitation to be honest about: **if iOS has terminated
the app, only Game Center's push reaches the player.** Its delivery is
subject to the user's notification settings for the app/Game Center — which
is why we request notification authorization, and why the invite-to-install
sweep (docs/INVITE_FLOW.md) remains the recovery path when a push was missed.

## 3. Implementation

### Message composition — `OnlineMatchCoordinator`

`MatchController.onTurnEnded` now passes a `TurnNotice` (defined in
`Models/MatchController.swift`) describing what the local player just did:

- `.moved` — plain move / castle / promotion,
- `.captured(PieceType)` — opponent's piece taken outright,
- `.challenged(PieceType)` — capture awaiting the opponent's
  challenge-or-concede decision (the §3 pending-capture flow).

Fight outcomes are *not* in the notice: the coordinator detects them from
`MatchState.fightSummaryVersion` advancing past `lastNotifiedFightVersion`
(a coordinator-local high-water mark, also raised whenever a version arrives
*from* the opponent so their own fights are never echoed back at them).

`turnMessage(for:notice:)` then produces the opponent-facing line, e.g. with
sender alias ALEX (`GKLocalPlayer.local.alias`; `displayName` can render as
"Me"):

| Event | Banner text |
|---|---|
| Challengeable capture attempt | "ALEX is attacking your queen — challenge the capture or let it stand!" |
| Outright capture | "ALEX captured your rook! Your move." / "… — check!" |
| Plain move | "ALEX moved. Your turn." / "ALEX moved — check!" |
| Fight (opponent attacked, local defender fought) | "Your knight won the fight and took ALEX's rook!" / "ALEX's rook fought off your knight!" |
| King's last stand survived | "ALEX's king survived his last stand — your bishop is slain!" |
| Match over | "ALEX won the match!" / "You won the match against ALEX!" / draw line |

The text is assigned to `match.message` immediately before `endTurn` /
`endMatchInTurn` / `participantQuitOutOfTurn`, per the doc'd contract.

### `Net/NotificationManager.swift` (new)

`@Observable final class NotificationManager: NSObject`, `.shared`
singleton, main-thread dispatch, `"CombatChess online: …"` diagnostics —
same shape as `GameKitManager`. Responsibilities:

1. **Authorization** — `requestAuthorizationIfNeeded()` asks for
   `[.alert, .sound, .badge]` the first time an online match coordinator is
   created (the moment notifications visibly matter to the player), only
   while status is `.notDetermined`.
2. **Background fallback banner** — `postTurnEventFallback(for:)` posts a
   local notification when a turn event reaches the app while
   `UIApplication.shared.applicationState == .background` (called from
   `GameKitManager.player(_:receivedTurnEventFor:didBecomeActive:)`). Game
   Center's push normally covers this case too, so the request identifier is
   the stable `"turn-<matchID>"`: a repeat replaces the previous banner
   instead of stacking, and `clearDelivered(forMatchID:)` removes it as soon
   as any non-background event for the match arrives. Body text prefers the
   incoming `match.message`.
3. **Delegate** — `UNUserNotificationCenterDelegate`, installed in
   `CombatChessApp.init()` so cold-start taps route correctly.
   `willPresent` suppresses banners for the match already on screen;
   `didReceive` loads the match via
   `GKTurnBasedMatch.load(withID:withCompletionHandler:)` and opens/refreshes
   its coordinator.

### Files touched

- `CombatChess/Net/NotificationManager.swift` — new.
- `CombatChess/Net/OnlineMatchCoordinator.swift` — per-turn `message`
  composition; fight-version high-water mark; authorization trigger.
- `CombatChess/Net/GameKitManager.swift` — background fallback / banner
  cleanup in the turn-event listener.
- `CombatChess/Models/MatchController.swift` — `TurnNotice` +
  `onTurnEnded` now `(MatchState, TurnNotice) -> Void`.
- `CombatChess/CombatChessApp.swift` — delegate installation at launch.

The project uses Xcode buildable folders (`PBXFileSystemSynchronizedRootGroup`),
so the new file joins the target automatically — no pbxproj edit.

## 4. Manual steps (Xcode / App Store Connect)

Nothing new is strictly required — worth verifying:

1. **Xcode**: Game Center capability is already on
   (`CombatChess.entitlements`). Do **not** add Push Notifications or the
   remote-notification background mode; Game Center's turn push does not use
   the app's APNs pipeline.
2. **App Store Connect**: Game Center must be enabled for the app record
   (already required for multiplayer). No further notification setup exists
   there.
3. **Device testing**: sandbox Game Center pushes require two devices with
   distinct Apple IDs; make sure Settings → Notifications → Combat Chess is
   allowed, and Settings → Game Center is signed in. Turn pushes do not
   appear in the simulator reliably — test on hardware.
4. **Optional Info.plist key**: `GKGameCenterBadgingDisabled` (Boolean)
   suppresses Game Center's automatic icon badging for pending turns if the
   badge ever feels noisy; we currently leave badging on.

## 5. Future work

- "Nudge" button while waiting, via `sendReminder(to:…)` (10-minute rate
  limit) — the serverless answer to "my opponent forgot the match exists".
- Localize banner text via `setLocalizableMessageWithKey(_:arguments:)`
  once the app grows `Localizable.strings`.
- M3 real-time fights: `GKMatch` sessions have no offline notification
  story; the turn-based fallback path (CPU proxy) already keeps the
  notification flow above intact.
