import SwiftUI
import SwiftData

/// Performance history (PRD §3.4): totals, per-difficulty breakdown, fight stats, match list.
struct HistoryView: View {
    @Query(sort: \MatchRecord.date, order: .reverse) private var matches: [MatchRecord]

    private var wins: Int { return matches.filter { $0.result == "win" }.count }
    private var losses: Int { return matches.filter { $0.result == "loss" }.count }
    private var draws: Int { return matches.filter { $0.result == "draw" }.count }

    private var winRate: String {
        guard !matches.isEmpty else { return "—" }
        let rate = Double(wins) / Double(matches.count) * 100
        return String(format: "%.0f%%", rate)
    }

    /// Current streak: consecutive same-result matches from the most recent.
    private var streak: String {
        guard let first = matches.first else { return "—" }
        var count = 0
        for m in matches {
            if m.result == first.result {
                count += 1
            } else {
                break
            }
        }
        let word = first.result == "win" ? "W" : first.result == "loss" ? "L" : "D"
        return "\(word)\(count)"
    }

    private var allFights: [FightRecord] {
        return matches.flatMap { $0.fights }
    }

    private var biggestUpset: Int {
        return allFights.map { $0.upsetDelta }.max() ?? 0
    }

    var body: some View {
        List {
            Section("Overall") {
                HStack {
                    statBox(value: String(matches.count), label: "Matches")
                    statBox(value: "\(wins)-\(losses)-\(draws)", label: "W-L-D")
                    statBox(value: winRate, label: "Win Rate")
                    statBox(value: streak, label: "Streak")
                }
            }

            Section("By Difficulty") {
                ForEach(Difficulty.allCases) { d in
                    let subset = matches.filter { $0.difficulty == d.rawValue }
                    let w = subset.filter { $0.result == "win" }.count
                    HStack {
                        Text(d.label)
                        Spacer()
                        Text(subset.isEmpty ? "No games" : "\(w)/\(subset.count) won")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Fights") {
                HStack {
                    statBox(value: String(allFights.count), label: "Total")
                    statBox(value: String(allFights.filter { $0.playerWon }.count), label: "Won")
                    statBox(value: biggestUpset > 0 ? "+\(biggestUpset)" : "—", label: "Biggest Upset")
                }
            }

            Section("Matches") {
                if matches.isEmpty {
                    Text("No matches yet. Go fight!")
                        .foregroundStyle(.secondary)
                }
                ForEach(matches) { match in
                    MatchRow(match: match)
                }
            }
        }
        .navigationTitle("History")
    }

    private func statBox(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MatchRow: View {
    let match: MatchRecord

    private var resultColor: Color {
        switch match.result {
        case "win": return .green
        case "loss": return .red
        default: return .gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(match.result.uppercased())
                    .font(.subheadline.bold())
                    .foregroundStyle(resultColor)
                Text("· \(match.difficulty.capitalized)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(match.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Label("\(match.moveCount / 2 + 1) moves", systemImage: "arrow.triangle.swap")
                Label("\(match.playerCardsUsed) cards", systemImage: "bolt.square")
                let fightsWon = match.fights.filter { $0.playerWon }.count
                Label("\(fightsWon)/\(match.fights.count) fights", systemImage: "figure.boxing")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !match.resultDetail.isEmpty {
                Text(match.resultDetail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
