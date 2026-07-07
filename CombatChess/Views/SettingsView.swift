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

/// GPLv3 "Appropriate Legal Notices" (license §5d) + third-party credits.
struct LicensesView: View {
    /// Public repository hosting the app's Corresponding Source (GPLv3 §6d).
    static let sourceURL = "https://github.com/jparekh117/combat-chess"

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
                Text("Copyright © 2026 Jigesh Parekh.\n\nThis program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License v3 as published by the Free Software Foundation. It is distributed WITHOUT ANY WARRANTY; see the license for details.")
                    .font(.footnote)
                if let url = URL(string: Self.sourceURL) {
                    Link("Get the source code", destination: url)
                }
            }
            Section("Chess Engine") {
                Text("Stockfish 17 — Copyright © the Stockfish developers. Licensed under the GNU General Public License v3. Includes NNUE evaluation networks from the Stockfish project.")
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
