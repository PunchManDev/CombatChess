# App Store Connect — Promotional Text (max 170 chars)

Character counts verified by script. All entries ≤170.

## Recommended (149 chars)

> Chess where captures fight back. Spend a card, drop into a real-time pixel brawl, and keep the square. Even checkmate ends in your king's last stand.

Leads with the one-sentence hook, names the concrete loop (card → brawl → square),
and lands the game's most surprising twist (checkmate isn't final) — all in the
first two lines a browser actually reads.

## Alternates

| # | Angle | Chars | Text |
|---|-------|------:|------|
| 1 | Hook-first | 146 | No piece goes quietly. Contest any capture in a retro arcade brawl — punch, block, dodge. The winner keeps the square. The loser leaves the board. |
| 2 | Mechanic-first (persistent damage) | 153 | Full chess, real fights. Spend an Action Card to contest a capture in a pixel brawl. Damage sticks for the whole match — wound the queen, hunt her later. |
| 3 | Checkmate-twist | 148 | Checkmate isn't the end. Your king gets one final fight to break the mate — 300 HP of last-stand fury. Chess where every capture can become a brawl. |
| 4 | Punchy/short | 145 | It's chess. With fists. Contest captures in real-time pixel brawls — winner keeps the square, and checkmate is just the start of the final fight. |
| 5 | Multiplayer | 154 | Challenge friends over Game Center in chess where captures become pixel brawls. Winner keeps the square — and every checkmate ends in a king's last stand. |
| 6 | Underdog fantasy | 154 | A pawn can beat a queen — if you can outfight her. Chess where contested captures drop into retro pixel brawls and checkmate triggers one last king fight. |

## Notes

- "Street Fighter-style" is deliberately avoided (third-party trademark in
  App Store marketing copy); "retro arcade brawl" / "pixel brawl" carries the
  same feel safely.
- No pricing, rankings, urgency, or platform mentions, per Apple marketing
  guidelines. No emoji — the copy is punchier without one.
- Promotional Text can be swapped without a new binary: rotate to alternate
  #5 when pushing online play, #3 for a "checkmate twist" seasonal refresh.

---

# App Store Connect — Description (max 4,000 chars)

Plain text — no markdown renders on the App Store, so structure comes from
ALL-CAPS headers, line breaks, and • bullets. **3,377 characters** (of 4,000),
verified by script. Paste everything between the fences exactly.

```
It's chess. With fists.

Combat Chess is real, full-rules chess — until a capture is contested. Then both pieces drop into a real-time retro pixel brawl, and the winner keeps the square. No piece goes quietly. Not even the king.

ACTION CARDS: FIGHT FOR THE SQUARE
You start every match with 3 Action Cards. When your piece is captured, spend one to force a fight instead of just losing it. Win the brawl and the capture is repelled — your piece holds the square and the attacker is removed. Cards are spent win or lose and never refill mid-match, so card management is a whole extra layer of strategy. Run dry, and captures land like ordinary chess.

FIGHTS THAT MATTER
• Fighting power scales with chess value: pawns brawl at 75 HP, knights and bishops at 125, rooks at 175, queens at a monstrous 275, kings at 300.
• Damage persists for the ENTIRE match. Wound the queen now, hunt her down later — a health bar follows every piece that has fought.
• A pawn can topple a queen. It just takes near-flawless play.

SIX-BUTTON ARCADE COMBAT
• Left punch (fast jab) and right punch (slow, heavy cross).
• Side-matched blocking — read the tell and guard the correct side to absorb 80% of the hit.
• Timed dodges — perfect timing negates all damage and charges your meter.
• A stamina system that punishes button-mashing. Burn out and you're exhausted: unable to act and taking 1.5x damage.
• Land perfect dodges to unlock the SUPER — a single power shot worth 2.5x a heavy punch.
Spam loses. Reads win.

THE KING NEVER FALLS QUIETLY
• In check, you can move out of danger — or spend a card to send your king to fight the checking piece directly.
• Checkmate isn't automatically the end. It triggers a mandatory final fight: your king duels the mating piece at 300 HP, no card needed. Win the last stand and the mate is broken. This cuts both ways — to beat you, your opponent must finish the job in the ring.

A REAL CHESS ENGINE UNDERNEATH
• Complete standard chess: castling, en passant, promotion, check, checkmate, and every standard draw rule.
• Powered by the Stockfish engine, tunable from 600 to 3190 Elo — friendly beginner to superhuman, with a strength slider for every difficulty in Settings.
• Single-player works fully offline. Sound and haptics are yours to toggle.

CHALLENGE FRIENDS ONLINE
• Turn-based multiplayer through Game Center: invite friends, run several matches at once, and take your time.
• Get notified when an opponent moves, captures, or starts a fight — with daily reminders before the 4-day forfeit window closes a stalled match.
• Built for turn-based play: when you contest a capture, the fight resolves instantly on your own device against a computer-controlled version of your opponent's piece — fighting with its true HP and power, including damage it already carries. No waiting around, and your opponent sees a full recap on their turn.

EVERY MATCH ON RECORD
• Match history with wins, losses, draws, win rate, streaks, per-difficulty records, fight stats, and your biggest upset.

OPEN AND HONEST
Combat Chess is open source under the GPL v3 — the entire codebase is public, so every claim here can be verified. No ads. No tracking. No analytics. No accounts. Your games, stats, and settings never leave your device unless you choose to play online through Apple's Game Center.

Now get out there and make your pieces earn their squares.
```

## Notes

- Count verified by script (extract the fenced block, strip surrounding
  newlines, `len()`): 3,377 chars. Re-verify after any edit.
- Hook is the first three lines (pre-fold): concept, twist, stakes.
- Online fights framed positively ("Built for turn-based play") while stating
  plainly that the opponent's piece is computer-controlled — accurate per
  RulebookView "How Online Fights Work" and safe under guideline 2.3.1.
- All numbers cross-checked: 3 cards (SettingsView), HP 75/125/175/275/300
  (RulebookView), 80% block / 1.5x exhaustion / 2.5x super (RulebookView),
  Elo 600–3190 (SettingsView footer, README), 4-day forfeit + daily reminders
  (NOTIFICATIONS.md), stats fields (HistoryView).
- No trademarks, pricing, urgency, rankings, or platform mentions.
