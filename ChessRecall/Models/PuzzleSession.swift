import Foundation

/// Transient runtime state for a single puzzle interaction. Never persisted.
struct PuzzleSession: Equatable {
    let puzzle: StoredPuzzle
    /// 4 multiple-choice options (1 correct + 3 distractors), shuffled.
    let choices: [PuzzleChoice]
}

struct PuzzleChoice: Identifiable, Equatable {
    let id = UUID()
    /// Human-readable SAN notation, e.g. "Nxd5", "O-O", "e4".
    let san: String
    /// UCI/LAN notation used for answer comparison, e.g. "c3d5".
    let lan: String
    let isCorrect: Bool
}
