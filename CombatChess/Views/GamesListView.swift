import SwiftUI
import GameKit

/// "Your Games": every game in progress, organized by opponent — all active
/// online `GKTurnBasedMatch`es plus the saved single-player CPU match.
/// Games where it's the local player's move surface first.
struct GamesListView: View {
    /// Resumes the saved CPU match. Provided by `LandingView`, which owns
    /// the offline `fullScreenCover` presentation.
    let onResumeCPU: (MatchState) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var cpuState: MatchState? = MatchSnapshotStore.load()

    // MARK: - Row model

    /// One row: the CPU snapshot or an online match, labeled by opponent.
    private struct Entry: Identifiable {
        enum Kind {
            case cpu(MatchState)
            case online(GKTurnBasedMatch)
        }
        /// CPU uses a fixed id; online rows use the stable `matchID`
        /// (GKTurnBasedMatch is a class, so identity comes from the id).
        let id: String
        let kind: Kind
        let opponentName: String
        let detail: String
        let isLocalTurn: Bool
        /// Opponent's pieces render the row icon.
        let iconColor: PieceColor
    }

    private var entries: [Entry] {
        var list: [Entry] = []

        // Saved single-player game (offline the local player is always White).
        if let state = cpuState {
            list.append(Entry(
                id: "local-cpu",
                kind: .cpu(state),
                opponentName: "COMPUTER · \(state.difficulty.label.uppercased())",
                detail: "MOVE \(state.moveCount / 2 + 1) · SINGLE PLAYER",
                isLocalTurn: state.board.turn == .white,
                iconColor: .black))
        }

        // Active online matches (swept by GameKitManager.refreshMatches()).
        let localID = GKLocalPlayer.local.gamePlayerID
        for match in GameKitManager.shared.activeMatches {
            let opponent = match.participants.first {
                $0.player?.gamePlayerID != localID
            }?.player?.displayName
            // Participant order fixes colors: index 0 (the creator) is White.
            let localIndex = match.participants.firstIndex {
                $0.player?.gamePlayerID == localID
            } ?? 0
            let stillMatching = match.status == .matching || opponent == nil
            list.append(Entry(
                id: match.matchID,
                kind: .online(match),
                opponentName: (opponent ?? "AWAITING RIVAL").uppercased(),
                detail: stillMatching ? "ONLINE · FINDING OPPONENT…"
                                      : "ONLINE · GAME CENTER",
                isLocalTurn: match.currentParticipant?.player?.gamePlayerID == localID,
                iconColor: localIndex == 0 ? .black : .white))
        }

        // Your-move games first, then alphabetical by opponent (stable order).
        return list.sorted {
            if $0.isLocalTurn != $1.isLocalTurn { return $0.isLocalTurn }
            return $0.opponentName < $1.opponentName
        }
    }

    // MARK: - Body

    var body: some View {
        let all = entries
        let yourMove = all.filter { $0.isLocalTurn }
        let theirMove = all.filter { !$0.isLocalTurn }

        return ZStack {
            Arcade.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if all.isEmpty {
                        emptyState
                    } else {
                        if !yourMove.isEmpty {
                            sectionHeader("YOUR MOVE", color: Arcade.gold)
                            ForEach(yourMove) { row($0) }
                        }
                        if !theirMove.isEmpty {
                            sectionHeader("WAITING ON OPPONENT",
                                          color: Arcade.cream.opacity(0.6))
                            ForEach(theirMove) { row($0) }
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Your Games")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            cpuState = MatchSnapshotStore.load()
            GameKitManager.shared.refreshMatches()
        }
        // Returning from a match (the online cover dismissed): re-sweep so
        // turn flags reflect the move that was just played.
        .onChange(of: GameKitManager.shared.activeCoordinator == nil) { _, isClosed in
            if isClosed {
                cpuState = MatchSnapshotStore.load()
                GameKitManager.shared.refreshMatches()
            }
        }
    }

    // MARK: - Pieces

    private func sectionHeader(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(.caption2, design: .monospaced).weight(.heavy))
            .foregroundStyle(color)
            .padding(.top, 6)
    }

    private func row(_ entry: Entry) -> some View {
        Button {
            Haptics.impact(.medium)
            open(entry)
        } label: {
            HStack(spacing: 12) {
                PixelImage(PieceType.knight.iconAsset(for: entry.iconColor))
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.opponentName)
                        .font(.system(.subheadline, design: .monospaced).weight(.heavy))
                        .foregroundStyle(Arcade.cream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(entry.detail)
                        .font(.system(size: 9, design: .monospaced).weight(.bold))
                        .foregroundStyle(Arcade.cream.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(entry.isLocalTurn ? "YOUR MOVE" : "THEIR MOVE")
                    .font(.system(size: 10, design: .monospaced).weight(.heavy))
                    .foregroundStyle(entry.isLocalTurn ? Color.black : Arcade.cream.opacity(0.6))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(entry.isLocalTurn ? Arcade.gold : Color.black.opacity(0.5))
                    .overlay(Rectangle().strokeBorder(
                        entry.isLocalTurn ? Arcade.gold : Arcade.cream.opacity(0.35),
                        lineWidth: 2))
            }
            .padding(12)
            .background(Arcade.panel.opacity(0.95))
            .overlay(Rectangle().strokeBorder(
                entry.isLocalTurn ? Arcade.gold : Arcade.cream.opacity(0.3),
                lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            PixelImage("text_vs")
                .aspectRatio(contentMode: .fit)
                .frame(width: 70)
            Text("NO GAMES IN PROGRESS")
                .font(.system(.subheadline, design: .monospaced).weight(.heavy))
                .foregroundStyle(Arcade.cream)
            Text("START A GAME OR INVITE A FRIEND\nFROM THE TITLE SCREEN")
                .font(.system(size: 10, design: .monospaced).weight(.bold))
                .foregroundStyle(Arcade.cream.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Opening a game

    private func open(_ entry: Entry) {
        switch entry.kind {
        case .cpu(let state):
            // Pop back to the landing screen (it owns the offline cover),
            // then hand it the snapshot on the next runloop so the cover
            // presents from a settled hierarchy.
            dismiss()
            DispatchQueue.main.async {
                onResumeCPU(state)
            }
        case .online(let match):
            // The online cover is attached to the NavigationStack itself,
            // so it presents fine over this pushed screen. The coordinator
            // reloads authoritative match data on init.
            GameKitManager.shared.openMatch(match)
        }
    }
}
