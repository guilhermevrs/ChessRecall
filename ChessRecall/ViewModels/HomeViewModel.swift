import Foundation
import DatadogRUM
import DatadogLogs

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var duePuzzleCount: Int = 0
    @Published var totalPuzzleCount: Int = 0
    /// True only during the initial blocking fetch (first 5 puzzles).
    @Published var isLoading: Bool = false
    /// Progress text shown while fetching, e.g. "Fetching puzzles… 3 / 5"
    @Published var fetchProgressText: String? = nil
    @Published var errorMessage: String?

    private let store = PuzzleStore.shared
    private let api = LichessAPIService.shared

    private static let minToStart = 5      // fetch this many before enabling Start Training
    private static let targetTotal = 30    // background-fill up to this many

    // Bump this string whenever cached puzzle format changes — triggers a cache clear.
    private static let dataVersion = "v4-progressive-fetch"
    private static let dataVersionKey = "dataVersion"

    func onAppear() async {
        let loadKey = UUID().uuidString
        RUMMonitor.shared().startFeatureOperation(
            name: "home_data_load",
            operationKey: loadKey,
            attributes: [:]
        )

        await migrateIfNeeded()   // must run before refreshCounts to avoid showing stale data
        await refreshCounts()

        if errorMessage != nil {
            RUMMonitor.shared().failFeatureOperation(
                name: "home_data_load",
                operationKey: loadKey,
                reason: .error,
                attributes: ["error": errorMessage ?? "unknown"]
            )
        } else {
            RUMMonitor.shared().succeedFeatureOperation(
                name: "home_data_load",
                operationKey: loadKey,
                attributes: [
                    "due_count": duePuzzleCount,
                    "total_count": totalPuzzleCount
                ]
            )
        }

        RUMMonitor.shared().addViewAttribute(forKey: "cache.due_count", value: duePuzzleCount)
        RUMMonitor.shared().addViewAttribute(forKey: "cache.total_count", value: totalPuzzleCount)
        AppLogger.shared.info(
            "home.on_appear",
            attributes: ["due": duePuzzleCount, "total": totalPuzzleCount]
        )

        await fetchIfNeeded()
    }

    /// Clears the puzzle cache when the stored data version doesn't match the current one.
    /// Running this synchronously in onAppear ensures the clear completes before we read counts.
    private func migrateIfNeeded() async {
        guard UserDefaults.standard.string(forKey: Self.dataVersionKey) != Self.dataVersion else { return }
        AppLogger.shared.info("home.migration_started", attributes: ["new_version": Self.dataVersion])
        try? await store.clearAll()
        UserDefaults.standard.set(Self.dataVersion, forKey: Self.dataVersionKey)
    }

    func refreshCounts() async {
        do {
            let all = try await store.loadAll()
            totalPuzzleCount = all.count
            duePuzzleCount = all.filter { $0.isDue }.count
        } catch {
            AppLogger.shared.error("home.refresh_counts_failed", error: error)
            RUMMonitor.shared().addError(
                message: "PuzzleStore.loadAll failed",
                source: .source,
                attributes: ["error": error.localizedDescription]
            )
            errorMessage = "Could not load puzzles."
        }
    }

    private func fetchIfNeeded() async {
        let existing: Int
        do {
            existing = try await store.puzzleCount()
        } catch {
            AppLogger.shared.error("home.puzzle_count_failed", error: error)
            return
        }

        let needed = max(0, Self.targetTotal - existing)
        guard needed > 0 else {
            AppLogger.shared.info(
                "home.fetch_skipped",
                attributes: ["reason": "cache_full", "total": existing]
            )
            return
        }

        // ── Phase 1: fetch enough to start playing ──────────────────────────
        let phase1Count = min(Self.minToStart, needed)
        let phase1OpKey = UUID().uuidString
        isLoading = true
        var fetched = 0

        AppLogger.shared.info(
            "home.phase1_started",
            attributes: ["target": phase1Count, "existing": existing]
        )
        RUMMonitor.shared().startFeatureOperation(
            name: "lichess_phase1_fetch",
            operationKey: phase1OpKey,
            attributes: ["target": phase1Count]
        )

        for _ in 0..<phase1Count {
            fetchProgressText = "Fetching puzzles… \(existing + fetched + 1) / \(existing + phase1Count)"
            do {
                let puzzle = try await api.fetchPuzzle()
                do {
                    try await store.upsert(puzzle)
                    fetched += 1
                    await refreshCounts()
                } catch {
                    AppLogger.shared.error(
                        "home.phase1_upsert_failed",
                        error: error,
                        attributes: ["puzzle_id": puzzle.id]
                    )
                }
            } catch {
                AppLogger.shared.error("home.phase1_fetch_failed", error: error)
                RUMMonitor.shared().addError(
                    message: "Phase 1 Lichess fetch failed",
                    source: .network,
                    attributes: ["error": error.localizedDescription]
                )
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        if fetched == 0 {
            AppLogger.shared.error(
                "home.phase1_failed",
                attributes: ["fetched": 0, "target": phase1Count]
            )
            RUMMonitor.shared().failFeatureOperation(
                name: "lichess_phase1_fetch",
                operationKey: phase1OpKey,
                reason: .error,
                attributes: ["fetched": 0, "target": phase1Count]
            )
        } else {
            AppLogger.shared.info(
                "home.phase1_completed",
                attributes: ["fetched": fetched, "target": phase1Count]
            )
            RUMMonitor.shared().succeedFeatureOperation(
                name: "lichess_phase1_fetch",
                operationKey: phase1OpKey,
                attributes: ["fetched": fetched, "target": phase1Count]
            )
        }

        isLoading = false
        fetchProgressText = nil
        await refreshCounts()
        // Signal TTFD — app is fully usable with the first batch of puzzles loaded
        RUMMonitor.shared().reportAppFullyDisplayed()

        // ── Phase 2: fill the rest in the background (non-blocking) ─────────
        let remaining = needed - phase1Count
        guard remaining > 0 else { return }

        AppLogger.shared.info("home.phase2_started", attributes: ["target": remaining])
        Task { [weak self] in
            guard let self else { return }
            for _ in 0..<remaining {
                do {
                    let puzzle = try await self.api.fetchPuzzle()
                    do {
                        try await self.store.upsert(puzzle)
                        await self.refreshCounts()
                    } catch {
                        AppLogger.shared.error(
                            "home.phase2_upsert_failed",
                            error: error,
                            attributes: ["puzzle_id": puzzle.id]
                        )
                    }
                } catch {
                    AppLogger.shared.error("home.phase2_fetch_failed", error: error)
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }
}
