import Foundation

/// Actor-isolated JSON persistence for puzzles. Single file in Documents directory.
actor PuzzleStore {
    static let shared = PuzzleStore()

    let fileURL: URL
    private var cache: [StoredPuzzle]?

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("puzzles.json")
    }

    /// Designated initializer for testing — allows injecting a custom file URL.
    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    // MARK: - Public API

    func loadAll() throws -> [StoredPuzzle] {
        if let cache { return cache }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            cache = []
            return []
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let puzzles = try decoder.decode([StoredPuzzle].self, from: data)
        cache = puzzles
        return puzzles
    }

    func save(_ puzzles: [StoredPuzzle]) throws {
        cache = puzzles
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(puzzles)
        try data.write(to: fileURL, options: .atomic)
    }

    func upsert(_ puzzle: StoredPuzzle) throws {
        var all = try loadAll()
        if let idx = all.firstIndex(where: { $0.id == puzzle.id }) {
            all[idx] = puzzle
        } else {
            all.append(puzzle)
        }
        try save(all)
    }

    func duePuzzles() throws -> [StoredPuzzle] {
        let all = try loadAll()
        return all.filter { $0.isDue }.sorted { $0.nextReviewDate < $1.nextReviewDate }
    }

    func puzzleCount() throws -> Int {
        return try loadAll().count
    }

    /// Replaces entire puzzle list (used when merging freshly-fetched puzzles).
    func mergeNew(_ newPuzzles: [StoredPuzzle]) throws {
        var all = try loadAll()
        let existingIds = Set(all.map(\.id))
        let fresh = newPuzzles.filter { !existingIds.contains($0.id) }
        all.append(contentsOf: fresh)
        try save(all)
    }

    func clearAll() throws {
        cache = []
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}
