import SwiftUI

/// The Combat Chess rulebook — explains every mechanic that sets the game
/// apart from ordinary chess. Reached from the ❓ button on the start menu.
struct RulebookView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Arcade.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header

                    section("♟️ IT'S CHESS — WITH FISTS", color: Arcade.gold) {
                        para("Combat Chess plays by full standard chess rules: castling, en passant, promotion, check, checkmate, and the usual draws. You command the White army against a friend online or the Stockfish-powered computer.")
                        para("The twist: no capture is guaranteed. When a piece is taken, the defender can force the two pieces into a real-time fight — and the winner of the fight keeps the square.")
                    }

                    section("🃏 ACTION CARDS — CONTEST A CAPTURE", color: Arcade.blue) {
                        para("Each player starts every match with 3 Action Cards. A card is your right to challenge a capture.")
                        bullet("When your piece is captured, spend a card to launch a FIGHT between your piece and the attacker instead of just losing it.")
                        bullet("Win the fight and the capture is repelled — your piece holds the square and the attacker is removed instead.")
                        bullet("Cards are spent whether you win or lose, and they do not refill during a match. Spend them wisely.")
                        bullet("Your opponent has cards too — capture their piece and they may challenge YOU.")
                        bullet("ONLINE: you always fight the challenge yourself, against a computer-controlled version of your opponent's piece. See 'How Online Fights Work' below.")
                    }

                    section("🈳 WHEN YOU RUN OUT OF CARDS", color: Arcade.red) {
                        para("Once your cards are gone, you can no longer contest captures — pieces you lose are simply taken, like normal chess. The player who manages their cards better keeps the upper hand deep into the match.")
                    }

                    section("💪 FIGHT STATS SCALE WITH PIECE VALUE", color: Arcade.gold) {
                        para("A piece's fighting power comes from its chess value. Bigger pieces are tougher brawlers:")
                        statRow("Pawn", "75 HP", "weakest")
                        statRow("Knight / Bishop", "125 HP", "")
                        statRow("Rook", "175 HP", "")
                        statRow("Queen", "275 HP", "monster")
                        statRow("King", "300 HP", "tankiest of all")
                        para("A pawn CAN topple a queen — but only with near-flawless play. Damage dealt is also scaled, so a queen hits far harder than a pawn.")
                    }

                    section("❤️ PERSISTENT HEALTH", color: Arcade.red) {
                        para("Damage carries over for the WHOLE match. A queen that survives a fight stays wounded — a health bar appears under any piece that has fought. Challenge that weakened queen again later and she enters the next fight already hurt. Health only resets between matches.")
                    }

                    section("🥊 FIGHTING: THE CONTROLS", color: Arcade.blue) {
                        para("Fights are side-view brawls with a six-button deck:")
                        bullet("L PUNCH / R PUNCH — left is a fast jab, right is a slower, harder cross.")
                        bullet("L BLOCK / R BLOCK — hold to guard a side. The foe's light attacks come from your LEFT, heavies from your RIGHT (watch the tell). Guard the correct side to absorb 80% of the hit; guess wrong and you only soften it.")
                        bullet("DODGE — timed. Tapped just before impact it negates ALL damage. Mistime it and you're caught off-balance, taking extra damage.")
                    }

                    section("⚡ STAMINA — DON'T MASH", color: Arcade.gold) {
                        para("Every action drains the stamina bar: punching, dodging, holding block, and even absorbing blocked hits. Only standing idle regenerates it.")
                        bullet("Button-mashing builds 'heat' that multiplies stamina costs — spammers burn out fast.")
                        bullet("Drop to zero and you're EXHAUSTED: you can't punch, block, or dodge, AND you take 1.5× damage until you recover. Bait your opponent into exhaustion, then punish.")
                    }

                    section("⭐ POWER SHOT (SUPER)", color: Arcade.blue) {
                        para("Land perfect dodges to charge your counter meter. Fill it — 3 perfect dodges (5 on Hard) — to unlock the ★ SUPER: a single devastating power shot worth 2.5× a heavy punch. Reading your opponent, not spamming, is how you earn it.")
                    }

                    section("👑 THE KING NEVER FALLS QUIETLY", color: Arcade.gold) {
                        para("Kings can't be captured on the board like other pieces. Instead:")
                        bullet("IN CHECK — you may move out of danger as usual, OR spend a card to send your king to fight the checking piece directly. Win and the checker is slain; lose and the king is captured (game over).")
                        bullet("CHECKMATE is not automatically the end — it triggers a mandatory FINAL FIGHT. Your doomed king duels the mating piece with no card needed. Win it and the mate is broken and play continues; lose and the king falls.")
                        bullet("Kings brawl at 300 HP — the toughest fighter in the game — so a last stand is a real chance, not a formality. This cuts both ways: checkmate the enemy and you must still finish their king yourself.")
                    }

                    section("🏆 WIN & LOSE CONDITIONS", color: Arcade.red) {
                        bullet("WIN — capture the enemy king (by winning the fight their checkmate forces), or the opponent resigns or forfeits.")
                        bullet("LOSE — your king is captured, or you resign.")
                        bullet("DRAW — stalemate, threefold repetition, the 50-move rule, or insufficient material, exactly as in standard chess.")
                        bullet("ONLINE FORFEIT — take longer than 4 days to move in an online match and you forfeit; your opponent wins by default. You'll get a daily reminder before then.")
                    }

                    section("🌐 ONLINE PLAY", color: Arcade.blue) {
                        para("Challenge friends through Game Center — matches are turn-based, so you can play several at once and take your time. The 'Your Games' menu lists every game in progress, and you'll be notified when an opponent moves, captures, or starts a fight while you're away.")
                    }

                    section("🤖 HOW ONLINE FIGHTS WORK", color: Arcade.gold) {
                        para("Online matches are turn-based, so the two of you are rarely holding your phones at the same moment. Fights therefore are NOT played live against each other.")
                        bullet("When a capture is contested, the player who spent the card fights it out on their own device — against a COMPUTER-CONTROLLED version of the opponent's piece.")
                        bullet("Your opponent doesn't sit and wait: the fight resolves immediately on your screen, and its result is final and binding.")
                        bullet("They'll be shown a recap of exactly what happened — which piece won, which fell — the next time their turn comes around.")
                        bullet("The CPU proxy fights with the real piece's stats: its true HP (including any damage it's carried from earlier fights) and its true punching power. You're facing the genuine piece, just with the computer at the controls.")
                        para("Live head-to-head fights, where both players punch it out in real time, are on the roadmap for a future update.")
                    }

                    Text("Now get out there and make your pieces earn their squares.")
                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                        .foregroundStyle(Arcade.gold)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
                .padding(20)
            }
        }
        .navigationTitle("Rulebook")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .font(.system(.body, design: .monospaced).weight(.bold))
                    .foregroundStyle(Arcade.gold)
            }
        }
    }

    // MARK: - Building blocks

    private var header: some View {
        VStack(spacing: 8) {
            PixelImage("logo_combat")
                .aspectRatio(contentMode: .fit)
                .frame(width: 220)
            PixelImage("logo_chess")
                .aspectRatio(contentMode: .fit)
                .frame(width: 180)
            Text("HOW TO PLAY")
                .font(.system(.subheadline, design: .monospaced).weight(.heavy))
                .foregroundStyle(Arcade.cream.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, 4)
    }

    private func section(_ title: String, color: Color,
                         @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(.headline, design: .monospaced).weight(.heavy))
                .foregroundStyle(color)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Arcade.panel.opacity(0.9))
        .overlay(Rectangle().strokeBorder(color.opacity(0.7), lineWidth: 2))
    }

    private func para(_ text: String) -> some View {
        Text(text)
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(Arcade.cream.opacity(0.92))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("▸")
                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                .foregroundStyle(Arcade.gold)
            Text(text)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Arcade.cream.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statRow(_ name: String, _ hp: String, _ note: String) -> some View {
        HStack {
            Text(name)
                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                .foregroundStyle(Arcade.cream)
            Spacer()
            Text(hp)
                .font(.system(.subheadline, design: .monospaced).weight(.heavy))
                .foregroundStyle(Arcade.gold)
            if !note.isEmpty {
                Text(note)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Arcade.cream.opacity(0.6))
                    .frame(width: 92, alignment: .trailing)
            } else {
                Spacer().frame(width: 92)
            }
        }
    }
}
