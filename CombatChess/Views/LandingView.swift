import SwiftUI
import GameKit

/// Arcade title screen (PRD §3.1): start game, difficulty, history, settings.
struct LandingView: View {
    @AppStorage("defaultDifficulty") private var defaultDifficulty = Difficulty.medium.rawValue
    // Observed so the buttons refresh after tuning Elo in Settings.
    @AppStorage("elo_easy") private var eloEasy: Double = 0
    @AppStorage("elo_medium") private var eloMedium: Double = 0
    @AppStorage("elo_hard") private var eloHard: Double = 0
    @State private var activeMatch: MatchController?
    @State private var hasResumableMatch = MatchSnapshotStore.hasSnapshot

    private var difficulty: Difficulty {
        return Difficulty(rawValue: defaultDifficulty) ?? .medium
    }

    /// Badge count for the "Your Games" button: active online matches plus
    /// the resumable CPU snapshot.
    private var gamesInProgress: Int {
        return GameKitManager.shared.activeMatches.count + (hasResumableMatch ? 1 : 0)
    }

    /// Inviter's display name for the pending-challenge button (participant
    /// 0 is always the match creator; see OnlineMatchCoordinator).
    private static func inviterName(_ match: GKTurnBasedMatch) -> String {
        let name = match.participants.first?.player?.displayName ?? "A RIVAL"
        return name.uppercased()
    }

    /// Elo shown on the selector (tracks the Settings sliders live).
    private func shownElo(_ d: Difficulty) -> Int {
        let stored: Double
        switch d {
        case .easy: stored = eloEasy
        case .medium: stored = eloMedium
        case .hard: stored = eloHard
        }
        let value = stored == 0 ? d.defaultElo : stored
        return Int(min(max(value, d.eloRange.lowerBound), d.eloRange.upperBound))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PixelImage("bg_title")
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()

                // Rulebook — top-right corner.
                VStack {
                    HStack {
                        Spacer()
                        NavigationLink {
                            RulebookView()
                        } label: {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(Arcade.gold)
                                .padding(8)
                                .background(Color.black.opacity(0.4), in: Circle())
                        }
                        .padding(.trailing, 20)
                        .padding(.top, 8)
                    }
                    Spacer()
                }
                .zIndex(1)

                VStack(spacing: 0) {
                    Spacer(minLength: 30)

                    // Pixel logo
                    VStack(spacing: 8) {
                        PixelImage("logo_combat")
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 300)
                        PixelImage("logo_chess")
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 250)
                        Text("CAPTURE · CHALLENGE · FIGHT")
                            .font(.system(.caption, design: .monospaced).weight(.bold))
                            .foregroundStyle(Arcade.cream.opacity(0.75))
                            .padding(.top, 6)
                    }

