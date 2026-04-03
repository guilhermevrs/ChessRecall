# Chess Recall

A chess puzzle trainer for iOS using spaced repetition (SM-2 inspired) and the Lichess public API.

Solve puzzles in a multiple-choice format, self-rate difficulty (Easy / Hard / Wrong), and see puzzles repeat at the right time — the more you struggle, the sooner it comes back.

---

## Requirements

- **Xcode 16+** (tested on Xcode 26.4)
- **iOS 17+** deployment target
- **Swift 5.9+**
- **XcodeGen** (`brew install xcodegen`)
- **Internet connection** for first-time puzzle fetch (offline after that)

---

## Setup

```bash
# Clone the repo
git clone <repo-url>
cd chess-learning-app

# Install XcodeGen if needed
brew install xcodegen

# Generate the Xcode project
xcodegen generate

# Resolve Swift Package Manager dependencies (needs internet)
xcodebuild -resolvePackageDependencies \
  -project ChessRecall.xcodeproj \
  -scheme ChessRecall
```

> **iOS Simulator first-time setup**: After installing Xcode, open it once and go to
> **Xcode → Settings → Platforms** and download the iOS platform. This is required
> for simulator builds and tests. You only need to do this once.

---

## Build

```bash
xcodebuild \
  -project ChessRecall.xcodeproj \
  -scheme ChessRecall \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  CODE_SIGN_IDENTITY="-" \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  build
```

---

## Run Tests

Tests never hit the real Lichess API — unit tests use `MockURLProtocol` with pre-recorded fixture responses, and UI tests activate an inline mock via the `MOCK_LICHESS=1` environment variable.

```bash
# Run all tests (unit + UI)
xcodebuild test \
  -project ChessRecall.xcodeproj \
  -scheme ChessRecall \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  CODE_SIGN_IDENTITY="-" \
  AD_HOC_CODE_SIGNING_ALLOWED=YES

# Run only unit tests
xcodebuild test \
  -project ChessRecall.xcodeproj \
  -scheme ChessRecall \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  CODE_SIGN_IDENTITY="-" \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  -only-testing:ChessRecallTests

# Run a single test class
xcodebuild test \
  -project ChessRecall.xcodeproj \
  -scheme ChessRecall \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  CODE_SIGN_IDENTITY="-" \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  -only-testing:ChessRecallTests/LichessAPIServiceTests
```

---

## Run on Real Device

```bash
# Find your device UDID
xcrun devicectl list devices

# Build (requires signing — set your Team ID once in Xcode)
xcodebuild \
  -project ChessRecall.xcodeproj \
  -scheme ChessRecall \
  -destination 'id=<DEVICE_UDID>' \
  DEVELOPMENT_TEAM=<TEAM_ID> \
  build
```

For first-time real device builds, open Xcode once to configure signing:
**ChessRecall target → Signing & Capabilities → Team** → select your Apple ID.

---

## API

Uses the [Lichess public API](https://lichess.org/api) — no key or account required.

Endpoint: `GET https://lichess.org/api/puzzle/next`

The response includes `puzzle.fen` (puzzle position) and `puzzle.lastMove` (opponent's setup move) directly — no PGN replay needed. On first launch, the app fetches 5 puzzles immediately (enough to start training), then continues filling up to 30 puzzles silently in the background.

---

## Offline Behavior

- Puzzles are cached in `Documents/puzzles.json`
- The app works fully offline after the initial fetch
- Background fetch runs on each launch until 30 puzzles are cached
- If the API is unreachable, cached puzzles are used silently

---

## Project Structure

```
chess-learning-app/
├── project.yml                          # XcodeGen spec — source of truth for project config
├── ChessRecall/
│   ├── App/ChessRecallApp.swift
│   ├── Models/
│   │   ├── StoredPuzzle.swift           # Codable puzzle + SRS state
│   │   └── PuzzleSession.swift          # Runtime session (not persisted)
│   ├── Services/
│   │   ├── SpacedRepetitionService.swift
│   │   ├── PuzzleStore.swift            # JSON persistence (actor-isolated)
│   │   └── LichessAPIService.swift      # Fetches puzzles; uses puzzle.fen directly
│   ├── TestSupport/
│   │   └── LichessAPIMock.swift         # DEBUG-only: inline fixtures for UI tests
│   ├── ViewModels/
│   │   ├── HomeViewModel.swift          # Progressive fetch logic
│   │   ├── PuzzleViewModel.swift        # State machine + choice generation
│   │   └── StatsViewModel.swift
│   └── Views/
│       ├── Home/HomeView.swift
│       ├── Puzzle/
│       │   ├── PuzzleView.swift
│       │   ├── ChessBoardView.swift     # Lichess cburnett SVG pieces + coordinates
│       │   └── ChoiceButton.swift
│       └── Stats/StatsView.swift
├── ChessRecallTests/
│   ├── Fixtures/                        # Pre-recorded Lichess API responses
│   │   ├── puzzle_MgP8r.json
│   │   ├── puzzle_HxxIU.json
│   │   └── puzzle_Ytw4u.json
│   ├── Support/
│   │   └── MockURLProtocol.swift        # URLProtocol interceptor for unit tests
│   ├── LichessAPIServiceTests.swift     # Full API parsing pipeline (no network)
│   ├── SpacedRepetitionTests.swift
│   ├── FENParsing_MoveTests.swift
│   └── PuzzleStoreTests.swift
└── ChessRecallUITests/
    ├── ChessRecallUITests.swift         # Flow tests (mock API via MOCK_LICHESS=1)
    └── ScreenshotTests.swift
```

---

## Dependencies

| Package | Purpose |
|---|---|
| [chesskit-app/chesskit-swift](https://github.com/chesskit-app/chesskit-swift) | FEN parsing, legal move generation, SAN notation, UCI parsing |

All other functionality (board rendering, networking, persistence) uses only Apple frameworks.
