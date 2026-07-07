import SwiftUI
import SwiftData

/// Match screen (PRD §3.2): pixel board, HUD, challenge prompt, fight hand-off, result.
struct MatchView: View {
    let controller: MatchController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var recorded = false
    @State private var showResignConfirm = false

    private let challengeTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var controller = controller
        ZStack {
            Arcade.bg.ignoresSafeArea()

            // HUDs pinned top/bottom; the board sits dead-center in the screen.
            VStack(spacing: 0) {
                opponentHUD
                Spacer(minLength: 0)
                playerHUD
            }
            .padding(.top, 8)

            BoardView(controller: controller)
                .aspectRatio(1, contentMode: .fit)
                .overlay(Rectangle().strokeBorder(Arcade.gold.opacity(0.8), lineWidth: 3))
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            if controller.phase == .aiChallengeBanner {
                bannerOverlay
            }
            if controller.phase == .awaitingChallengeDecision, let pending = controller.pending {
                ChallengePromptView(pending: pending, controller: controller)
            }
            if controller.phase == .gameOver {
                gameOverOverlay
            }
        }
        .fullScreenCover(item: $controller.fightSetup) { setup in
            FightView(setup: setup) { result in
                controller.fightEnded(result)
            }
        }
        .onReceive(challengeTimer) { _ in
            if let deadline = controller.challengeDeadline, Date() >= deadline {
                controller.playerDeclinesChallenge()
            }
        }
        .onChange(of: controller.gameResult) { _, newValue in
            guard newValue != nil else { return }
            recordMatchIfNeeded()
        }
        .onAppear {
            controller.start()
        }
        .confirmationDialog("Abandon this match?", isPresented: $showResignConfirm, titleVisibility: .visible) {
            Button("Resign (counts as a loss)", role: .destructive) {
                controller.resign()
            }
            Button("Keep Playing", role: .cancel) {}
        }
    }

    // MARK: - HUD

    private var opponentHUD: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(controller.opponentKind == .remote
                         ? controller.remoteOpponentName
                         : "CPU·\(controller.state.difficulty.label.uppercased())")
                        .font(.system(.subheadline, design: .monospaced).weight(.heavy))
                        .foregroundStyle(Arcade.red)
                        .lineLimit(1)
                    if controller.phase == .aiThinking || controller.phase == .waitingForOpponent {
                        ProgressView().controlSize(.small).tint(Arcade.cream)
                    }
                }
                if controller.phase == .waitingForOpponent {
                    Text("WAITING FOR THEIR MOVE…")
                        .font(.system(size: 9, design: .monospaced).weight(.bold))
                        .foregroundStyle(Arcade.cream.opacity(0.6))
                }
                cardRow(count: controller.opponentCards,
                        total: controller.opponentCardsStart,
                        team: controller.localColor.opposite.teamName)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Button {
                    showResignConfirm = true
                } label: {
                    Label("RESIGN", systemImage: "flag.fill")
                        .font(.system(.caption2, design: .monospaced).weight(.heavy))
                        .foregroundStyle(Arcade.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.6))
                        .overlay(Rectangle().strokeBorder(Arcade.red, lineWidth: 2))
                }
                capturedTray(symbols: controller.capturedByOpponent,
                             pieceColor: controller.localColor)
            }
        }
        .padding(.horizontal, 16)
    }

    private var playerHUD: some View {
        VStack(spacing: 8) {
            // Check-challenge bar: fight the checker instead of moving away.
            if controller.phase == .playerTurn && controller.canChallengeCheck {
                Button {
                    controller.playerChallengesCheck()
                } label: {
                    Text("CHECK! ⚔ KING FIGHTS THE \(controller.currentCheckerType?.displayName.uppercased() ?? "CHECKER") (1 CARD)")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .buttonStyle(ArcadeButtonStyle(color: Arcade.red, filled: true))
            }
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("YOU")
                            .font(.system(.subheadline, design: .monospaced).weight(.heavy))
                            .foregroundStyle(Arcade.blue)
                        if controller.playerInCheck && controller.gameResult == nil {
                            Text("CHECK!")
                                .font(.system(.caption, design: .monospaced).weight(.heavy))
                                .foregroundStyle(.red)
                        }
                    }
                    cardRow(count: controller.localCards,
                            total: controller.localCardsStart,
                            team: controller.localColor.teamName)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    capturedTray(symbols: controller.capturedByLocal,
                                 pieceColor: controller.localColor.opposite)
                    Text("MOVE \(controller.state.moveCount / 2 + 1)")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(Arcade.cream.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    /// SF-style pixel action cards: lit while held, burnt out once spent.
    private func cardRow(count: Int, total: Int, team: String) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { i in
                PixelImage(i < count ? "card_\(team)" : "card_spent")
                    .frame(width: 26, height: 36)
                    .opacity(i < count ? 1.0 : 0.6)
                    .shadow(color: i < count ? Arcade.gold.opacity(0.5) : .clear, radius: 3)
            }
        }
    }

    /// Captured-piece tray rendered with pixel icons.
    private func capturedTray(symbols: [String], pieceColor: PieceColor) -> some View {
        HStack(spacing: 1) {
            ForEach(Array(symbols.suffix(8).enumerated()), id: \.offset) { _, symbol in
                if let type = PieceType.allCases.first(where: { $0.symbol == symbol }) {
                    PixelImage(type.iconAsset(for: pieceColor))
                        .frame(width: 18, height: 18)
                }
            }
        }
        .frame(maxWidth: 170, alignment: .trailing)
    }

    // MARK: - Overlays

    private var bannerOverlay: some View {
        VStack(spacing: 10) {
            PixelImage("text_vs")
                .aspectRatio(contentMode: .fit)
                .frame(width: 80)
            Text(controller.bannerText)
                .font(.system(.headline, design: .monospaced).weight(.heavy))
                .foregroundStyle(Arcade.cream)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .arcadePanel(border: Arcade.red)
        .transition(.scale)
    }

    private var gameOverOverlay: some View {
        VStack(spacing: 14) {
            Text(resultTitle)
                .font(.system(size: 38, weight: .heavy, design: .monospaced))
                .foregroundStyle(resultColor)
            Text(controller.gameResultDetail.uppercased())
                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                .foregroundStyle(Arcade.cream.opacity(0.8))
            PixelImage(resultSpriteName)
                .aspectRatio(contentMode: .fit)
                .frame(height: 90)
            Button {
                recordMatchIfNeeded()
                dismiss()
            } label: {
                Text("Back to Menu")
            }
            .buttonStyle(ArcadeButtonStyle(color: Arcade.gold))
            .frame(width: 230)

            Text("RETURNING TO MENU…")
                .font(.system(size: 9, design: .monospaced).weight(.bold))
                .foregroundStyle(Arcade.cream.opacity(0.5))
        }
        .padding(30)
        .arcadePanel(border: resultColor)
        .task {
            // Auto-return to the start screen shortly after the match ends.
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            recordMatchIfNeeded()
            dismiss()
        }
    }

    private var resultTitle: String {
        switch controller.gameResult {
        case "win": return "VICTORY"
        case "loss": return "DEFEAT"
        default: return "DRAW"
        }
    }

    private var resultColor: Color {
        switch controller.gameResult {
        case "win": return Arcade.gold
        case "loss": return Arcade.red
        default: return Arcade.cream
        }
    }

    private var resultSpriteName: String {
        let team = controller.localColor.teamName
        switch controller.gameResult {
        case "win": return PieceType.queen.fighterAsset(team: team, frame: "punch_r")
        case "loss": return PieceType.queen.fighterAsset(team: team, frame: "ko")
        default: return PieceType.queen.fighterAsset(team: team, frame: "block_l")
        }
    }

    // MARK: - Recording (PRD §6)

    private func recordMatchIfNeeded() {
        guard !recorded, let result = controller.gameResult else { return }
        recorded = true
        let fights = controller.state.fightLogs.map { log in
            FightRecord(moveNumber: log.moveNumber,
                        attackerType: log.attackerType,
                        defenderType: log.defenderType,
                        initiatedBy: log.initiatedBy,
                        playerWon: log.playerWon,
                        upsetDelta: log.upsetDelta,
                        durationSec: log.durationSec)
        }
        let record = MatchRecord(date: .now,
                                 difficulty: controller.state.difficulty.rawValue,
                                 result: result,
                                 resultDetail: controller.gameResultDetail,
                                 moveCount: controller.state.moveCount,
                                 playerCardsUsed: controller.state.playerCardsUsed,
                                 aiCardsUsed: controller.state.aiCardsUsed,
                                 fights: fights)
        modelContext.insert(record)
    }
}

// MARK: - Board

struct BoardView: View {
    let controller: MatchController

    var body: some View {
        GeometryReader { geo in
            let cell = geo.size.width / 8
            let flipped = controller.localColor == .black
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { col in
                            let sq = SquareUtil.index(file: flipped ? 7 - col : col,
                                                      rank: flipped ? row : 7 - row)
                            SquareView(square: sq,
                                       piece: controller.state.board.squares[sq],
                                       isSelected: controller.selectedSquare == sq,
                                       isTarget: controller.legalTargets.contains { $0.to == sq },
                                       isLastMove: controller.lastMove?.from == sq || controller.lastMove?.to == sq,
                                       size: cell)
                                .onTapGesture {
                                    controller.tapSquare(sq)
                                    Haptics.moveSound()
                                }
                        }
                    }
                }
            }
        }
    }
}

