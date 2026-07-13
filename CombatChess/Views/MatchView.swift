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

            // Names + action cards hug the board; utility controls sit at the
            // screen's top (Menu) and bottom (Resign) corners.
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)

                opponentHUD                       // directly above the board
                BoardView(controller: controller)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(Rectangle().strokeBorder(Arcade.gold.opacity(0.8), lineWidth: 3))
                    .padding(.horizontal, 8)
                playerHUD                         // directly below the board

                // A capture is awaiting the OTHER side's fight-or-concede
                // decision: reassure the waiting player the game isn't hung.
                if controller.contestedSquare != nil {
                    ContestedIndicatorView(subtitle: controller.opponentKind == .remote
                        ? "AWAITING \(controller.remoteOpponentName)'S DECISION"
                        : "OPPONENT IS DECIDING…")
                        .padding(.top, 10)
                }

                Spacer(minLength: 0)
                bottomBar
            }
            .padding(.top, 8)

            if controller.phase == .aiChallengeBanner {
                bannerOverlay
            }
            if controller.phase == .awaitingChallengeDecision, let pending = controller.pending {
                ChallengePromptView(pending: pending, controller: controller)
            }
            if controller.phase == .fightRecap, let recap = controller.fightRecap {
                FightRecapView(recap: recap) {
                    controller.dismissFightRecap()
                }
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
        // Online problems are no longer silent: a failed send would otherwise
        // hang the match forever, and bad turn data would look like a freeze.
        .alert(controller.onlineError?.title ?? "",
               isPresented: Binding(
                get: { controller.onlineError != nil },
                set: { if !$0 { controller.onlineError = nil } })) {
            if controller.onlineError == .sendFailed {
                Button("Try Again") {
                    GameKitManager.shared.activeCoordinator?.retryFailedTurn()
                }
                Button("Back to Menu", role: .cancel) { dismiss() }
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(controller.onlineError?.message ?? "")
        }
    }

    // MARK: - HUD

    /// Screen top: Menu (leave without resigning) + the move counter.
    private var topBar: some View {
        HStack {
            // Leave WITHOUT resigning: the game stays in progress (online
            // matches live on in Game Center; the CPU game is snapshotted
            // after every move). No state is touched.
            Button {
                Haptics.impact(.light)
                dismiss()
            } label: {
                Label("MENU", systemImage: "house.fill")
                    .font(.system(.caption2, design: .monospaced).weight(.heavy))
                    .foregroundStyle(Arcade.cream)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.6))
                    .overlay(Rectangle().strokeBorder(Arcade.cream.opacity(0.7), lineWidth: 2))
            }
            Spacer()
            Text("MOVE \(controller.state.moveCount / 2 + 1)")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(Arcade.cream.opacity(0.6))
        }
        .padding(.horizontal, 16)
    }

    /// Screen bottom: Resign, anchored bottom-right.
    private var bottomBar: some View {
        HStack {
            Spacer()
            Button {
                showResignConfirm = true
            } label: {
                Label("RESIGN", systemImage: "flag.fill")
                    .font(.system(.caption2, design: .monospaced).weight(.heavy))
                    .foregroundStyle(Arcade.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.6))
                    .overlay(Rectangle().strokeBorder(Arcade.red, lineWidth: 2))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    /// Opponent strip — sits directly on top of the board.
    private var opponentHUD: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
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
                if controller.phase == .waitingForOpponent && controller.contestedSquare == nil {
                    Text("WAITING FOR THEIR MOVE…")
                        .font(.system(size: 9, design: .monospaced).weight(.bold))
                        .foregroundStyle(Arcade.cream.opacity(0.6))
                }
                capturedTray(symbols: controller.capturedByOpponent,
                             pieceColor: controller.localColor)
            }
            Spacer()
            cardRow(count: controller.opponentCards,
                    total: controller.opponentCardsStart,
                    team: controller.localColor.opposite.teamName)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
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
            HStack(alignment: .center) {
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
                    capturedTray(symbols: controller.capturedByLocal,
                                 pieceColor: controller.localColor.opposite)
                }
                Spacer()
                cardRow(count: controller.localCards,
                        total: controller.localCardsStart,
                        team: controller.localColor.teamName)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    /// SF-style pixel action cards: lit while held, burnt out once spent.
    private func cardRow(count: Int, total: Int, team: String) -> some View {
        HStack(spacing: 7) {
            ForEach(0..<total, id: \.self) { i in
                PixelImage(i < count ? "card_\(team)" : "card_spent")
                    .frame(width: 42, height: 58)
                    .opacity(i < count ? 1.0 : 0.55)
                    .shadow(color: i < count ? Arcade.gold.opacity(0.6) : .clear, radius: 4)
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

    /// Currently animating move: (from, to, progress 0→1).
    @State private var slide: (from: Int, to: Int, progress: Double)?

    private func screenPos(_ sq: Int, cell: CGFloat, flipped: Bool) -> CGPoint {
        let file = SquareUtil.file(sq), rank = SquareUtil.rank(sq)
        let col = flipped ? 7 - file : file
        let row = flipped ? rank : 7 - rank
        return CGPoint(x: (CGFloat(col) + 0.5) * cell, y: (CGFloat(row) + 0.5) * cell)
    }

    var body: some View {
        GeometryReader { geo in
            let cell = geo.size.width / 8
            let flipped = controller.localColor == .black
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<8, id: \.self) { col in
                                let sq = SquareUtil.index(file: flipped ? 7 - col : col,
                                                          rank: flipped ? row : 7 - row)
                                // Hide the destination piece while it slides in,
                                // and the fight loser while its shatter plays.
                                let hidden = slide?.to == sq
                                    || controller.shatteringPiece?.square == sq
                                SquareView(square: sq,
                                           piece: hidden ? nil : controller.state.board.squares[sq],
                                           isSelected: controller.selectedSquare == sq,
                                           isTarget: controller.legalTargets.contains { $0.to == sq },
                                           isLastMove: controller.lastMove?.from == sq || controller.lastMove?.to == sq,
                                           isContested: controller.contestedSquare == sq,
                                           // Notation on the board edges, derived from the true
                                           // square so it stays correct when flipped for Black.
                                           fileLabel: row == 7 ? String(Array("ABCDEFGH")[SquareUtil.file(sq)]) : nil,
                                           rankLabel: col == 0 ? String(SquareUtil.rank(sq) + 1) : nil,
                                           size: cell)
                                    .onTapGesture {
                                        controller.tapSquare(sq)
                                        Haptics.moveSound()
                                    }
                            }
                        }
                    }
                }
                // Fight loser breaking apart on its square (plays while the
                // board still shows the pre-resolution position underneath).
                if let sp = controller.shatteringPiece {
                    ShatterEffectView(type: sp.type, color: sp.color, cell: cell)
                        .frame(width: cell, height: cell)
                        .position(screenPos(sp.square, cell: cell, flipped: flipped))
                        .allowsHitTesting(false)
                        .id(sp.id)
                }
                // Sliding piece overlay.
                if let s = slide, let piece = controller.state.board.squares[s.to] {
                    let from = screenPos(s.from, cell: cell, flipped: flipped)
                    let to = screenPos(s.to, cell: cell, flipped: flipped)
                    PixelImage(piece.type.iconAsset(for: piece.color))
                        .frame(width: cell * 0.78, height: cell * 0.78)
                        .position(x: from.x + (to.x - from.x) * s.progress,
                                  y: from.y + (to.y - from.y) * s.progress)
                }
            }
            .onChange(of: controller.lastMove) { _, mv in
                guard let mv = mv, mv.from != mv.to,
                      controller.state.board.squares[mv.to] != nil else {
                    slide = nil
                    return
                }
                slide = (mv.from, mv.to, 0)
                // Kick the tween on the next runloop so progress 0 renders first.
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        slide?.progress = 1
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                    slide = nil
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
    /// This square's capture is awaiting the other player's decision.
    var isContested: Bool = false
    var fileLabel: String? = nil
    var rankLabel: String? = nil
    let size: CGFloat

    private var isLight: Bool {
        return (SquareUtil.file(square) + SquareUtil.rank(square)) % 2 == 1
    }

    /// Notation ink: contrast against the tile it sits on.
    private var labelColor: Color {
        return isLight ? Color(red: 0.42, green: 0.32, blue: 0.26)
                       : Color(red: 0.90, green: 0.84, blue: 0.72)
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
            if isContested {
                ContestedGlowView()
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

            // Rank number (top-left) and file letter (bottom-right), on the
            // board edges only. Derived from the true square, so orientation
            // follows the flip automatically for Black.
            if let rankLabel = rankLabel {
                Text(rankLabel)
                    .font(.system(size: max(9, size * 0.19), design: .monospaced).weight(.bold))
                    .foregroundStyle(labelColor)
                    .padding(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if let fileLabel = fileLabel {
                Text(fileLabel)
                    .font(.system(size: max(9, size * 0.19), design: .monospaced).weight(.bold))
                    .foregroundStyle(labelColor)
                    .padding(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Fight-loss shatter

/// Pixel-shatter played on the square of a piece that just lost a fight:
/// a quick impact flash, the icon crushing inward, and chunky square shards
/// bursting outward with spin before fading — arcade-style destruction.
/// Runs ~0.5 s; `MatchController` clears `shatteringPiece` right after.
private struct ShatterEffectView: View {
    let type: PieceType
    let color: PieceColor
    let cell: CGFloat

    @State private var flashed = false
    @State private var burst = false

    private struct Shard {
        let dx: CGFloat      // final offset, in cell fractions
        let dy: CGFloat
        let size: CGFloat    // side length, in cell fractions
        let spin: Double     // final rotation, degrees
        let isSpark: Bool    // gold spark vs. piece-colored chunk
    }

    /// Fixed, hand-tuned burst layout (deterministic — no randomness).
    private static let shards: [Shard] = [
        Shard(dx: -0.52, dy: -0.38, size: 0.16, spin: -160, isSpark: false),
        Shard(dx:  0.48, dy: -0.50, size: 0.12, spin:  140, isSpark: true),
        Shard(dx:  0.60, dy: -0.06, size: 0.18, spin:  110, isSpark: false),
        Shard(dx:  0.44, dy:  0.46, size: 0.11, spin: -120, isSpark: true),
        Shard(dx: -0.05, dy:  0.58, size: 0.17, spin:  170, isSpark: false),
        Shard(dx: -0.55, dy:  0.34, size: 0.10, spin: -140, isSpark: true),
        Shard(dx: -0.62, dy: -0.02, size: 0.14, spin:  130, isSpark: false),
        Shard(dx:  0.06, dy: -0.62, size: 0.15, spin: -170, isSpark: false),
    ]

    /// Shard body color matches the doomed piece's team.
    private var chunkColor: Color {
        return color == .white
            ? Arcade.cream
            : Color(red: 0.36, green: 0.31, blue: 0.45)
    }

    var body: some View {
        ZStack {
            // Impact flash on the square.
            Rectangle()
                .fill(Arcade.cream)
                .opacity(flashed ? 0 : 0.7)
            // The piece itself crushing inward.
            PixelImage(type.iconAsset(for: color))
                .frame(width: cell * 0.78, height: cell * 0.78)
                .scaleEffect(burst ? 0.1 : 1.0)
                .rotationEffect(.degrees(burst ? 18 : 0))
                .opacity(burst ? 0 : 1)
            // Chunky pixel shards flying outward.
            ForEach(0..<Self.shards.count, id: \.self) { i in
                let s = Self.shards[i]
                Rectangle()
                    .fill(s.isSpark ? Arcade.gold : chunkColor)
                    .frame(width: cell * s.size, height: cell * s.size)
                    .rotationEffect(.degrees(burst ? s.spin : 0))
                    .offset(x: burst ? cell * s.dx : 0,
                            y: burst ? cell * s.dy : 0)
                    .opacity(burst ? 0 : 0.95)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.12)) {
                flashed = true
            }
            withAnimation(.easeOut(duration: 0.5)) {
                burst = true
            }
        }
    }
}

// MARK: - Contested capture (waiting player's view)

/// Pulsing light-red glow over the square whose capture is awaiting the
/// other player's fight-or-concede decision.
private struct ContestedGlowView: View {
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Arcade.red.opacity(pulsing ? 0.42 : 0.12))
            Rectangle()
                .strokeBorder(Arcade.red.opacity(pulsing ? 0.95 : 0.35), lineWidth: 3)
                .shadow(color: Arcade.red.opacity(pulsing ? 0.8 : 0.2), radius: 6)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}

/// "Capture contested" pill shown to the player waiting on the other side's
/// decision — distinct from the pre-fight challenge banner.
private struct ContestedIndicatorView: View {
    let subtitle: String
    @State private var pulsing = false

    var body: some View {
        VStack(spacing: 3) {
            Text("CAPTURE CONTESTED…")
                .font(.system(.caption, design: .monospaced).weight(.heavy))
                .foregroundStyle(Arcade.red)
                .opacity(pulsing ? 1.0 : 0.55)
            Text(subtitle)
                .font(.system(size: 10, design: .monospaced).weight(.bold))
                .foregroundStyle(Arcade.cream.opacity(0.75))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.7))
        .overlay(Rectangle().strokeBorder(Arcade.red.opacity(0.8), lineWidth: 2))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
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

// MARK: - Fight recap (online: outcome shown to the player who waited)

struct FightRecapView: View {
    let recap: MatchController.FightRecap
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("⚔️ A FIGHT BROKE OUT")
                .font(.system(.caption, design: .monospaced).weight(.heavy))
                .foregroundStyle(Arcade.gold)
            Text(recap.headline)
                .font(.system(.headline, design: .monospaced).weight(.heavy))
                .foregroundStyle(Arcade.cream)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                // Your piece — triumphant or floored based on the result.
                PixelImage(recap.localPieceType.fighterAsset(
                    team: recap.localTeam, frame: recap.localWon ? "punch_r" : "ko"))
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 96)
                PixelImage("text_vs")
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 52)
                PixelImage(recap.foePieceType.fighterAsset(
                    team: recap.foeTeam, frame: recap.localWon ? "ko" : "punch_r"))
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 96)
                    .scaleEffect(x: -1)
            }

            Text(recap.localWon ? "YOU HELD" : "YOU LOST")
                .font(.system(size: 34, weight: .heavy, design: .monospaced))
                .foregroundStyle(recap.localWon ? Arcade.gold : Arcade.red)
            Text(recap.outcome)
                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                .foregroundStyle(Arcade.cream.opacity(0.85))
                .multilineTextAlignment(.center)

            Button {
                onContinue()
            } label: {
                Text("Continue")
            }
            .buttonStyle(ArcadeButtonStyle(color: Arcade.gold))
            .frame(width: 220)
        }
        .padding(24)
        .frame(maxWidth: 380)
        .arcadePanel(border: recap.localWon ? Arcade.gold : Arcade.red)
        .padding(20)
    }
}
