import SwiftUI

/// Renders a chess board from a FEN string using Lichess cburnett piece images
/// with rank/file coordinate labels.
///
/// When `lastMove` is provided the board first shows the piece at the **from** square
/// (pre-move state), then after a short delay animates to the final position and fades
/// in the yellow highlight — so the player can see what move was just played.
struct ChessBoardView: View {
    let fen: String
    /// When true the board is shown from Black's perspective.
    var flipped: Bool = false
    /// Optional last-move squares to highlight (e.g. ("e2", "e4")).
    var lastMove: (from: String, to: String)? = nil

    private static let lightSquare = Color(red: 240/255, green: 217/255, blue: 181/255)
    private static let darkSquare  = Color(red: 181/255, green: 136/255, blue:  99/255)
    private static let coordFont = Font.system(size: 9, weight: .semibold)

    /// Drives the move animation. When false the piece is shown at the from-square;
    /// when true it's shown at the to-square (final FEN state).
    @State private var moveAnimated = false
    @State private var highlightOpacity: Double = 0

    var body: some View {
        GeometryReader { geo in
            let totalSize = min(geo.size.width, geo.size.height)
            let labelWidth: CGFloat = 14
            let boardSize = totalSize - labelWidth
            let sq = boardSize / 8

            HStack(spacing: 0) {
                // Rank labels (left side)
                VStack(spacing: 0) {
                    ForEach(rankIndices, id: \.self) { rankIdx in
                        Text(rankLabel(rankIdx))
                            .font(Self.coordFont)
                            .foregroundStyle(.secondary)
                            .frame(width: labelWidth, height: sq)
                    }
                }

                VStack(spacing: 0) {
                    // Board squares
                    ForEach(rankIndices, id: \.self) { rankIdx in
                        HStack(spacing: 0) {
                            ForEach(fileIndices, id: \.self) { fileIdx in
                                let square = squareAt(rankIdx: rankIdx, fileIdx: fileIdx)
                                let isLight = (rankIdx + fileIdx) % 2 == 0
                                let piece = displayPiece(at: square)

                                ZStack {
                                    (isLight ? Self.lightSquare : Self.darkSquare)
                                    if isLastMoveSquare(square) {
                                        Color.yellow.opacity(0.55 * highlightOpacity)
                                    }
                                    if let name = piece {
                                        Image(name)
                                            .resizable()
                                            .interpolation(.high)
                                            .antialiased(true)
                                            .scaledToFit()
                                            .padding(sq * 0.04)
                                            .transition(.opacity)
                                    }
                                }
                                .animation(.easeInOut(duration: 0.35), value: moveAnimated)
                                .frame(width: sq, height: sq)
                            }
                        }
                    }

                    // File labels (bottom)
                    HStack(spacing: 0) {
                        ForEach(fileIndices, id: \.self) { fileIdx in
                            Text(fileLabel(fileIdx))
                                .font(Self.coordFont)
                                .foregroundStyle(.secondary)
                                .frame(width: sq, height: labelWidth)
                        }
                    }
                }
            }
            .frame(width: totalSize, height: totalSize)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { startAnimation() }
        .onChange(of: fen) { startAnimation() }
    }

    // MARK: - Animation

    private func startAnimation() {
        guard lastMove != nil else {
            moveAnimated = true
            highlightOpacity = 1
            return
        }
        // Step 1: show piece at from-square (pre-move), no highlight
        moveAnimated = false
        highlightOpacity = 0

        // Step 2: after a brief pause, animate piece to to-square and fade in highlight
        Task {
            try? await Task.sleep(nanoseconds: 450_000_000) // 0.45s pause
            withAnimation(.easeInOut(duration: 0.35)) {
                moveAnimated = true
                highlightOpacity = 1
            }
        }
    }

    /// Returns the piece to display at a given square, accounting for the animation state.
    ///
    /// When `moveAnimated = false` (pre-move): the moving piece is shown at the **from** square
    /// and the **to** square is empty, so the player sees the position before the last move.
    /// When `moveAnimated = true`: the normal FEN piece map is used.
    private func displayPiece(at square: String) -> String? {
        guard let lm = lastMove, !moveAnimated else { return pieceMap[square] }
        if square == lm.from { return pieceMap[lm.to] }  // piece hasn't moved yet
        if square == lm.to   { return nil }               // destination is empty pre-move
        return pieceMap[square]
    }

    // MARK: - Board orientation

    private var rankIndices: [Int] {
        flipped ? Array(0..<8) : Array((0..<8).reversed())
    }

    private var fileIndices: [Int] {
        flipped ? Array((0..<8).reversed()) : Array(0..<8)
    }

    private func rankLabel(_ rankIdx: Int) -> String { "\(rankIdx + 1)" }

    private func fileLabel(_ fileIdx: Int) -> String {
        String(UnicodeScalar(Int(("a" as UnicodeScalar).value) + fileIdx)!)
    }

    private func squareAt(rankIdx: Int, fileIdx: Int) -> String {
        let file = Character(UnicodeScalar(Int(("a" as UnicodeScalar).value) + fileIdx)!)
        return "\(file)\(rankIdx + 1)"
    }

    private func isLastMoveSquare(_ square: String) -> Bool {
        guard let lm = lastMove else { return false }
        return square == lm.from || square == lm.to
    }

    // MARK: - FEN parsing → asset name map

    private var pieceMap: [String: String] {
        var map: [String: String] = [:]
        let parts = fen.split(separator: " ")
        guard let boardPart = parts.first else { return map }

        let ranks = boardPart.split(separator: "/")
        for (rankOffset, rankStr) in ranks.enumerated() {
            let rank = 8 - rankOffset
            var fileIdx = 0
            for char in rankStr {
                if let skip = char.wholeNumberValue {
                    fileIdx += skip
                } else {
                    let file = Character(UnicodeScalar(Int(("a" as UnicodeScalar).value) + fileIdx)!)
                    map["\(file)\(rank)"] = assetName(for: char)
                    fileIdx += 1
                }
            }
        }
        return map
    }

    private func assetName(for char: Character) -> String {
        switch char {
        case "K": return "Pieces/wK"
        case "Q": return "Pieces/wQ"
        case "R": return "Pieces/wR"
        case "B": return "Pieces/wB"
        case "N": return "Pieces/wN"
        case "P": return "Pieces/wP"
        case "k": return "Pieces/bK"
        case "q": return "Pieces/bQ"
        case "r": return "Pieces/bR"
        case "b": return "Pieces/bB"
        case "n": return "Pieces/bN"
        case "p": return "Pieces/bP"
        default:  return ""
        }
    }
}

#Preview {
    ChessBoardView(
        fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1",
        lastMove: (from: "e2", to: "e4")
    )
    .padding()
}
