import SwiftUI

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
            // Online matches: opened by Game Center turn events.
            .fullScreenCover(item: Binding(
                get: { GameKitManager.shared.activeCoordinator },
                set: { GameKitManager.shared.activeCoordinator = $0 })) { coordinator in
                MatchView(controller: coordinator.controller)
            }
            .onAppear {
                hasResumableMatch = MatchSnapshotStore.hasSnapshot
                // Game Center sign-in (idempotent; shows Apple's sheet if needed).
                GameKitManager.shared.authenticate()
            }
        }
    }
}

extension MatchController: Identifiable {}
