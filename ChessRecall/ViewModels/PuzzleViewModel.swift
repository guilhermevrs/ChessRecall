import Foundation
import ChessKit

@MainActor
final class PuzzleViewModel: ObservableObject {

    enum State: Equatable {
        case idle
        case loading
        case presenting(PuzzleSession)
        case answered(choice: PuzzleChoice, session: PuzzleSession)
        case rating(correct: Bool, selectedChoice: PuzzleChoice, session: PuzzleSession)
        case allCaughtUp
        case retryWrong(count: Int)
        case error(String)
    }

    @Published var state: State = .idle

    private let store = PuzzleStore.shared
    private let api = LichessAPIService.shared

    /// Wrong puzzles collected during the current session for retry.
    private var wrongPuzzlesQueue: [StoredPuzzle] = []
    private var isRetryMode = false

    // MARK: - Public API

    func startSession() async {
        wrongPuzzlesQueue = []
        isRetryMode = false
        await loadNextPuzzle()
    }

    func submitAnswer(_ choice: PuzzleChoice) {
        guard case .presenting(let session) = state else { return }
        state = .answered(choice: choice, session: session)
    }

    func showRating() {
        guard case .answered(let choice, let session) = state else { return }
        state = .rating(correct: choice.isCorrect, selectedChoice: choice, session: session)
    }

    func submitRating(_ difficulty: Difficulty) async {
        guard case .rating(_, _, let session) = state else { return }
        let updated = SpacedRepetitionService.update(puzzle: session.puzzle, difficulty: difficulty)

        try? await store.upsert(updated)

        if difficulty == .wrong && !isRetryMode {
            wrongPuzzlesQueue.append(session.puzzle)
        }

        await loadNextPuzzle()
    }

    func startRetrySession() async {
        isRetryMode = true
        let toRetry = wrongPuzzlesQueue
        wrongPuzzlesQueue = []

        if let first = toRetry.first {
            wrongPuzzlesQueue = Array(toRetry.dropFirst())
            if let session = buildSession(for: first) {
                state = .presenting(session)
            } else {
                await loadNextPuzzle()
            }
        } else {
            state = .allCaughtUp
        }
    }

    // MARK: - Private

    private func loadNextPuzzle() async {
        if isRetryMode, let next = wrongPuzzlesQueue.first {
            wrongPuzzlesQueue.removeFirst()
            if let session = buildSession(for: next) {
                state = .presenting(session)
                return
            }
        }

        state = .loading

        do {
            let duePuzzles = try await store.duePuzzles()

            if let puzzle = duePuzzles.first {
                if let session = buildSession(for: puzzle) {
                    state = .presenting(session)
                } else {
                    // Skip puzzles we can't build choices for (bad FEN, etc.)
                    var mutable = puzzle
                    mutable.nextReviewDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
                    try? await store.upsert(mutable)
                    await loadNextPuzzle()
                }
                return
            }

            // No due puzzles — try to fetch a new one
            if let fetched = try? await api.fetchPuzzle() {
                try? await store.upsert(fetched)
                if let session = buildSession(for: fetched) {
                    state = .presenting(session)
                    return
                }
            }

            if !wrongPuzzlesQueue.isEmpty {
                state = .retryWrong(count: wrongPuzzlesQueue.count)
            } else {
                state = .allCaughtUp
            }
        } catch {
            state = .error("Failed to load puzzle: \(error.localizedDescription)")
        }
    }

    /// Builds a PuzzleSession for a given stored puzzle, generating 4 multiple-choice options.
    func buildSession(for puzzle: StoredPuzzle) -> PuzzleSession? {
        guard !puzzle.solution.isEmpty else { return nil }
        let choices = generateChoices(for: puzzle)
        guard choices.count >= 2 else { return nil }
        return PuzzleSession(puzzle: puzzle, choices: choices)
    }

    /// Generates 4 shuffled choices: the correct move + up to 3 random legal distractors.
    private func generateChoices(for puzzle: StoredPuzzle) -> [PuzzleChoice] {
        guard let position = Position(fen: puzzle.fen) else { return [] }
        var board = Board(position: position)

        let correctLAN = puzzle.correctMoveLAN
        guard let correctMove = EngineLANParser.parse(move: correctLAN,
                                                      for: position.sideToMove,
                                                      in: position) else { return [] }

        let correctChoice = PuzzleChoice(san: correctMove.san, lan: correctLAN, isCorrect: true)

        // Generate all legal moves for the current side as distractor candidates
        var distractors: [PuzzleChoice] = []
        let pieces = board.position.pieces.filter { $0.color == position.sideToMove }

        for piece in pieces {
            let destinations = board.legalMoves(forPieceAt: piece.square)
            for dest in destinations {
                var testBoard = board
                if let move = testBoard.move(pieceAt: piece.square, to: dest) {
                    let lan = "\(piece.square.notation)\(dest.notation)"
                    if lan != correctLAN {
                        distractors.append(PuzzleChoice(san: move.san, lan: lan, isCorrect: false))
                    }
                }
            }
        }

        distractors.shuffle()
        let selectedDistractors = Array(distractors.prefix(3))

        return ([correctChoice] + selectedDistractors).shuffled()
    }
}
