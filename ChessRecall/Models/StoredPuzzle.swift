import Foundation

struct StoredPuzzle: Codable, Identifiable, Equatable {
    var id: String
    /// Board FEN at the puzzle start position (after initialPly moves from the game).
    var fen: String
    /// UCI moves; solution[0] is the first correct move the user must find.
    var solution: [String]
    var themes: [String]
    var rating: Int

    // MARK: - SRS state
    var easeFactor: Double = 2.5
    var interval: Double = 1.0
    var nextReviewDate: Date = Date()
    var totalAttempts: Int = 0
    var successCount: Int = 0

    /// The opponent's setup move in UCI notation (e.g. "d4c4"), used to highlight
    /// the last move on the board when the puzzle is presented.
    var lastMoveLAN: String?

    // MARK: - Derived helpers (not stored)
    var correctMoveLAN: String { solution[0] }

    var isDue: Bool { nextReviewDate <= Date() }

    var successRate: Double {
        guard totalAttempts > 0 else { return 0 }
        return Double(successCount) / Double(totalAttempts)
    }
}
