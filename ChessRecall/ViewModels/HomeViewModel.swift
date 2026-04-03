import Foundation

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
        await migrateIfNeeded()   // must run before refreshCounts to avoid showing stale data
        await refreshCounts()
        await fetchIfNeeded()
    }

    /// Clears the puzzle cache when the stored data version doesn't match the current one.
    /// Running this synchronously in onAppear ensures the clear completes before we read counts.
    private func migrateIfNeeded() async {
        guard UserDefaults.standard.string(forKey: Self.dataVersionKey) != Self.dataVersion else { return }
        try? await store.clearAll()
        UserDefaults.standard.set(Self.dataVersion, forKey: Self.dataVersionKey)
    }

    func refreshCounts() async {
        do {
            let all = try await store.loadAll()
            totalPuzzleCount = all.count
            duePuzzleCount = all.filter { $0.isDue }.count
        } catch {
            errorMessage = "Could not load puzzles."
        }
    }

    private func fetchIfNeeded() async {
        let existing = (try? await store.puzzleCount()) ?? 0
        let needed = max(0, Self.targetTotal - existing)
        guard needed > 0 else { return }

        // ── Phase 1: fetch enough to start playing ──────────────────────────
        let phase1Count = min(Self.minToStart, needed)
        isLoading = true
        var fetched = 0

        for _ in 0..<phase1Count {
            fetchProgressText = "Fetching puzzles… \(existing + fetched + 1) / \(existing + phase1Count)"
            if let puzzle = try? await api.fetchPuzzle() {
                try? await store.upsert(puzzle)
                fetched += 1
                await refreshCounts()
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }

        isLoading = false
        fetchProgressText = nil
        await refreshCounts()

        // ── Phase 2: fill the rest in the background (non-blocking) ─────────
        let remaining = needed - phase1Count
        guard remaining > 0 else { return }

        Task { [weak self] in
            guard let self else { return }
            for _ in 0..<remaining {
                if let puzzle = try? await self.api.fetchPuzzle() {
                    try? await self.store.upsert(puzzle)
                    await self.refreshCounts()
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }
}
