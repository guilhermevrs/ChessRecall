# Architecture

## Overview

Chess Recall follows **MVVM** (Model-View-ViewModel) with actor-isolated services.

```
┌─────────────────────────────────────────────────────┐
│                      Views                           │
│   HomeView  ·  PuzzleView  ·  StatsView              │
│   ChessBoardView  ·  ChoiceButton                    │
└────────────────────┬────────────────────────────────┘
                     │ @Published state
┌────────────────────▼────────────────────────────────┐
│                   ViewModels (@MainActor)             │
│   HomeViewModel  ·  PuzzleViewModel  ·  StatsViewModel│
└────────┬──────────────────────┬──────────────────────┘
         │ await                │ await
┌────────▼────────┐   ┌─────────▼──────────────────────┐
│  PuzzleStore    │   │  LichessAPIService               │
│  (actor)        │   │  (actor)                         │
│  JSON on disk   │   │  URLSession + puzzle.fen         │
└────────┬────────┘   └────────────────────────────────┘
         │
┌────────▼────────────────────────────────────────────┐
│                    Models                            │
│   StoredPuzzle  ·  PuzzleSession  ·  PuzzleChoice    │
└─────────────────────────────────────────────────────┘
         │  (pure function, no I/O)
┌────────▼────────────────────────────────────────────┐
│            SpacedRepetitionService                   │
└─────────────────────────────────────────────────────┘
```

---

## Key Design Decisions

### MVVM + @MainActor

All ViewModels are `@MainActor` — they own UI state and publish changes on the main thread. Views are passive: they render state and forward user interactions.

### Actor Isolation

`PuzzleStore` and `LichessAPIService` are Swift actors. This prevents data races when background fetching and UI access happen concurrently, without locks or DispatchQueues.

### Single JSON File Storage

Puzzles are stored as a JSON array in `Documents/puzzles.json`. For a personal app with ~100–200 puzzles, this is simpler than CoreData and easy to inspect. The `actor` guarantees atomic access.

### Spaced Repetition Algorithm

Simplified SM-2:

| Rating | Interval change |
|--------|----------------|
| Easy   | `× 2.5`        |
| Hard   | `× 1.5`        |
| Wrong  | `= 1 day`      |

`nextReviewDate = today + roundedInterval`

A puzzle is "due" when `nextReviewDate <= now`. Default interval: 1 day.

### Lichess API Puzzle Flow

