import Foundation
import ChessKit
import DatadogRUM
import DatadogLogs

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

    /// Time the current puzzle was presented; used to calculate time-to-answer.
    private var puzzleStartTime: Date?

    /// Unique key for the current puzzle_training_session operation.
    private var sessionOperationKey: String = ""

    /// Key for the in-flight puzzle_load operation; nil when no load is active.
    private var currentLoadOperationKey: String?

    // MARK: - Public API

    func startSession() async {
        sessionOperationKey = UUID().uuidString
        wrongPuzzlesQueue = []
        isRetryMode = false
        RUMMonitor.shared().startFeatureOperation(
            name: "puzzle_training_session",
            operationKey: sessionOperationKey,
            attributes: ["mode": "normal"]
        )
        AppLogger.shared.info("puzzle_session.started")
        await loadNextPuzzle()
    }

    func submitAnswer(_ choice: PuzzleChoice) {
        guard case .presenting(let session) = state else { return }
        let elapsedMs = puzzleStartTime.map { Int(Date().timeIntervalSince($0) * 1000) } ?? 0
        state = .answered(choice: choice, session: session)

        let p = session.puzzle
        RUMMonitor.shared().addAction(
            type: .custom,
            name: "puzzle.answer_selected",
            attributes: [
                "puzzle.id": p.id,
                "puzzle.rating": p.rating,
                "puzzle.themes": p.themes.joined(separator: ","),
                "answer.is_correct": choice.isCorrect,
                "answer.selected_lan": choice.lan,
                "answer.correct_lan": p.correctMoveLAN,
                "answer.time_to_answer_ms": elapsedMs,
                "session.is_retry_mode": isRetryMode
            ]
        )
        AppLogger.shared.info(
            "puzzle.answered",
            attributes: [
                "puzzle_id": p.id,
                "is_correct": choice.isCorrect,
                "time_ms": elapsedMs
            ]
        )
    }

    func showRating() {
        guard case .answered(let choice, let session) = state else { return }
        state = .rating(correct: choice.isCorrect, selectedChoice: choice, session: session)
    }

    func submitRating(_ difficulty: Difficulty) async {
        guard case .rating(_, _, let session) = state else { return }
        let p = session.puzzle
        let updated = SpacedRepetitionService.update(puzzle: p, difficulty: difficulty)

        do {
            try await store.upsert(updated)
        } catch {
            AppLogger.shared.error(
                "puzzle.store_upsert_failed",
                error: error,
                attributes: ["puzzle_id": p.id]
            )
            RUMMonitor.shared().addError(
                message: "PuzzleStore.upsert failed",
                source: .source,
                attributes: ["puzzle_id": p.id]
            )
        }

        let diffStr: String
        switch difficulty {
        case .easy:  diffStr = "easy"
        case .hard:  diffStr = "hard"
        case .wrong: diffStr = "wrong"
        }

        RUMMonitor.shared().addAction(
            type: .custom,
            name: "puzzle.rated",
            attributes: [
                "puzzle.id": p.id,
                "puzzle.rating": p.rating,
                "rating.difficulty": diffStr,
                "srs.new_interval_days": updated.interval,
                "srs.attempt_count": updated.totalAttempts,
                "srs.success_count": updated.successCount
            ]
        )
        AppLogger.shared.info(
            "puzzle.rated",
            attributes: [
                "puzzle_id": p.id,
                "difficulty": diffStr,
                "new_interval": updated.interval,
                "attempt_count": updated.totalAttempts
            ]
        )

        if difficulty == .wrong && !isRetryMode {
            wrongPuzzlesQueue.append(p)
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

    /// Presents a puzzle, stops the active puzzle_load operation, and sets view-level attributes.
    private func presentPuzzle(session: PuzzleSession, source: String) {
        puzzleStartTime = Date()
        let p = session.puzzle

        if let key = currentLoadOperationKey {
            RUMMonitor.shared().succeedFeatureOperation(
                name: "puzzle_load",
                operationKey: key,
                attributes: [
                    "source": source,
                    "puzzle_rating": p.rating
                ]
            )
            currentLoadOperationKey = nil
        }

        RUMMonitor.shared().addViewAttribute(forKey: "puzzle.id", value: p.id)
        RUMMonitor.shared().addViewAttribute(forKey: "puzzle.rating", value: p.rating)
        RUMMonitor.shared().addViewAttribute(forKey: "puzzle.themes", value: p.themes.joined(separator: ","))
        RUMMonitor.shared().addViewAttribute(forKey: "puzzle.source", value: source)

        AppLogger.shared.info(
            "puzzle.presented",
            attributes: [
                "puzzle_id": p.id,
                "puzzle_rating": p.rating,
                "themes": p.themes.joined(separator: ","),
                "source": source,
                "attempt_count": p.totalAttempts
            ]
        )

        state = .presenting(session)
    }

    private func loadNextPuzzle() async {
        // Retry queue shortcut — no load operation needed (instant)
        if isRetryMode, let next = wrongPuzzlesQueue.first {
            wrongPuzzlesQueue.removeFirst()
            if let session = buildSession(for: next) {
                presentPuzzle(session: session, source: "retry_queue")
                return
            }
            // Fall through to full load if retry puzzle can't build choices
        }

        // Start the puzzle_load operation on the first (non-recursive) entry
        if currentLoadOperationKey == nil {
            let key = UUID().uuidString
            currentLoadOperationKey = key
            RUMMonitor.shared().startFeatureOperation(
                name: "puzzle_load",
                operationKey: key,
                attributes: [:]
            )
        }
        state = .loading
        AppLogger.shared.debug("puzzle.loading_next")

        do {
            let duePuzzles = try await store.duePuzzles()

            if let puzzle = duePuzzles.first {
                if let session = buildSession(for: puzzle) {
                    presentPuzzle(session: session, source: "due_store")
                    return
                } else {
                    // Skip: bad FEN or insufficient legal moves for choices
                    AppLogger.shared.warn(
                        "puzzle.skipped_bad_choices",
                        attributes: ["puzzle_id": puzzle.id, "fen": puzzle.fen]
                    )
                    RUMMonitor.shared().addError(
                        message: "Puzzle skipped: could not generate choices",
                        source: .source,
                        attributes: ["puzzle_id": puzzle.id]
                    )
                    var mutable = puzzle
                    mutable.nextReviewDate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
                    do {
                        try await store.upsert(mutable)
                    } catch {
                        AppLogger.shared.error(
                            "puzzle.reschedule_failed",
                            error: error,
                            attributes: ["puzzle_id": puzzle.id]
                        )
                    }
                    await loadNextPuzzle()
                    return
                }
            }

            // No due puzzles — try the network
            AppLogger.shared.info("puzzle.fetching_from_api")
            do {
                let fetched = try await api.fetchPuzzle()
                do {
                    try await store.upsert(fetched)
                } catch {
                    AppLogger.shared.error(
                        "puzzle.fetch_upsert_failed",
                        error: error,
                        attributes: ["puzzle_id": fetched.id]
                    )
                }
                if let session = buildSession(for: fetched) {
                    presentPuzzle(session: session, source: "api_fetch")
                    return
                }
            } catch {
                AppLogger.shared.error("puzzle.api_fetch_failed", error: error)
                RUMMonitor.shared().addError(
                    message: "Lichess API fetch failed",
                    source: .network,
                    attributes: ["error": error.localizedDescription]
                )
            }

            // No puzzle could be presented — fail the load operation
            if let key = currentLoadOperationKey {
                RUMMonitor.shared().failFeatureOperation(
                    name: "puzzle_load",
                    operationKey: key,
                    reason: .other,
                    attributes: [:]
                )
                currentLoadOperationKey = nil
            }

            if !wrongPuzzlesQueue.isEmpty {
                AppLogger.shared.info(
                    "puzzle.session_retry_prompt",
                    attributes: ["wrong_count": wrongPuzzlesQueue.count]
                )
                RUMMonitor.shared().succeedFeatureOperation(
                    name: "puzzle_training_session",
                    operationKey: sessionOperationKey,
                    attributes: [
                        "reason": "retry_available",
                        "wrong_count": wrongPuzzlesQueue.count
                    ]
                )
                state = .retryWrong(count: wrongPuzzlesQueue.count)
            } else {
                AppLogger.shared.info("puzzle.session_all_caught_up")
                RUMMonitor.shared().succeedFeatureOperation(
                    name: "puzzle_training_session",
                    operationKey: sessionOperationKey,
                    attributes: ["reason": "all_caught_up"]
                )
                state = .allCaughtUp
            }

        } catch {
            AppLogger.shared.error("puzzle.store_load_failed", error: error)
            RUMMonitor.shared().addError(
                message: "PuzzleStore.duePuzzles failed",
                source: .source,
                attributes: ["error": error.localizedDescription]
            )
            if let key = currentLoadOperationKey {
                RUMMonitor.shared().failFeatureOperation(
                    name: "puzzle_load",
                    operationKey: key,
                    reason: .error,
                    attributes: ["error": error.localizedDescription]
                )
                currentLoadOperationKey = nil
            }
            RUMMonitor.shared().failFeatureOperation(
                name: "puzzle_training_session",
                operationKey: sessionOperationKey,
                reason: .error,
                attributes: ["error": error.localizedDescription]
            )
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
