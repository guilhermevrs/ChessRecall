import XCTest
@testable import ChessRecall

/// Wraps actor calls so tests can use synchronous-style async/await.
final class PuzzleStoreTests: XCTestCase {

    private var testFileURL: URL!
    private var store: PuzzleStore!

    override func setUp() async throws {
        try await super.setUp()
        testFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_puzzles_\(UUID().uuidString).json")
        store = PuzzleStore(fileURL: testFileURL)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: testFileURL)
        try await super.tearDown()
    }

    private func makePuzzle(id: String, dueInDays: Int = 0) -> StoredPuzzle {
        let nextReview = Calendar.current.date(byAdding: .day, value: dueInDays, to: Date()) ?? Date()
        return StoredPuzzle(
            id: id,
            fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
            solution: ["e2e4"],
            themes: ["opening"],
            rating: 1500,
            nextReviewDate: nextReview
        )
    }

    // MARK: - Helper that bridges synchronous-throwing actor methods into async tests

    private func save(_ puzzles: [StoredPuzzle]) async throws {
        try await store.save(puzzles)
    }

    private func loadAll() async throws -> [StoredPuzzle] {
        try await store.loadAll()
    }

    private func upsert(_ puzzle: StoredPuzzle) async throws {
        try await store.upsert(puzzle)
    }

    private func duePuzzles() async throws -> [StoredPuzzle] {
        try await store.duePuzzles()
    }

    private func count() async throws -> Int {
        try await store.puzzleCount()
    }

    private func merge(_ puzzles: [StoredPuzzle]) async throws {
        try await store.mergeNew(puzzles)
    }

    private func clearAll() async throws {
        try await store.clearAll()
    }

    // MARK: - Tests

    func testSaveAndLoadAll() async throws {
        let puzzles = [makePuzzle(id: "a"), makePuzzle(id: "b"), makePuzzle(id: "c")]
        try await save(puzzles)
        let loaded = try await loadAll()
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(Set(loaded.map(\.id)), Set(["a", "b", "c"]))
    }

    func testLoadAllReturnsEmptyWhenNoFile() async throws {
        let loaded = try await loadAll()
        XCTAssertEqual(loaded.count, 0)
    }

    func testUpsertAddsNewPuzzle() async throws {
        try await upsert(makePuzzle(id: "new"))
        let c = try await count()
        XCTAssertEqual(c, 1)
    }

    func testUpsertUpdatesExistingPuzzle() async throws {
        var puzzle = makePuzzle(id: "x")
        try await upsert(puzzle)
        puzzle.successCount = 5
        try await upsert(puzzle)
        let loaded = try await loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.successCount, 5)
    }

    func testDuePuzzlesFiltersByDate() async throws {
        let due = makePuzzle(id: "due", dueInDays: -1)
        let future = makePuzzle(id: "future", dueInDays: 5)
        try await save([due, future])
        let result = try await duePuzzles()
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "due")
    }

    func testDuePuzzlesSortedByNextReviewDate() async throws {
        var older = makePuzzle(id: "older")
        older.nextReviewDate = Date().addingTimeInterval(-3600 * 24)
        var newer = makePuzzle(id: "newer")
        newer.nextReviewDate = Date().addingTimeInterval(-60)
        try await save([newer, older])
        let due = try await duePuzzles()
        XCTAssertEqual(due.first?.id, "older")
    }

    func testMergeNewSkipsDuplicates() async throws {
        try await save([makePuzzle(id: "dup")])
        try await merge([makePuzzle(id: "dup"), makePuzzle(id: "fresh")])
        let all = try await loadAll()
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.contains(where: { $0.id == "dup" }))
        XCTAssertTrue(all.contains(where: { $0.id == "fresh" }))
    }

    func testClearAll() async throws {
        try await save([makePuzzle(id: "z")])
        try await clearAll()
        let c = try await count()
        XCTAssertEqual(c, 0)
    }
}