`GET /api/puzzle/next` returns `puzzle.fen` (the puzzle position) and `puzzle.lastMove` (the opponent's setup move in LAN) directly. `LichessAPIService` uses these fields when present:

```
puzzle.fen       → StoredPuzzle.fen        (position shown to player)
puzzle.lastMove  → StoredPuzzle.lastMoveLAN (highlighted on board as last move)
puzzle.solution  → StoredPuzzle.solution    (solution[0] = player's correct first move)
```

PGN replay (`game.pgn` + `puzzle.initialPly`) is kept as a fallback for endpoints that omit `puzzle.fen`.

**Key invariant**: `solution[0]` is always the player's first move. The opponent's setup move that preceded the puzzle is captured separately in `lastMoveLAN`.

### Progressive Puzzle Fetch

`HomeViewModel.fetchIfNeeded()` runs in two phases:

1. **Phase 1 (blocking)**: Fetches 5 puzzles → updates counts → enables "Start Training"
2. **Phase 2 (background Task)**: Silently fills up to 30 puzzles, updating the badge count live

This means the first training session is available in ~1–2 seconds on a good connection, while additional puzzles accumulate in the background.

### ChessBoardView Rendering

The board is rendered in pure SwiftUI using Lichess cburnett piece images (SVGs in `Assets.xcassets/Pieces/`):

- `8×8` grid using `VStack`/`HStack`
- FEN string is parsed at render time into a `[square: assetName]` dictionary
- Piece images: 12 SVG assets (`wK`, `wQ`, `wR`, `wB`, `wN`, `wP` / `bK`…`bP`)
- Coordinate labels: rank numbers left-side, file letters bottom
- Board orientation: `flipped: Bool` reverses rank/file iteration order
- Last-move highlight: two squares (`from`, `to`) tinted yellow, with a fade-in animation

### Last Move Animation

When a puzzle loads and `StoredPuzzle.lastMoveLAN` is set, `ChessBoardView` shows a brief animation:

1. **t = 0**: Piece rendered at the **from**-square (pre-move state, using `displayPiece(at:)` which swaps the piece back)
2. **t = 450ms**: `withAnimation(.easeInOut(duration: 0.35))` — piece crossfades to the **to**-square, yellow highlight fades in

This shows the player exactly which move the opponent just played before their turn.

### Multiple Choice Generation

For each puzzle:
1. Parse `StoredPuzzle.fen` into a ChessKit `Position`
2. Correct move: `EngineLANParser.parse(move: solution[0], ...)` → `.san` for display
3. Distractors: iterate all pieces of `sideToMove`, collect `board.legalMoves(forPieceAt:)`, exclude correct move, shuffle, take 3
4. Return 4 shuffled `PuzzleChoice` items (1 correct + 3 distractors)

### PuzzleViewModel State Machine

```
idle
  └─▶ loading
        ├─▶ presenting(PuzzleSession)
        │       └─▶ answered(choice, session)
        │                 └─▶ rating(correct, selectedChoice, session)
        │                           └─▶ [loop to loading]
        ├─▶ retryWrong(count)    ← after queue empty; wrong puzzles were collected
        └─▶ allCaughtUp          ← no due puzzles, no newly fetched puzzles
        └─▶ error(String)
```

Wrong-rated puzzles are collected in `wrongPuzzlesQueue: [StoredPuzzle]` during the session and offered as an optional retry pass at the end. SRS state is saved immediately on rating; retried puzzles are rated independently.

### Data Version Migration

`HomeViewModel` stores a `dataVersion` string in `UserDefaults`. When the app launches and the stored version doesn't match the current value, the puzzle cache is cleared and puzzles are re-fetched. This ensures cached puzzles always match the current parsing format. Bump `dataVersion` whenever `StoredPuzzle`'s on-disk format changes.

---

## Test Mock Infrastructure

### Unit Tests (`ChessRecallTests`)

`LichessAPIService` accepts an optional `URLSession` in its initializer. Tests pass a session configured with `MockURLProtocol` as its `protocolClasses`, intercepting all requests to `lichess.org` and returning pre-recorded fixture responses from `ChessRecallTests/Fixtures/`.

### UI Tests (`ChessRecallUITests`)

UI tests set `launchEnvironment["MOCK_LICHESS"] = "1"` on `XCUIApplication`. In `DEBUG` builds, `ChessRecallApp.init()` detects this and calls `LichessAPIMock.register()`, which loads inline fixture JSON into `MockLichessProtocol`. `LichessAPIService` then injects `MockLichessProtocol` into its `URLSessionConfiguration` — so no real network calls are made during the test run.

---

## Adding Datadog RUM

The following touch points are naturally isolated for instrumentation:

```swift
// PuzzleViewModel.loadNextPuzzle() — puzzle starts
RUM.startView("puzzle", attributes: ["puzzleId": puzzle.id, "rating": puzzle.rating, "themes": puzzle.themes])

// PuzzleViewModel.submitAnswer() — user selects a choice
RUM.addAction(.tap, name: "answer_selected", attributes: ["isCorrect": choice.isCorrect, "timeToAnswer": elapsed])

// PuzzleViewModel.submitRating() — user rates difficulty
RUM.addAction(.tap, name: "self_rating", attributes: ["difficulty": difficulty])

// LichessAPIService.fetchPuzzle() — API latency
RUM.addResourceTiming(url: "lichess.org/api/puzzle/next", duration: elapsed)
```

Import `DatadogRUM` via SPM and add these calls without changing existing logic.
