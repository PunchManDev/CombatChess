# Combat Chess — Invite-to-Install Flow

Scenario: Player A invites Player B to a Combat Chess `GKTurnBasedMatch`, but
B **does not have the app installed**. This doc covers what Apple's stack
actually does today, the UX we ship, what we implemented, and what must be
configured manually.

## 1. How GameKit actually behaves (verified against Apple docs)

**How the invite travels.** The system matchmaker
(`GKTurnBasedMatchmakerViewController`) lets the sender invite Game Center
friends, contacts, iMessage groups, nearby players, or a phone number/email.
Invites are delivered by Game Center itself — as a Game Center push
notification if the game is installed, and through the Messages thread for
contact/iMessage-group invites. Sources:
[Game Center overview](https://developer.apple.com/game-center/) ("players
can invite Game Center friends, contacts, iMessage groups, and nearby
players"), [WWDC21 — What's new in Game Center](https://developer.apple.com/videos/play/wwdc2021/10066/)
(Messages-based invite flow, suggestions shelf).

**Timing catch.** GameKit does **not** send any invitation until the match
creator takes the first turn. Until the opponent joins, the sender sees a
placeholder name/avatar. Source:
[Creating turn-based games](https://developer.apple.com/documentation/gamekit/creating-turn-based-games)
— "GameKit doesn't send invitations to the match until the participant who
starts the match takes the first turn."

**The not-installed case.** The invite the recipient sees (Messages bubble /
Game Center notification) is system UI we don't control. If the game isn't
installed, tapping it opens the **App Store product page** for
`com.punchmandev.combatchess` instead of launching the game. Apple handles
this redirect; there is no API hook, no custom copy, and no way to attach
our own onboarding to it. (Behavior introduced with the iOS 10 move of
invites into Messages and unchanged since; confirmed by Apple's Game Center
materials above.)

**The crucial property: no deferred deep link is needed.** A
`GKTurnBasedMatch` lives **server-side on the invitee's Game Center
account**, with the invitee as a participant whose status is `.invited`.
Nothing about the pending match is carried by the tapped link — so nothing
is lost when the link detours through the App Store. After install, any of
these paths recovers the match:

1. Player taps the invite again (Messages bubble or Game Center
   notification) → the game launches → GameKit calls
   [`player(_:receivedTurnEventFor:didBecomeActive:)`](https://developer.apple.com/documentation/gamekit/gkturnbasedeventlistener/player(_:receivedturneventfor:didbecomeactive:))
   with `didBecomeActive == true`. Its documented triggers explicitly
   include "The player accepts an invitation from another participant."
2. Player just opens the game → after authentication we sweep
   `GKTurnBasedMatch.loadMatches` for participants with status `.invited`
   and surface the challenge ourselves, accepting programmatically via
   [`acceptInvite(completionHandler:)`](https://developer.apple.com/documentation/gamekit/gkturnbasedmatch/acceptinvite(completionhandler:))
   ("use this method to programmatically accept an invitation on behalf of
   the local player") /
   [`declineInvite(completionHandler:)`](https://developer.apple.com/documentation/gamekit/gkturnbasedmatch/declineinvite(completionhandler:)).
3. Player opens the system matchmaker sheet → the invited match is listed
   there too.

**What `GKInvite` / `GKInviteEventListener` are (and aren't).**
[`GKInvite`](https://developer.apple.com/documentation/gamekit/gkinvite) and
[`GKInviteEventListener.player(_:didAccept:)`](https://developer.apple.com/documentation/gamekit/gkinviteeventlistener)
belong to **real-time** (`GKMatch`) matchmaking — Apple's docs group them
under "Real-time games", and the invitee-side pattern is
`GKMatchmakerViewController(invite:)` (WWDC21 session code). Turn-based
invite acceptance never arrives there; it arrives via
`receivedTurnEventFor`. We still implement `player(_:didAccept:)` as a
logged no-op because `GKLocalPlayerListener` inherits the protocol and M2+
may add real-time flows.

**Universal Links / deferred deep linking.** Apple provides **no**
first-party deferred deep linking: a Universal Link tapped before install
does not survive the App Store trip (App Clips are the only pre-install
experience, and games of this size aren't App Clip material). Third-party
SDKs (Branch et al.) fake it with fingerprinting/pasteboard tricks — not
worth the privacy surface here, because Game Center already persists the
one thing we care about (the match) on the account. Universal Links remain
useful only for a *marketing* landing page (§4); they are not required for
the invite flow. Setup reference:
[Supporting associated domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains).

**Turn notifications after joining** work the same way: notification tap →
game launch → `receivedTurnEventFor` with `didBecomeActive == true`; a
waiting player can nudge via `sendReminder` (max one per 10 minutes).
Source: [Sending messages to players in turn-based games](https://developer.apple.com/documentation/gamekit/sending-messages-to-players-in-turn-based-games).

**iOS 26 note.** The Apple Games app now surfaces Game Center invites,
challenges, and friend activity, and GameKit gained `GKGameActivity`
(shareable `partyURL` for real-time party joining). None of it changes the
turn-based invite path above, but the Games app gives invites more visible
placement, and "Friends Are Playing" on the App Store/Games app is a free
discovery channel for exactly this scenario.

## 2. Recommended UX flow (what we ship)

### Sender (has the app)
1. Taps **Online · Invite a Friend** → system matchmaker → picks a friend,
   contact, or iMessage group.
2. **Makes their first chess move immediately.** This is what actually
   fires the invite (see §1 timing catch). The match UI already opens right
   after matchmaking, so the natural "make a move" flow doubles as the
   send-trigger — no extra UI needed, but the design rule is: never let the
   sender park on a "waiting" screen before move one.
3. While the opponent slot is pending, Game Center shows a placeholder
   opponent — `OnlineMatchCoordinator` already renders "OPPONENT" until the
   join.

### Receiver (no app installed)
1. Gets the invite in Messages (or a Game Center notification on devices
   where they're signed in): *"A wants to play Combat Chess — 'your pieces
   won't capture themselves.'"*
2. Taps it → **App Store product page** (system behavior, not ours).
3. Installs, opens the app.
4. First launch: `LandingView.onAppear` runs `authenticate()`; Game Center
   sign-in is usually silent (device-level Apple Account).
5. On auth, `GameKitManager.refreshPendingInvites()` sweeps
   `loadMatches()` and finds the invited match. The landing screen shows a
   gold, filled **"⚔ Challenge from <NAME>"** button above the online
   button — the single most prominent action on screen.
6. Tap → `acceptInvite` → `OnlineMatchCoordinator` opens the board. From
   invite to first move: install + two taps.
7. Alternative: if they tap the Messages invite again after installing,
   GameKit launches the app and path (1) of §1 delivers the match with
   `didBecomeActive == true` — the existing turn-event handler opens it
   directly, skipping the landing button.

### Honest limitations
- The App Store hop is unbrandable and unmeasurable from our side; we can't
  inject "B invited you" into the product page.
- If the sender never makes move one, no invite ever goes out — the most
  common "my friend got nothing" bug report.
- If the invitee's device isn't signed into Game Center, they get a
  system sign-in sheet before anything works; declining it dead-ends online
  play (we show "Online · Sign In" as the fallback).
- Invited matches that sit unaccepted are subject to Game Center's normal
  participant timeout handling; the sender's match eventually auto-matches
  or stalls. Reminders (`sendReminder`) only target *current* participants,
  so we cannot nudge a not-yet-joined invitee.
- TestFlight caveat: both sandbox/TestFlight and App Store builds share
  Game Center, but an invitee without the app is sent to the **App Store**
  page, never to TestFlight — invite-to-install testing needs the store
  build.

## 3. Implementation (this change)

`CombatChess/Net/GameKitManager.swift`
- `pendingInvites: [GKTurnBasedMatch]` observable state.
- `refreshPendingInvites()` — `GKTurnBasedMatch.loadMatches`, filtered to
  open/matching matches where the local participant's status is `.invited`.
  Called on successful auth and from `LandingView.onAppear`.
- `acceptInvite(_:)` / `declineInvite(_:)` — programmatic accept/decline;
  accept opens an `OnlineMatchCoordinator` (same path as turn events).
- `presentMatchmaker(recipients:)` — optional pre-filled invitees; used by
  the new `player(_:didRequestMatchWithOtherPlayers:)` handler so "play
  with this friend" launched from Game Center UI lands in our matchmaker.
- `player(_:didAccept:)` (`GKInviteEventListener`) — logged no-op with the
  rationale in §1; real-time only.
- `receivedTurnEventFor` now prunes `pendingInvites` for the delivered
  match (covers system-UI accepts).
- Shared `GameKitManager.inviteMessage` constant.

`CombatChess/Views/LandingView.swift`
- `import GameKit`, "⚔ Challenge from <NAME>" gold button bound to
  `pendingInvites.first`, `inviterName(_:)` helper (participant 0 is the
  creator, mirroring `OnlineMatchCoordinator` color assignment), and an
  invite re-sweep in `onAppear`.

No entitlement, Info.plist, or project-file changes were needed — the flow
is pure GameKit and the `com.apple.developer.game-center` entitlement is
already present in `CombatChess/CombatChess.entitlements`.

## 4. Manual configuration checklist (developer)

Required (most already done for TestFlight; verify):
1. **App Store Connect → app record → Services → Game Center**: Game
   Center must be enabled for the app record *and* activated for the
   current app version's page. Without this, invites don't deliver in
   production even though sandbox works.
2. **Xcode → target → Signing & Capabilities**: Game Center capability
   present (it is — entitlement already in the project).
3. **Ship to the App Store.** The invite → App Store redirect targets the
   public product page; while the app is TestFlight-only, invited
   non-testers hit a dead product page. The flow only fully works once the
   app is live.
4. Test matrix (two Game Center accounts): (a) invite with app installed —
   notification → `receivedTurnEventFor`; (b) invite, delete app,
   reinstall — landing-screen challenge button appears after auth; (c)
   accept via the matchmaker sheet instead — pending button disappears
   (turn-event prune).

Optional, later (marketing layer — not needed for the invite flow):
- **Universal Link landing page**: host
  `https://combatchess.punchmandev.com` with a "Get Combat Chess" page that
  redirects to the App Store; serve
  `/.well-known/apple-app-site-association` with
  `{"applinks":{"details":[{"appIDs":["<TEAMID>.com.punchmandev.combatchess"],"components":[{"/":"/play*"}]}]}}`,
  add the `applinks:combatchess.punchmandev.com` Associated Domains
  entitlement, and handle `onOpenURL` in `CombatChessApp`. Gives shareable
  self-branded links ("beat my king fight score"), but tapped-before-install
  links still won't carry context through the store — by design, that's
  what Game Center already covers.
- **iOS 26 Games app**: adopt challenges/activities (`GKGameActivity`) for
  additional invite surfaces once M4 polish lands.

## 5. Doc sources

- https://developer.apple.com/documentation/gamekit/creating-turn-based-games
- https://developer.apple.com/documentation/gamekit/gkturnbasedeventlistener/player(_:receivedturneventfor:didbecomeactive:)
- https://developer.apple.com/documentation/gamekit/gkturnbasedmatch/acceptinvite(completionhandler:)
- https://developer.apple.com/documentation/gamekit/gkturnbasedmatch/declineinvite(completionhandler:)
- https://developer.apple.com/documentation/gamekit/gkinvite
- https://developer.apple.com/documentation/gamekit/gkinviteeventlistener
- https://developer.apple.com/documentation/gamekit/sending-messages-to-players-in-turn-based-games
- https://developer.apple.com/game-center/
- https://developer.apple.com/videos/play/wwdc2021/10066/
- https://developer.apple.com/documentation/xcode/supporting-associated-domains