struct SquareView: View {
    let square: Int
    let piece: Piece?
    let isSelected: Bool
    let isTarget: Bool
    let isLastMove: Bool
    let size: CGFloat

    private var isLight: Bool {
        return (SquareUtil.file(square) + SquareUtil.rank(square)) % 2 == 1
    }

    var body: some View {
        ZStack {
            PixelImage(isLight ? "tile_light" : "tile_dark")
            if isLastMove {
                Rectangle().fill(Arcade.gold.opacity(0.28))
            }
            if isSelected {
                Rectangle().fill(Arcade.blue.opacity(0.45))
            }
            if isTarget {
                if piece == nil {
                    Rectangle()
                        .fill(Color.green.opacity(0.7))
                        .frame(width: size * 0.22, height: size * 0.22)
                } else {
                    Rectangle().strokeBorder(Color.green.opacity(0.9), lineWidth: 3)
                }
            }
            if let piece = piece {
                VStack(spacing: 0) {
                    PixelImage(piece.type.iconAsset(for: piece.color))
                        .frame(width: size * 0.78, height: size * 0.78)
                    // Persistent HP bar for pieces that have fought (PRD §2.5).
                    if piece.hasFought {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.black.opacity(0.65))
                                Rectangle()
                                    .fill(piece.hpFraction > 0.5 ? Color.green :
                                          piece.hpFraction > 0.25 ? Color.yellow : Color.red)
                                    .frame(width: g.size.width * piece.hpFraction)
                            }
                        }
                        .frame(width: size * 0.7, height: size * 0.1)
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Challenge prompt (PRD §3.2)

struct ChallengePromptView: View {
    let pending: PendingCapture
    let controller: MatchController
    @State private var now = Date()

    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var remainingFraction: Double {
        guard let deadline = controller.challengeDeadline else { return 0 }
        return max(0, min(1, deadline.timeIntervalSince(now) / 10))
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("YOUR \(pending.defender.type.displayName.uppercased()) IS UNDER ATTACK!")
                .font(.system(.subheadline, design: .monospaced).weight(.heavy))
                .foregroundStyle(Arcade.cream)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                fighterCard(piece: pending.defender, team: pending.defender.color.teamName,
                            label: "YOURS", color: Arcade.blue)
                PixelImage("text_vs")
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 52)
                fighterCard(piece: pending.attacker, team: pending.attacker.color.teamName,
                            label: "ENEMY", color: Arcade.red, mirrored: true)
            }

            HStack(spacing: 14) {
                Text("CARDS LEFT: \(controller.localCards)")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(Arcade.cream.opacity(0.7))

                // Countdown only for live challenges; async (online) prompts
                // wait indefinitely for the defender's decision.
                if controller.challengeDeadline != nil {
                    ZStack {
                        Circle().stroke(Color.gray.opacity(0.3), lineWidth: 5)
                        Circle()
                            .trim(from: 0, to: remainingFraction)
                            .stroke(remainingFraction > 0.3 ? Arcade.gold : Arcade.red,
                                    style: StrokeStyle(lineWidth: 5, lineCap: .square))
                            .rotationEffect(.degrees(-90))
                        Text(String(Int((remainingFraction * 10).rounded(.up))))
                            .font(.system(.subheadline, design: .monospaced).weight(.heavy))
                            .foregroundStyle(Arcade.cream)
                    }
                    .frame(width: 40, height: 40)
                }
            }

            HStack(spacing: 12) {
                Button {
                    controller.playerDeclinesChallenge()
                } label: {
                    Text("Concede")
                }
                .buttonStyle(ArcadeButtonStyle(color: Arcade.cream.opacity(0.7)))

                Button {
                    controller.playerAcceptsChallenge()
                } label: {
                    Text("Fight!")
                }
                .buttonStyle(ArcadeButtonStyle(color: Arcade.red, filled: true))
            }
        }
        .padding(4)
        .frame(maxWidth: 360)
        .arcadePanel(border: Arcade.gold)
        .padding(20)
        .onReceive(timer) { date in
            now = date
        }
    }

    private func fighterCard(piece: Piece, team: String, label: String,
                             color: Color, mirrored: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(.caption2, design: .monospaced).weight(.heavy))
                .foregroundStyle(color)
            PixelImage(piece.type.fighterAsset(team: team, frame: "idle_a"))
                .aspectRatio(contentMode: .fit)
                .frame(height: 70)
                .scaleEffect(x: mirrored ? -1 : 1)
            Text(piece.type.displayName.uppercased())
                .font(.system(.caption2, design: .monospaced).weight(.heavy))
                .foregroundStyle(Arcade.cream)
            Text("HP \(piece.currentHP)/\(piece.maxHP)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(piece.hpFraction > 0.5 ? .green : piece.hpFraction > 0.25 ? .yellow : .red)
        }
        .frame(width: 96)
    }
}
