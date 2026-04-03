import Foundation

enum Difficulty {
    case easy, hard, wrong
}

/// Pure, stateless spaced repetition logic. No I/O.
struct SpacedRepetitionService {

    /// Apply SM-2-inspired SRS update. Returns a new puzzle with updated state.
    static func update(puzzle: StoredPuzzle, difficulty: Difficulty) -> StoredPuzzle {
        var p = puzzle
        p.totalAttempts += 1

        switch difficulty {
        case .easy:
            p.interval = max(1.0, p.interval * 2.5)
            p.successCount += 1
        case .hard:
            p.interval = max(1.0, p.interval * 1.5)
            p.successCount += 1
        case .wrong:
            p.interval = 1.0
            // successCount unchanged on wrong
        }

        // Clamp to [1, 365] days
        p.interval = min(p.interval, 365.0)

        p.nextReviewDate = Calendar.current.date(
            byAdding: .day,
            value: Int(p.interval.rounded()),
            to: Date()
        ) ?? Date()

        return p
    }
}
