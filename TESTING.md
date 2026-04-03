# Testing

## Test Targets

| Target | Files | What it covers |
|--------|-------|----------------|
| `ChessRecallTests` | 4 test files | Unit tests — pure logic, no network, no UI |
| `ChessRecallUITests` | 2 test files | UI tests — real app, mock API, XCUITest |

Tests **never hit the real Lichess API**. Unit tests use `MockURLProtocol` with fixture JSON. UI tests use an inline mock activated via `MOCK_LICHESS=1`.

---

## Run All Tests

```bash
xcodebuild test \
  -project ChessRecall.xcodeproj \
  -scheme ChessRecall \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  CODE_SIGN_IDENTITY="-" \
  AD_HOC_CODE_SIGNING_ALLOWED=YES
```

> **Prerequisite**: iOS Simulator runtime must be installed.
> Open Xcode → Settings → Platforms → download iOS 26.

---

## Run a Specific Target or Class

```bash
# Unit tests only
xcodebuild test ... -only-testing:ChessRecallTests

# UI tests only
xcodebuild test ... -only-testing:ChessRecallUITests

# Single class
xcodebuild test ... -only-testing:ChessRecallTests/LichessAPIServiceTests

# Single test method
xcodebuild test ... -only-testing:ChessRecallTests/LichessAPIServiceTests/testMgP8rLastMoveMatchesFixture
```

---

## Unit Test Coverage

### `LichessAPIServiceTests` (9 tests) — API parsing pipeline

Uses `MockURLProtocol` to intercept requests and return fixture responses from `ChessRecallTests/Fixtures/`.

- Parses puzzle ID, rating, themes from fixture JSON
- FEN has valid side-to-move field (`w` or `b`)
- `lastMoveLAN` is populated from `puzzle.lastMove` in the API response
- MgP8r: `lastMoveLAN == "d4c4"`, `solution[0] == "e2f2"` (Qf2+)
- HxxIU: `lastMoveLAN == "c3d5"`, `solution[0] == "e6d5"`
- Ytw4u: `lastMoveLAN == "e4f3"`, `solution[0] == "e1e8"`
- Batch fetch returns puzzles in fixture order
- Network error / bad response throws correctly
- Correct move from fixture puzzle always appears in generated choices

### `SpacedRepetitionTests` (9 tests)

- Easy multiplies interval by 2.5
- Hard multiplies interval by 1.5
- Wrong resets interval to 1
- Wrong does not increment `successCount`
- Hard/Easy increment both `successCount` and `totalAttempts`
- Interval clamped to [1, 365]
- `nextReviewDate` is always in the future

### `FENParsing_MoveTests` (10 tests)

- Standard starting FEN parses correctly, side to move = white
- Invalid FEN returns nil
- White king is on e1 in starting position
- `e2e4` changes position and switches side to move
- Illegal move (e2→e5) returns nil
- Legal destinations from e2 include e3 and e4
- `EngineLANParser` parses `"e2e4"` into correct start/end squares
- `buildSession` always includes the correct move
- Exactly one choice marked correct
- All choices are legal moves

### `PuzzleStoreTests` (8 tests)

- Save and reload round-trips correctly
- Empty store returns empty array
- Upsert adds new puzzles
- Upsert updates existing puzzle by id
- `duePuzzles()` filters by `nextReviewDate <= now`
- `duePuzzles()` sorted oldest-first
- `mergeNew()` skips duplicate ids
- `clearAll()` empties the store

---

## UI Test Coverage (`ChessRecallUITests`)

All UI tests set `launchEnvironment["MOCK_LICHESS"] = "1"]` — puzzles load instantly from inline fixtures, no waiting for network.

### `ChessRecallUITests` (5 tests)

- Home screen shows title, subtitle, Start Training button, View Stats
- Tapping Start Training navigates to Puzzle screen with "Puzzle" nav bar
- Puzzle screen shows at least 2 choice buttons after loading
- Selecting a choice causes Easy/Hard/Wrong rating panel to appear
- Tapping View Stats loads Stats screen with "Stats" nav bar

### `ScreenshotTests` (3 tests) — visual capture helpers

Not automated assertions — used to capture screenshots for debugging:
- `testCapturePuzzleScreen` → `/tmp/puzzle_screen.png`
- `testCaptureAfterAnswer` → `/tmp/after_answer.png`
- `testCaptureDebugPanelExpanded` → `/tmp/debug_panel.png`

---

## Fixture Files

Pre-recorded Lichess API responses live in `ChessRecallTests/Fixtures/`.

| File | Puzzle | Key details |
|------|--------|-------------|
| `puzzle_MgP8r.json` | MgP8r | mateIn3, `lastMove: d4c4`, solution starts `e2f2` |
| `puzzle_HxxIU.json` | HxxIU | middlegame hanging piece, `lastMove: c3d5` |
| `puzzle_Ytw4u.json` | Ytw4u | mateIn2, `lastMove: e4f3`, solution starts `e1e8` |

To add a new fixture:
```bash
curl -s "https://lichess.org/api/puzzle/<ID>" \
  -H "Accept: application/json" \
  -o ChessRecallTests/Fixtures/puzzle_<ID>.json
```

Then add it to `LichessAPIMock.fixtureDataset` in `ChessRecall/TestSupport/LichessAPIMock.swift` for UI test coverage.

---

## Manual Test Checklist

### Loading State
- [ ] First launch (or after cache clear) shows spinner + "Fetching puzzles… N / 5"
- [ ] After 5 puzzles: "Start Training" button enables, badges show counts
- [ ] Background fetch continues — badge counts increment silently up to 30

### Core Puzzle Flow
- [ ] Board shows pre-move position briefly, then opponent's last move animates in
- [ ] Yellow squares highlight opponent's from/to squares after animation
- [ ] 4 choice buttons appear with valid SAN notation
- [ ] Correct answer → green highlight, "Correct!" banner stays visible
- [ ] Wrong answer → selected stays red, correct reveals green, "Wrong" banner stays
- [ ] Rating panel (Wrong/Hard/Easy) appears below choices — no overlap
- [ ] "See on Lichess" link opens the correct puzzle URL

### Session End
- [ ] All due puzzles rated → "All caught up!" screen
- [ ] If any Wrong → retry button with count appears
- [ ] Retry session uses separate queue, doesn't change SRS until re-answered

### Spaced Repetition
- [ ] Rate Easy → relaunch → `nextReviewDate` ≈ 3 days out
- [ ] Rate Wrong → relaunch → `nextReviewDate` ≈ tomorrow

### Offline Mode
- [ ] Fetch puzzles → enable Airplane Mode → relaunch → cached puzzles load
- [ ] "Start Training" works with cached puzzles offline

### Stats
- [ ] Solve 5+ puzzles → Stats shows correct totals and theme breakdown
