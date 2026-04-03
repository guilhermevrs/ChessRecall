import XCTest
@testable import ChessRecall

final class SpacedRepetitionTests: XCTestCase {

    private func makePuzzle(interval: Double = 1.0, successCount: Int = 0, totalAttempts: Int = 0) -> StoredPuzzle {
        StoredPuzzle(
            id: "test",
            fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            solution: ["e2e4"],
            themes: ["opening"],
            rating: 1500,
            easeFactor: 2.5,
            interval: interval,
            nextReviewDate: Date(),
            totalAttempts: totalAttempts,
            successCount: successCount
        )
    }

    func testEasyMultipliesIntervalBy2_5() {
        let puzzle = makePuzzle(interval: 2.0)
        let updated = SpacedRepetitionService.update(puzzle: puzzle, difficulty: .easy)
        XCTAssertEqual(updated.interval, 5.0, accuracy: 0.001)
    }

    func testHardMultipliesIntervalBy1_5() {
        let puzzle = makePuzzle(interval: 2.0)
        let updated = SpacedRepetitionService.update(puzzle: puzzle, difficulty: .hard)
        XCTAssertEqual(updated.interval, 3.0, accuracy: 0.001)
    }

    func testWrongResetsIntervalTo1() {
        let puzzle = makePuzzle(interval: 10.0)
        let updated = SpacedRepetitionService.update(puzzle: puzzle, difficulty: .wrong)
        XCTAssertEqual(updated.interval, 1.0, accuracy: 0.001)
    }

    func testEasyIncrementsSuccessCount() {
        let puzzle = makePuzzle(successCount: 3, totalAttempts: 5)
        let updated = SpacedRepetitionService.update(puzzle: puzzle, difficulty: .easy)
        XCTAssertEqual(updated.successCount, 4)
        XCTAssertEqual(updated.totalAttempts, 6)
    }

    func testWrongDoesNotIncrementSuccessCount() {
        let puzzle = makePuzzle(successCount: 3, totalAttempts: 5)
        let updated = SpacedRepetitionService.update(puzzle: puzzle, difficulty: .wrong)
        XCTAssertEqual(updated.successCount, 3)
        XCTAssertEqual(updated.totalAttempts, 6)
    }

    func testIntervalClampsAt365() {
        let puzzle = makePuzzle(interval: 300.0)
        let updated = SpacedRepetitionService.update(puzzle: puzzle, difficulty: .easy)
        XCTAssertLessThanOrEqual(updated.interval, 365.0)
    }

    func testIntervalNeverBelowOne() {
        // Even if somehow interval is 0.1, easy should clamp to >= 1
        let puzzle = makePuzzle(interval: 0.1)
        let updated = SpacedRepetitionService.update(puzzle: puzzle, difficulty: .easy)
        XCTAssertGreaterThanOrEqual(updated.interval, 1.0)
    }

    func testNextReviewDateIsInFuture() {
        let puzzle = makePuzzle(interval: 1.0)
        let updated = SpacedRepetitionService.update(puzzle: puzzle, difficulty: .easy)
        XCTAssertGreaterThan(updated.nextReviewDate, Date())
    }

    func testHardIncrementsTotalAttempts() {
        let puzzle = makePuzzle(totalAttempts: 0)
        let updated = SpacedRepetitionService.update(puzzle: puzzle, difficulty: .hard)
        XCTAssertEqual(updated.totalAttempts, 1)
        XCTAssertEqual(updated.successCount, 1)
    }
}
