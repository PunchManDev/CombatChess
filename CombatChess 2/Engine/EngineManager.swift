import Foundation
import ChessKitEngine

/// Stockfish 17 via the MIT-licensed ChessKitEngine package.
///
/// Requires two NNUE network files in the app bundle (see README §Engine).
/// If Stockfish can't start or the networks are missing, callers get `nil`
/// and `MatchController` falls back to the native minimax engine, so the
/// app remains fully playable either way.
actor EngineManager {
    static let shared = EngineManager()

    private var engine: Engine?
    private var streamTask: Task<Void, Never>?
    private var bestMoveContinuation: CheckedContinuation<String?, Never>?
    /// Flips false permanently on a failed start so we don't retry each move.
    private var available = true

    // MARK: - Public API

    /// Pre-starts the engine (NNUE load takes a moment); call at match start
    /// so the first AI move doesn't pay the startup cost.
    func warmUp() async {
        _ = await startIfNeeded()
    }

    /// Best move in UCI notation ("e2e4", "e7e8q"), or nil if Stockfish is
    /// unavailable (caller should use the native engine instead).
    func bestMove(fen: String, difficulty: Difficulty) async -> String? {
        guard await startIfNeeded(), let engine = engine else { return nil }

        // User-tuned Elo gradient (Settings). Stockfish's UCI_Elo floor is
        // 1320; below that we approximate with low Skill Level + shallow depth.
        let elo = difficulty.configuredElo
        if elo >= 1320 {
            await engine.send(command: .setoption(id: "UCI_LimitStrength", value: "true"))
            await engine.send(command: .setoption(id: "UCI_Elo", value: String(elo)))
            await engine.send(command: .setoption(id: "Skill Level", value: "20"))
        } else {
            await engine.send(command: .setoption(id: "UCI_LimitStrength", value: "false"))
            let skill = max(0, min(8, (elo - 600) / 110))
            await engine.send(command: .setoption(id: "Skill Level", value: String(skill)))
        }

        // Depth scales with Elo, but movetime is the hard wall-clock cap —
        // Elo limiting changes *how well* the engine plays, not how long it
        // thinks, so without movetime, deep searches can stall the match.
        let depth = max(3, min(18, elo / 170))
        let movetimeMs = 300 + elo * 35 / 100        // ~0.5s easy → ~1.4s max

        await engine.send(command: .position(.fen(fen)))
        await engine.send(command: .go(depth: depth, movetime: movetimeMs))

        let move: String? = await withCheckedContinuation { continuation in
            bestMoveContinuation = continuation
            // Safety timeout: never hang the match on the engine.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await self?.timeoutBestMove()
            }
        }
        return move
    }

    // MARK: - Lifecycle

    private func startIfNeeded() async -> Bool {
        guard available else { return false }
        if engine != nil { return true }

        // Stockfish 17 requires NNUE evaluation networks; without them it
        // cannot evaluate positions, so fall back to the native engine.
        let networks = bundledNetworkPaths()
        guard let bigNet = networks.first else {
            available = false
            return false
        }

        let engine = Engine(type: .stockfish)
        self.engine = engine
        // Explicit core count: the package's default resolves to a single
        // thread, which makes searches far slower than the device allows.
        await engine.start(coreCount: ProcessInfo.processInfo.processorCount)

        // Wait for the setup handshake (readyok flips isRunning).
        var running = false
        for _ in 0..<50 {
            if await engine.isRunning {
                running = true
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard running else {
            available = false
            self.engine = nil
            return false
        }

        await engine.send(command: .setoption(id: "EvalFile", value: bigNet))
        if networks.count > 1, let smallNet = networks.last {
            await engine.send(command: .setoption(id: "EvalFileSmall", value: smallNet))
        }

        // Consume the response stream; bestmove lines resolve pending waits.
        if let stream = await engine.responseStream {
            streamTask = Task { [weak self] in
                for await response in stream {
                    await self?.handleResponse(response.rawValue)
                }
            }
        }
        return true
    }

    /// Bundled .nnue files sorted big → small (EvalFile wants the large net).
    private func bundledNetworkPaths() -> [String] {
        let paths = Bundle.main.paths(forResourcesOfType: "nnue", inDirectory: nil)
        func size(_ path: String) -> Int {
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            return (attrs?[.size] as? NSNumber)?.intValue ?? 0
        }
        return paths.sorted { size($0) > size($1) }
    }

    // MARK: - Responses

    private func handleResponse(_ raw: String) {
        guard raw.hasPrefix("bestmove") else { return }
        let parts = raw.split(separator: " ")
        let move = parts.count > 1 ? String(parts[1]) : nil
        resumeBestMove(with: move == "(none)" ? nil : move)
    }

    private func timeoutBestMove() async {
        guard bestMoveContinuation != nil else { return }
        await engine?.send(command: .stop)
        resumeBestMove(with: nil)
    }

    private func resumeBestMove(with value: String?) {
        guard let continuation = bestMoveContinuation else { return }
        bestMoveContinuation = nil
        continuation.resume(returning: value)
    }
}

