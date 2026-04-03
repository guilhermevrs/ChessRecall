import XCTest
import ChessKit
@testable import ChessRecall

final class FENParsingMoveTests: XCTestCase {

    // Standard starting position FEN
    private let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    // After 1.e4
    private let afterE4FEN = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"

    // MARK: - FEN parsing

    func testParseStandardStartPosition() {
        guard let position = Position(fen: startFEN) else {
            XCTFail("Failed to parse standard starting FEN")
            return
        }
        XCTAssertEqual(position.sideToMove, .white)
    }

    func testInvalidFENReturnsNil() {
        let position = Position(fen: "not a valid fen")
        XCTAssertNil(position)
    }

    func testBoardHasCorrectPiecesAtStart() {
        guard let position = Position(fen: startFEN) else {
            XCTFail("Failed to parse FEN")
            return
        }
        let board = Board(position: position)
        // White king on e1
        let pieces = board.position.pieces.filter { $0.color == .white }
        let king = pieces.first { $0.kind == .king }
        XCTAssertNotNil(king)
        XCTAssertEqual(king?.square, Square("e1"))
    }

    // MARK: - Move application

    func testApplyLegalMoveChangesPosition() {
        guard let position = Position(fen: startFEN) else {
            XCTFail("Failed to parse FEN")
            return
        }
        var board = Board(position: position)
        let move = board.move(pieceAt: Square("e2"), to: Square("e4"))
        XCTAssertNotNil(move, "e2-e4 should be legal")
        XCTAssertEqual(board.position.sideToMove, .black)
    }

    func testApplyIllegalMoveReturnsNil() {
        guard let position = Position(fen: startFEN) else {
            XCTFail("Failed to parse FEN")
            return
        }
        var board = Board(position: position)
        // Moving e2 pawn to e5 (3 squares) is illegal
        let move = board.move(pieceAt: Square("e2"), to: Square("e5"))
        XCTAssertNil(move, "e2-e5 should be illegal")
    }

    func testLegalMovesFromStartIncludesE4() {
        guard let position = Position(fen: startFEN) else {
            XCTFail("Failed to parse FEN")
            return
        }
        let board = Board(position: position)
        let destinations = board.legalMoves(forPieceAt: Square("e2"))
        XCTAssertTrue(destinations.contains(Square("e4")), "e4 should be a legal destination from e2")
        XCTAssertTrue(destinations.contains(Square("e3")), "e3 should be a legal destination from e2")
    }

    // MARK: - UCI/LAN parsing

    func testEngineLANParserParsesE2E4() {
        guard let position = Position(fen: startFEN) else {
            XCTFail("Failed to parse FEN")
            return
        }
        let move = EngineLANParser.parse(move: "e2e4", for: .white, in: position)
        XCTAssertNotNil(move, "Should parse 'e2e4' as a valid move")
        XCTAssertEqual(move?.start, Square("e2"))
        XCTAssertEqual(move?.end, Square("e4"))
    }

    // MARK: - PuzzleViewModel choices include correct move

    @MainActor
    func testCorrectMoveAlwaysInChoices() {
        let viewModel = PuzzleViewModel()
        let puzzle = StoredPuzzle(
            id: "test-fork",
            fen: startFEN,
            solution: ["e2e4"],
            themes: ["opening"],
            rating: 1200
        )
        let session = viewModel.buildSession(for: puzzle)
        XCTAssertNotNil(session, "Should build a session for valid puzzle")
        let hasCorrect = session?.choices.contains(where: { $0.isCorrect }) ?? false
        XCTAssertTrue(hasCorrect, "Session choices must include the correct move")
    }

    @MainActor
    func testChoicesContainExactlyOneCorrectMove() {
        let viewModel = PuzzleViewModel()
        let puzzle = StoredPuzzle(
            id: "test",
            fen: startFEN,
            solution: ["e2e4"],
            themes: [],
            rating: 1000
        )
        let session = viewModel.buildSession(for: puzzle)
        let correctCount = session?.choices.filter { $0.isCorrect }.count ?? 0
        XCTAssertEqual(correctCount, 1, "Exactly one choice should be marked correct")
    }

    @MainActor
    func testChoicesAreAllLegalMoves() {
        guard let position = Position(fen: startFEN) else {
            XCTFail("Failed to parse FEN")
            return
        }
        let viewModel = PuzzleViewModel()
        let puzzle = StoredPuzzle(
            id: "test",
            fen: startFEN,
            solution: ["e2e4"],
            themes: [],
            rating: 1000
        )
        guard let session = viewModel.buildSession(for: puzzle) else {
            XCTFail("Should build session")
            return
        }

        // All choices must be parseable as legal moves
        for choice in session.choices {
            let move = EngineLANParser.parse(move: choice.lan, for: .white, in: position)
            XCTAssertNotNil(move, "Choice '\(choice.san)' (LAN: \(choice.lan)) should be a valid move")
        }
    }
}
