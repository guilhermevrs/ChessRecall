import Foundation

struct ThemeStat: Identifiable {
    var id: String { theme }
    let theme: String
    let successRate: Double
    let totalAttempts: Int
}

@MainActor
final class StatsViewModel: ObservableObject {
    @Published var totalSolved: Int = 0
    @Published var overallSuccessRate: Double = 0
    @Published var themeStats: [ThemeStat] = []
    @Published var isLoading: Bool = false

    private let store = PuzzleStore.shared

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let puzzles = try await store.loadAll()
            let attempted = puzzles.filter { $0.totalAttempts > 0 }
            totalSolved = attempted.count

            let totalAttempts = attempted.reduce(0) { $0 + $1.totalAttempts }
            let totalSuccess = attempted.reduce(0) { $0 + $1.successCount }
            overallSuccessRate = totalAttempts > 0 ? Double(totalSuccess) / Double(totalAttempts) : 0

            // Aggregate stats per theme
            var themeMap: [String: (success: Int, attempts: Int)] = [:]
            for puzzle in attempted {
                for theme in puzzle.themes {
                    var entry = themeMap[theme, default: (0, 0)]
                    entry.success += puzzle.successCount
                    entry.attempts += puzzle.totalAttempts
                    themeMap[theme] = entry
                }
            }

            themeStats = themeMap
                .map { theme, counts in
                    ThemeStat(
                        theme: theme,
                        successRate: counts.attempts > 0 ? Double(counts.success) / Double(counts.attempts) : 0,
                        totalAttempts: counts.attempts
                    )
                }
                .sorted { $0.totalAttempts > $1.totalAttempts }
        } catch {
            // Leave displayed values as-is on error
        }
    }
}
