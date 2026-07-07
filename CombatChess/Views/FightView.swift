import SwiftUI
import SpriteKit

/// Fight screen wrapper (PRD §3.3): SF-style VS splash → pixel fight → result hand-off.
struct FightView: View {
    let setup: FightSetup
    let onResult: (FightResult) -> Void

    @State private var showSplash = true
    @State private var isPaused = false
    @State private var scene: FightScene?

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.07, blue: 0.12).ignoresSafeArea()

            if let scene = scene, !showSplash {
                SpriteView(scene: scene)
                    .ignoresSafeArea()
            }

            if showSplash {
                splash
            }

            if !showSplash {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            isPaused.toggle()
                            scene?.isPaused = isPaused
                        } label: {
                            Image(systemName: isPaused ? "play.square.fill" : "pause.square.fill")
                                .font(.title)
                                .foregroundStyle(Arcade.cream.opacity(0.6))
                        }
                        .padding(.trailing, 14)
                    }
                    Spacer()
                }
                .padding(.top, 4)
            }

            // Pause cover hides the arena so the foe's attack state can't be studied (PRD §3.3).
            if isPaused {
                ZStack {
                    Color.black.opacity(0.97).ignoresSafeArea()
                    VStack(spacing: 18) {
                        Text("PAUSED")
                            .font(.system(.largeTitle, design: .monospaced).weight(.heavy))
                            .foregroundStyle(Arcade.gold)
                        Button {
                            isPaused = false
                            scene?.isPaused = false
                        } label: {
                            Text("Resume")
                        }
                        .buttonStyle(ArcadeButtonStyle(color: Arcade.gold))
                        .frame(width: 200)
                    }
                }
            }
        }
        .onAppear {
            let newScene = FightScene(size: UIScreen.main.bounds.size, setup: setup) { result in
                DispatchQueue.main.async {
                    onResult(result)
                }
            }
            scene = newScene
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                withAnimation { showSplash = false }
            }
        }
    }

    // MARK: - VS splash

    private var splash: some View {
        ZStack {
            PixelImage(setup.difficulty.stageBackground)
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.55).ignoresSafeArea())

            VStack(spacing: 24) {
                Text(setup.difficulty.stageName)
                    .font(.system(.caption, design: .monospaced).weight(.heavy))
                    .foregroundStyle(Arcade.cream.opacity(0.7))
                    .padding(.top, 30)

                HStack(spacing: 4) {
                    splashCard(piece: setup.playerPiece, team: setup.playerPiece.color.teamName,
                               label: "YOU", color: Arcade.blue)
                    PixelImage("text_vs")
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 70)
                    splashCard(piece: setup.aiPiece, team: setup.aiPiece.color.teamName,
                               label: "FOE", color: Arcade.red, mirrored: true)
                }

                Text(splashTagline)
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(setup.isCheckFight ? Arcade.red : Arcade.gold)

                VStack(spacing: 3) {
                    Text("L/R PUNCH · HOLD L/R BLOCK · TIMED DODGE NEGATES ALL")
                    Text("EVERY ACTION DRAINS STAMINA — EXHAUSTED FIGHTERS TAKE 1.5×")
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Arcade.cream.opacity(0.6))

                Button {
                    withAnimation { showSplash = false }
                } label: {
                    Text("Fight!")
                }
                .buttonStyle(ArcadeButtonStyle(color: Arcade.red))
                .frame(width: 180)
                .padding(.bottom, 30)
            }
        }
        .onTapGesture {
            withAnimation { showSplash = false }
        }
    }

    private var splashTagline: String {
        if setup.isCheckFight {
            return setup.playerIsAttacker
                ? "SLAY THE ENEMY KING TO WIN THE GAME"
                : "YOUR KING FIGHTS FOR HIS LIFE"
        }
        return setup.playerIsAttacker
            ? "WIN TO COMPLETE YOUR CAPTURE"
            : "WIN TO REPEL THE ATTACK"
    }

    private func splashCard(piece: Piece, team: String, label: String,
                            color: Color, mirrored: Bool = false) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(.caption, design: .monospaced).weight(.heavy))
                .foregroundStyle(color)
            PixelImage(piece.type.fighterAsset(team: team, frame: "idle_a"))
                .aspectRatio(contentMode: .fit)
                .frame(height: 110)
                .scaleEffect(x: mirrored ? -1 : 1)
            Text(piece.type.displayName.uppercased())
                .font(.system(.footnote, design: .monospaced).weight(.heavy))
                .foregroundStyle(Arcade.cream)
            Text("HP \(piece.currentHP)/\(piece.maxHP)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(piece.hpFraction > 0.5 ? .green : piece.hpFraction > 0.25 ? .yellow : .red)
            Text("JAB \(piece.type.jabDamage)·HVY \(piece.type.heavyDamage)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Arcade.cream.opacity(0.6))
        }
        .frame(width: 130)
        .padding(.vertical, 14)
        .arcadePanel(border: color)
    }
}
