import DatadogLogs
import DatadogRUM

/// Module-level structured logger. All subsystems write through this.
/// Initialized eagerly in ChessRecallApp.init() after Logs.enable().
enum AppLogger {
    static let shared: LoggerProtocol = Logger.create(
        with: Logger.Configuration(
            name: "chess-recall",
            networkInfoEnabled: true,
            remoteLogThreshold: .info
        )
    )
}

/// SwiftUI view predicate that only tracks the three top-level navigation views,
/// preserving the same short names ("Home", "Puzzle", "Stats") used previously
/// with the manual `.trackRUMView()` modifier.
class ChessRecallViewsPredicate: SwiftUIRUMViewsPredicate {
    private static let trackedViews: [String: String] = [
        "HomeView":   "Home",
        "PuzzleView": "Puzzle",
        "StatsView":  "Stats"
    ]

    func rumView(for extractedViewName: String) -> RUMView? {
        guard let name = Self.trackedViews[extractedViewName] else { return nil }
        return RUMView(name: name)
    }
}
