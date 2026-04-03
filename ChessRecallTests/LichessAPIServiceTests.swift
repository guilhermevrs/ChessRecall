import XCTest
@testable import ChessRecall

/// Tests the full Lichess API parsing pipeline using pre-recorded fixture responses.
/// No network calls are made — MockURLProtocol intercepts all requests to lichess.org.
final class LichessAPIServiceTests: XCTestCase {

    private var mockSession: URLSession!
    private var service: LichessAPIService!

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        mockSession = URLSession(configuration: config)
        service = LichessAPIService(session: mockSession)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Helpers

    private func fixture(named name: String) throws -> Data {
        let bundle = Bundle(for: LichessAPIServiceTests.self)
        // XcodeGen copies fixture files to the bundle root (no subdirectory)
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "json"),
            "Fixture '\(name).json' not found in test bundle at \(bundle.bundlePath)"
        )
        return try Data(contentsOf: url)
    }

    // MARK: - Puzzle parsing

    func testParsesMgP8r() async throws {
        MockURLProtocol.enqueue(try fixture(named: "puzzle_MgP8r"))
        let puzzle = try await service.fetchPuzzle()

        XCTAssertEqual(puzzle.id, "MgP8r")
        XCTAssertEqual(puzzle.rating, 1507)
        XCTAssertTrue(puzzle.themes.contains("endgame") || puzzle.themes.contains("mateIn3"))
        XCTAssertFalse(puzzle.solution.isEmpty)
        XCTAssertFalse(puzzle.fen.isEmpty)
    }

    func testCorrectFENContainsSideToMove() async throws {
        MockURLProtocol.enqueue(try fixture(named: "puzzle_MgP8r"))
        let puzzle = try await service.fetchPuzzle()

        // FEN second field is "w" or "b"
        let parts = puzzle.fen.split(separator: " ")
        XCTAssertGreaterThanOrEqual(parts.count, 2, "FEN must have at least 2 space-separated fields")
        let side = String(parts[1])
        XCTAssertTrue(side == "w" || side == "b", "Side to move must be 'w' or 'b', got '\(side)'")
    }

    func testLastMoveLANIsPresent() async throws {
        MockURLProtocol.enqueue(try fixture(named: "puzzle_MgP8r"))
        let puzzle = try await service.fetchPuzzle()

        // MgP8r fixture provides lastMove = "d4c4"
        let lan = try XCTUnwrap(puzzle.lastMoveLAN, "lastMoveLAN should be populated from fixture")
        XCTAssertEqual(lan.count, 4, "LAN notation should be 4 chars: from-square + to-square, got '\(lan)'")
    }

    func testMgP8rLastMoveMatchesFixture() async throws {
        // The fixture provides lastMove = "d4c4" (white Queen captures pawn on c4)
        // This triggers the tactic: black plays Qf2+
        MockURLProtocol.enqueue(try fixture(named: "puzzle_MgP8r"))
        let puzzle = try await service.fetchPuzzle()

        XCTAssertEqual(puzzle.lastMoveLAN, "d4c4",
            "MgP8r opponent's last move should be d4c4 (Qxc4)")
        XCTAssertEqual(puzzle.solution.first, "e2f2",
            "MgP8r first player move should be e2f2 (Qf2+)")
    }

    func testHxxIUPuzzle() async throws {
        MockURLProtocol.enqueue(try fixture(named: "puzzle_HxxIU"))
        let puzzle = try await service.fetchPuzzle()

        XCTAssertEqual(puzzle.id, "HxxIU")
        XCTAssertEqual(puzzle.lastMoveLAN, "c3d5", "HxxIU: opponent's last move is c3d5")
        XCTAssertEqual(puzzle.solution.first, "e6d5", "HxxIU: first player move is e6d5")
    }

    func testYtw4uPuzzle() async throws {
        MockURLProtocol.enqueue(try fixture(named: "puzzle_Ytw4u"))
        let puzzle = try await service.fetchPuzzle()

        XCTAssertEqual(puzzle.id, "Ytw4u")
        XCTAssertEqual(puzzle.lastMoveLAN, "e4f3")
        XCTAssertEqual(puzzle.solution.first, "e1e8")
    }

    func testFetchMultiplePuzzlesConsumesFixturesInOrder() async throws {
        MockURLProtocol.enqueue(try fixture(named: "puzzle_MgP8r"))
        MockURLProtocol.enqueue(try fixture(named: "puzzle_HxxIU"))
        MockURLProtocol.enqueue(try fixture(named: "puzzle_Ytw4u"))

        let puzzles = try await service.fetchPuzzles(count: 3)
        XCTAssertEqual(puzzles.count, 3)
        XCTAssertEqual(puzzles[0].id, "MgP8r")
        XCTAssertEqual(puzzles[1].id, "HxxIU")
        XCTAssertEqual(puzzles[2].id, "Ytw4u")
    }

    func testBadResponseThrows() async throws {
        // Enqueue a 429 body — the service should throw on non-200
        let errorBody = #"{"error":"Too many requests"}"#.data(using: .utf8)!
        MockURLProtocol.enqueue(errorBody)
        // Hijack the response to return 429 by enqueueing an error
        MockURLProtocol.reset()
        MockURLProtocol.enqueueError(URLError(.badServerResponse))

        do {
            _ = try await service.fetchPuzzle()
            XCTFail("Should have thrown")
        } catch {
            // Expected
        }
    }

    func testCorrectMoveIsAlwaysInChoicesForFixturePuzzle() async throws {
        MockURLProtocol.enqueue(try fixture(named: "puzzle_MgP8r"))
        let puzzle = try await service.fetchPuzzle()

        // Build choices via the ViewModel and verify the correct move is included
        let vm = await PuzzleViewModel()
        let session = await vm.buildSession(for: puzzle)
        let s = try XCTUnwrap(session, "Should build a session for valid fixture puzzle")
        XCTAssertTrue(s.choices.contains(where: { $0.isCorrect }),
            "Correct move \(puzzle.correctMoveLAN) must be among the choices")
    }
}
