import SwiftUI

struct PuzzleView: View {
    @StateObject private var viewModel = PuzzleViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var debugExpanded = false
    @State private var boardExpanded = true

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                loadingView

            case .presenting(let session):
                puzzleContent(session: session, selectedChoice: nil, isRevealed: false)

            case .answered(let choice, let session):
                puzzleContent(session: session, selectedChoice: choice, isRevealed: true, ratingCorrect: nil)
                    .overlay(alignment: .top) { answerBanner(correct: choice.isCorrect) }

            case .rating(let correct, let choice, let session):
                puzzleContent(session: session, selectedChoice: choice, isRevealed: true, ratingCorrect: correct)
                    .overlay(alignment: .top) { answerBanner(correct: correct) }

            case .allCaughtUp:
                allCaughtUpView

            case .retryWrong(let count):
                retryView(count: count)

            case .error(let msg):
                errorView(message: msg)
            }
        }
        .navigationTitle("Puzzle")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.startSession() }
        .onChange(of: viewModel.state) { _, newState in
            switch newState {
            case .answered:
                withAnimation(.easeInOut(duration: 0.25)) { boardExpanded = false }
            case .presenting:
                boardExpanded = true
                debugExpanded = false
            default:
                break
            }
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading puzzle…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func puzzleContent(
        session: PuzzleSession,
        selectedChoice: PuzzleChoice?,
        isRevealed: Bool,
        ratingCorrect: Bool? = nil
    ) -> some View {
        let puzzle = session.puzzle
        let sideToMove = sideToMove(from: puzzle.fen)
        let flipped = sideToMove == "b"

        return ScrollView {
            VStack(spacing: 20) {
                // Rating badge
                HStack {
                    Label("\(puzzle.rating)", systemImage: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Label(puzzle.themes.prefix(2).joined(separator: ", "), systemImage: "tag")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal)

                // Chessboard (collapsible after answering)
                if isRevealed {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { boardExpanded.toggle() }
                    } label: {
                        HStack {
                            Image(systemName: boardExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                            Text(boardExpanded ? "Hide board" : "Show board")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    }
                }

                if boardExpanded {
                    ChessBoardView(
                        fen: puzzle.fen,
                        flipped: flipped,
                        lastMove: lastMoveSquares(puzzle.lastMoveLAN)
                    )
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Player indicator
                if boardExpanded {
                    Text(flipped ? "Black to move" : "White to move")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Multiple choice buttons
                VStack(spacing: 10) {
                    ForEach(session.choices) { choice in
                        ChoiceButton(
                            choice: choice,
                            isSelected: selectedChoice?.id == choice.id,
                            isRevealed: isRevealed
                        ) {
                            if case .presenting = viewModel.state {
                                viewModel.submitAnswer(choice)
                                // Small delay then show rating
                                Task {
                                    try? await Task.sleep(nanoseconds: 800_000_000)
                                    viewModel.showRating()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal)

                // Lichess link — shown after answering
                if isRevealed, let url = URL(string: "https://lichess.org/training/\(puzzle.id)") {
                    Link(destination: url) {
                        Label("See on Lichess", systemImage: "arrow.up.right.square")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Rating panel — inline when in rating state (no overlay)
                if let correct = ratingCorrect {
                    ratingPanel(correct: correct)
                        .padding(.horizontal)
                }

                // Debug panel — only shown after answering
                if isRevealed {
                    debugPanel(puzzle: puzzle)
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                }
            }
            .padding(.top)
        }
    }

    private func answerBanner(correct: Bool) -> some View {
        HStack {
            Image(systemName: correct ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(correct ? .green : .red)
            Text(correct ? "Correct!" : "Wrong")
                .fontWeight(.semibold)
                .foregroundStyle(correct ? .green : .red)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .clipShape(Capsule())
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func ratingPanel(correct: Bool) -> some View {
        VStack(spacing: 12) {
            Text(correct ? "How was it?" : "Keep practicing")
                .font(.headline)

            HStack(spacing: 12) {
                ratingButton("Wrong", color: .red, difficulty: .wrong)
                ratingButton("Hard", color: .orange, difficulty: .hard)
                ratingButton("Easy", color: .green, difficulty: .easy)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }

    private func ratingButton(_ label: String, color: Color, difficulty: Difficulty) -> some View {
        Button {
            Task { await viewModel.submitRating(difficulty) }
        } label: {
            Text(label)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(color.opacity(0.15))
                .foregroundStyle(color)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(color.opacity(0.4), lineWidth: 1)
                )
        }
    }

    private func debugPanel(puzzle: StoredPuzzle) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row — tap to expand/collapse
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    debugExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "ant.fill")
                        .font(.caption)
                    Text("Debug — Puzzle JSON")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: debugExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            if debugExpanded {
                Divider()
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(formattedJSON(puzzle))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.primary)
                        .padding(12)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 320)
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }

    private func formattedJSON(_ puzzle: StoredPuzzle) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(puzzle),
              let string = String(data: data, encoding: .utf8) else {
            return "{ \"error\": \"could not encode puzzle\" }"
        }
        return string
    }

    private var allCaughtUpView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            Text("All caught up!")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Come back tomorrow for more puzzles.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Back to Home") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func retryView(count: Int) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)
            Text("Session complete!")
                .font(.title2)
                .fontWeight(.semibold)
            Text("You got \(count) puzzle\(count == 1 ? "" : "s") wrong.")
                .foregroundStyle(.secondary)
            Button("Retry Wrong Puzzles (\(count))") {
                Task { await viewModel.startRetrySession() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            Button("Skip") { dismiss() }
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await viewModel.startSession() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func sideToMove(from fen: String) -> String {
        let parts = fen.split(separator: " ")
        return parts.count > 1 ? String(parts[1]) : "w"
    }

    /// Parses a UCI move like "e2e4" into (from: "e2", to: "e4"), or nil if malformed.
    private func lastMoveSquares(_ lan: String?) -> (from: String, to: String)? {
        guard let lan, lan.count >= 4 else { return nil }
        let from = String(lan.prefix(2))
        let to   = String(lan.dropFirst(2).prefix(2))
        return (from, to)
    }
}

#Preview {
    NavigationStack {
        PuzzleView()
    }
}
