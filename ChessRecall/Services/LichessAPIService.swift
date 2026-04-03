import Foundation
import ChessKit

/// Fetches puzzles from the Lichess public API and reconstructs puzzle FEN from PGN.
actor LichessAPIService {
    static let shared = LichessAPIService()

    private let session: URLSession

    /// Designated initializer — pass a custom URLSession for unit testing.
    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15
            #if DEBUG
            // Inject the mock protocol when running under UI tests
            if ProcessInfo.processInfo.environment["MOCK_LICHESS"] == "1" {
                config.protocolClasses = [MockLichessProtocol.self]
            }
            #endif
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Public API

    func fetchPuzzle() async throws -> StoredPuzzle {
        let url = URL(string: "https://lichess.org/api/puzzle/next")!
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.badResponse
        }

        let raw = try JSONDecoder().decode(LichessResponse.self, from: data)
        return try buildStoredPuzzle(from: raw)
    }

    /// Fetches `count` puzzles with a short delay between requests to be polite.
    func fetchPuzzles(count: Int) async throws -> [StoredPuzzle] {
        var results: [StoredPuzzle] = []
        for _ in 0..<count {
            if let puzzle = try? await fetchPuzzle() {
                results.append(puzzle)
            }
            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms
        }
        return results
    }

    // MARK: - Private

    private func buildStoredPuzzle(from response: LichessResponse) throws -> StoredPuzzle {
        let puzzle = response.puzzle

        // Use fen + lastMove from the API response when present (no PGN replay needed).
        // Fall back to PGN replay for endpoints that omit these fields.
        let fen: String
        let lastMoveLAN: String?

        if let apiFen = puzzle.fen, !apiFen.isEmpty {
            fen = apiFen
            lastMoveLAN = puzzle.lastMove
        } else {
            (fen, lastMoveLAN) = try fenFromPGN(response.game.pgn, upToHalfMove: puzzle.initialPly)
        }

        return StoredPuzzle(
            id: puzzle.id,
            fen: fen,
            solution: puzzle.solution,
            themes: puzzle.themes,
            rating: puzzle.rating,
            lastMoveLAN: lastMoveLAN
        )
    }

    /// Replays PGN SAN moves through index `ply` (inclusive) and returns the resulting FEN
    /// plus the LAN notation of the last move applied (the opponent's setup move).
    ///
    /// `initialPly` from the Lichess API is the 0-based index of the last pre-puzzle move
    /// (the opponent's setup move). We apply all tokens 0...ply so the resulting position
    /// is the player's turn, matching solution[0].
    private func fenFromPGN(_ pgn: String, upToHalfMove ply: Int) throws -> (fen: String, lastMoveLAN: String?) {
        let sanTokens = parsePGNMoves(pgn)
        var board = Board()
        var lastMoveLAN: String?

        for (index, san) in sanTokens.enumerated() {
            guard index <= ply else { break }
            if let move = applyMoveReturning(san: san, to: &board) {
                if index == ply {
                    lastMoveLAN = move.lan
                }
            }
        }

        return (board.position.fen, lastMoveLAN)
    }

    /// Applies the SAN move to the board and returns the resulting `Move`, or nil if not found.
    private func applyMoveReturning(san: String, to board: inout Board) -> Move? {
        let sideToMove = board.position.sideToMove
        let pieces = board.position.pieces.filter { $0.color == sideToMove }
        for piece in pieces {
            let destinations = board.legalMoves(forPieceAt: piece.square)
            for dest in destinations {
                var testBoard = board
                if let move = testBoard.move(pieceAt: piece.square, to: dest), move.san == san {
                    board.move(pieceAt: piece.square, to: dest)
                    return move
                }
            }
        }
        return nil
    }

    /// Attempts to find and apply the legal move matching the given SAN token.
    /// Returns true if a move was applied.
    @discardableResult
    private func applyMove(san: String, to board: inout Board) -> Bool {
        let sideToMove = board.position.sideToMove
        let pieces = board.position.pieces.filter { $0.color == sideToMove }

        for piece in pieces {
            let destinations = board.legalMoves(forPieceAt: piece.square)
            for dest in destinations {
                // Speculatively apply to a copy to check SAN
                var testBoard = board
                if let move = testBoard.move(pieceAt: piece.square, to: dest) {
                    if move.san == san {
                        board.move(pieceAt: piece.square, to: dest)
                        return true
                    }
                }
            }
        }
        return false
    }

    /// Strips move numbers, annotations, and result tokens from PGN.
    private func parsePGNMoves(_ pgn: String) -> [String] {
        // Strip header tags [Key "Value"]
        var clean = pgn
        while let start = clean.range(of: "["),
              let end = clean.range(of: "]", range: start.upperBound..<clean.endIndex) {
            clean.removeSubrange(start.lowerBound...end.upperBound)
        }
        // Strip {comment} blocks
        while let start = clean.range(of: "{"),
              let end = clean.range(of: "}", range: start.upperBound..<clean.endIndex) {
            clean.removeSubrange(start.lowerBound...end.upperBound)
        }

        let results: Set<String> = ["*", "1-0", "0-1", "1/2-1/2"]
        return clean
            .components(separatedBy: .whitespaces)
            .compactMap { token -> String? in
                guard !token.isEmpty else { return nil }
                if token.first!.isNumber { return nil }  // "1." "12..." etc.
                if results.contains(token) { return nil }
                // Strip trailing annotation symbols (!, ?, !!, ??, !?, ?!)
                // Keep + (check) and # (checkmate) — ChessKit includes these in move.san
                let stripped = token.trimmingCharacters(in: CharacterSet(charactersIn: "!?"))
                return stripped.isEmpty ? nil : stripped
            }
    }

    enum APIError: Error, LocalizedError {
        case badResponse
        case pgnParseFailure

        var errorDescription: String? {
            switch self {
            case .badResponse: return "Lichess returned an unexpected response."
            case .pgnParseFailure: return "Could not parse the puzzle position from PGN."
            }
        }
    }
}

// MARK: - Lichess JSON decodable types (private to this file)

private struct LichessResponse: Decodable {
    let game: LichessGame
    let puzzle: LichessPuzzle
}

private struct LichessGame: Decodable {
    let id: String
    let pgn: String
}

private struct LichessPuzzle: Decodable {
    let id: String
    let rating: Int
    let solution: [String]
    let themes: [String]
    let initialPly: Int
    /// Puzzle position FEN — provided by the API, no PGN replay needed when present.
    let fen: String?
    /// Opponent's last move in LAN format — provided when `fen` is present.
    let lastMove: String?
}
