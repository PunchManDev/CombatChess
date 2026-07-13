import SwiftUI

/// Settings (PRD §3.1): sound, haptics, default difficulty, CPU Elo tuning.
struct SettingsView: View {
    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("defaultDifficulty") private var defaultDifficulty = Difficulty.medium.rawValue

    var body: some View {
        Form {
            Section("Feedback") {
                Toggle("Sound Effects", isOn: $soundEnabled)
                Toggle("Haptics", isOn: $hapticsEnabled)
            }
            Section("Gameplay") {
                Picker("Default Difficulty", selection: $defaultDifficulty) {
                    ForEach(Difficulty.allCases) { d in
                        Text(d.label).tag(d.rawValue)
                    }
                }
            }
            Section {
                ForEach(Difficulty.allCases) { d in
                    EloSliderRow(difficulty: d)
                }
                Button("Reset to Defaults", role: .destructive) {
                    for d in Difficulty.allCases {
                        UserDefaults.standard.removeObject(forKey: d.eloKey)
                    }
                }
            } header: {
                Text("CPU Strength (Elo)")
            } footer: {
                Text("Each difficulty maps to a Stockfish rating you can tune. Below 1320 Elo the engine plays with intentionally limited skill and shallow search; above it, strength is Elo-calibrated up to 3190 (superhuman).")
            }
            Section {
                LabeledContent("Version", value: "1.0")
                LabeledContent("Action cards per match", value: "3")
                NavigationLink("Privacy Policy") {
                    PrivacyPolicyView()
                }
                NavigationLink("Open Source & Licenses") {
                    LicensesView()
                }
            } footer: {
                Text("Combat Chess V1 — chess with SF2-style piece fights. Capture a piece and your opponent may challenge it; damage persists for the whole match.")
            }
        }
        .navigationTitle("Settings")
    }
}

/// In-app privacy policy. App Store Review Guideline 5.1.1(i) requires the
/// policy to be reachable from within the app, not only from the App Store
/// listing — so the full text is bundled here rather than merely linked.
struct PrivacyPolicyView: View {
    /// Canonical hosted copy (App Store Connect needs this URL too).
    static let policyURL = "https://github.com/PunchManDev/CombatChess/blob/main/PRIVACY.md"

    var body: some View {
        List {
            Section {
                Text("Combat Chess does not collect, store, or share any personal data. There is no analytics, no advertising, no tracking, and no account with us. The developer operates no server.")
                    .font(.subheadline)
            }
            Section("Stored on your device only") {
                Text("Your saved game, match history, and settings live on your device and never leave it. Notification reminders for online matches are scheduled locally. Deleting the app deletes all of it.")
                    .font(.footnote)
            }
            Section("Game Center (only if you play online)") {
                Text("Online multiplayer uses Apple's Game Center. If you play online, your Game Center nickname and your moves travel through Apple's servers to reach your opponent — that's inherent to playing a match. The developer receives none of it and has no access to it. Apple's handling of that data is governed by Apple's privacy policy.")
                    .font(.footnote)
                if let url = URL(string: "https://www.apple.com/legal/privacy/") {
                    Link("Apple's Privacy Policy", destination: url)
                }
                Text("If you never play online, no data leaves your device at all.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("What we don't do") {
                Text("• No personal information collected\n• No analytics or crash-reporting SDKs\n• No ads\n• No cross-app or cross-site tracking\n• No selling or sharing data with third parties")
                    .font(.footnote)
            }
            Section {
                Text("Combat Chess is open source (GPL v3) — you can read the code and verify every claim on this page.")
                    .font(.footnote)
                if let url = URL(string: Self.policyURL) {
                    Link("View this policy online", destination: url)
                }
                if let url = URL(string: "https://github.com/PunchManDev/CombatChess") {
                    Link("Source code", destination: url)
                }
            }
        }
        .navigationTitle("Privacy Policy")
    }
}

/// GPLv3 "Appropriate Legal Notices" (license §5d) + third-party credits.
struct LicensesView: View {
    /// Public repository hosting the app's Corresponding Source (GPLv3 §6d).
    static let sourceURL = "https://github.com/PunchManDev/CombatChess"

    private var gplText: String {
        guard let url = Bundle.main.url(forResource: "gpl-3.0", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "See https://www.gnu.org/licenses/gpl-3.0.html"
        }
        return text
    }

    var body: some View {
        List {
            Section("Combat Chess") {
                Text("Copyright © 2026 PunchMan LLC.\n\nThis program is free software under the terms of the GNU General Public License v3 as published by the Free Software Foundation. It is distributed WITHOUT ANY WARRANTY.")
                    .font(.footnote)
                if let url = URL(string: Self.sourceURL) {
                    Link("Get the source code", destination: url)
                }
            }
            Section("Chess Engine") {
                Text("Stockfish 17 — Copyright ©Stockfish . Licensed under the GNU General Public License v3. Includes NNUE evaluation networks from the Stockfish project.")
                    .font(.footnote)
                if let url = URL(string: "https://stockfishchess.org") {
                    Link("stockfishchess.org", destination: url)
                }
            }
            Section("Libraries") {
                Text("ChessKitEngine — Copyright © chesskit-app contributors. Licensed under the MIT License.")
                    .font(.footnote)
            }
            Section("GNU General Public License v3") {
                Text(gplText)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Licenses")
    }
}

/// Slider tuning one difficulty tier's Elo within its band.
struct EloSliderRow: View {
    let difficulty: Difficulty
    @AppStorage private var elo: Double

    init(difficulty: Difficulty) {
        self.difficulty = difficulty
        _elo = AppStorage(wrappedValue: 0, difficulty.eloKey)
    }

    private var displayElo: Double {
        return elo == 0 ? difficulty.defaultElo : elo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(difficulty.label)
                    .font(.headline)
                Spacer()
                Text("\(Int(displayElo)) ELO")
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { displayElo },
                                  set: { elo = $0 }),
                   in: difficulty.eloRange,
                   step: 25)
            HStack {
                Text("\(Int(difficulty.eloRange.lowerBound))")
                Spacer()
                Text("\(Int(difficulty.eloRange.upperBound))")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