                    // Marquee fighters
                    HStack(spacing: 12) {
                        PixelImage(PieceType.knight.fighterAsset(team: "white", frame: "punch_l"))
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 110)
                        PixelImage("text_vs")
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 34)
                        PixelImage(PieceType.queen.fighterAsset(team: "black", frame: "idle_a"))
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 110)
                            .scaleEffect(x: -1)
                    }
                    .padding(.top, 18)

                    Spacer()

                    // Difficulty selector
                    VStack(spacing: 8) {
                        Text("DIFFICULTY")
                            .font(.system(.caption2, design: .monospaced).weight(.heavy))
                            .foregroundStyle(Arcade.cream.opacity(0.7))
                        HStack(spacing: 8) {
                            ForEach(Difficulty.allCases) { d in
                                Button {
                                    defaultDifficulty = d.rawValue
                                    Haptics.impact(.light)
                                } label: {
                                    VStack(spacing: 2) {
                                        Text(d.label)
                                        Text("\(shownElo(d)) ELO")
                                            .font(.system(size: 9, design: .monospaced).weight(.bold))
                                            .opacity(0.85)
                                    }
                                }
                                .buttonStyle(ArcadeButtonStyle(
                                    color: d == difficulty ? Arcade.gold : Arcade.cream.opacity(0.5),
                                    filled: d == difficulty))
                            }
                        }
                    }
                    .padding(.horizontal, 28)

                    // Menu
                    VStack(spacing: 10) {
                        Button {
                            MatchSnapshotStore.clear()
                            activeMatch = MatchController(difficulty: difficulty)
                        } label: {
                            Text("▶ Start Game")
                        }
                        .buttonStyle(ArcadeButtonStyle(color: Arcade.gold))

                        // Every game in progress, grouped by opponent:
                        // active online matches + the saved CPU game.
                        if gamesInProgress > 0 {
                            NavigationLink {
                                GamesListView { saved in
                                    activeMatch = MatchController(resuming: saved)
                                }
                            } label: {
                                Text("Your Games · \(gamesInProgress)")
                            }
                            .buttonStyle(ArcadeButtonStyle(color: Arcade.blue))
                        }

                        if hasResumableMatch {
                            Button {
                                if let saved = MatchSnapshotStore.load() {
                                    activeMatch = MatchController(resuming: saved)
                                } else {
                                    hasResumableMatch = false
                                }
                            } label: {
                                Text("Resume Match")
                            }
                            .buttonStyle(ArcadeButtonStyle(color: Arcade.blue))
                        }

                        // Pending Game Center challenge (docs/INVITE_FLOW.md):
                        // surfaced after auth sweeps invited matches — the
                        // landing pad for invite-to-install players.
                        if let invite = GameKitManager.shared.pendingInvites.first {
                            Button {
                                Haptics.impact(.medium)
                                GameKitManager.shared.acceptInvite(invite)
                            } label: {
                                Text("⚔ Challenge from \(Self.inviterName(invite))")
                            }
                            .buttonStyle(ArcadeButtonStyle(color: Arcade.gold, filled: true))
                        }

                        // Online play (Game Center): friend invites +
                        // async turn-based matches (docs/ONLINE_MULTIPLAYER.md M1).
                        Button {
                            if GameKitManager.shared.isAuthenticated {
                                GameKitManager.shared.presentMatchmaker()
                            } else {
                                GameKitManager.shared.authenticate()
                            }
                        } label: {
                            Text(GameKitManager.shared.isAuthenticated
                                 ? "Online · Invite a Friend"
                                 : "Online · Sign In")
                        }
                        .buttonStyle(ArcadeButtonStyle(color: Arcade.cream.opacity(
                            GameKitManager.shared.isAuthenticated ? 1.0 : 0.6)))

                        HStack(spacing: 10) {
                            NavigationLink {
                                HistoryView()
                            } label: {
                                Text("History")
                            }
                            .buttonStyle(ArcadeButtonStyle(color: Arcade.cream))

                            NavigationLink {
                                SettingsView()
                            } label: {
                                Text("Settings")
                            }
                            .buttonStyle(ArcadeButtonStyle(color: Arcade.cream))
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 14)

                    Text("© 2026 COMBAT CHESS")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Arcade.cream.opacity(0.4))
                        .padding(.vertical, 12)
                }
            }
            .fullScreenCover(item: $activeMatch) { controller in
                MatchView(controller: controller)
                    .onDisappear {
                        hasResumableMatch = MatchSnapshotStore.hasSnapshot
                    }
            }
            .onAppear {
                hasResumableMatch = MatchSnapshotStore.hasSnapshot
                // Game Center sign-in (idempotent; shows Apple's sheet if needed).
                GameKitManager.shared.authenticate()
                // Re-sweep invites + active matches when returning to the
                // title screen (the auth handler only fires once per launch).
                GameKitManager.shared.refreshMatches()
            }
        }
        // Online matches: opened by Game Center turn events. Attached to the
        // NavigationStack, NOT the inner content — SwiftUI allows only one
        // presentation modifier per view, and the offline cover lives inside.
        .fullScreenCover(item: Binding(
            get: { GameKitManager.shared.activeCoordinator },
            set: { GameKitManager.shared.activeCoordinator = $0 })) { coordinator in
            MatchView(controller: coordinator.controller)
        }
    }
}

extension MatchController: Identifiable {}
