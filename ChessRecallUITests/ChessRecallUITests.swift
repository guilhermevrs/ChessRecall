import XCTest

final class ChessRecallUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["MOCK_LICHESS"] = "1"
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Home Screen

    func testHomeScreenElementsExist() throws {
        XCTAssertTrue(app.staticTexts["Chess Recall"].exists)
        XCTAssertTrue(app.staticTexts["Spaced repetition puzzle trainer"].exists)
        XCTAssertTrue(app.buttons["Start Training"].exists || app.buttons["Loading…"].exists)
        XCTAssertTrue(app.buttons["View Stats"].exists)
    }

    // MARK: - Puzzle Flow

    func testStartTrainingNavigatesToPuzzleScreen() throws {
        // Wait for puzzles to load (up to 30s for network fetch)
        let startButton = app.buttons["Start Training"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 30), "Start Training button should appear after loading")
        startButton.tap()

        // Puzzle screen should appear with navigation bar
        let puzzleNav = app.navigationBars["Puzzle"]
        XCTAssertTrue(puzzleNav.waitForExistence(timeout: 10), "Should navigate to Puzzle screen")
    }

    func testPuzzleScreenShowsBoardAndChoices() throws {
        let startButton = app.buttons["Start Training"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 30))
        startButton.tap()

        // Wait for puzzle to load
        sleep(3)

        // There should be exactly 4 choice buttons (or at least 2)
        // They are regular buttons in the VStack
        let buttons = app.buttons.allElementsBoundByIndex
        let choiceButtons = buttons.filter { $0.label.count <= 10 && $0.label != "Puzzle" }
        XCTAssertGreaterThanOrEqual(choiceButtons.count, 2, "Should show multiple choice options")
    }

    func testSelectingAnswerShowsFeedback() throws {
        let startButton = app.buttons["Start Training"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 30))
        startButton.tap()

        sleep(4)

        // Find any button that's not a nav/system button
        let excluded: Set<String> = ["Start Training", "View Stats", "Back", "Puzzle", ""]
        guard let choiceButton = app.buttons.allElementsBoundByIndex.first(where: {
            !excluded.contains($0.label) && $0.isHittable
        }) else {
            XCTFail("No choice buttons found on puzzle screen. Found: \(app.buttons.allElementsBoundByIndex.map { $0.label })")
            return
        }

        choiceButton.tap()

        // Rating panel should appear
        XCTAssertTrue(app.buttons["Easy"].waitForExistence(timeout: 5), "Rating buttons should appear after answering")
        XCTAssertTrue(app.buttons["Wrong"].exists)
        XCTAssertTrue(app.buttons["Hard"].exists)
    }

    // MARK: - Stats Screen

    func testStatsScreenLoads() throws {
        app.buttons["View Stats"].tap()
        let statsNav = app.navigationBars["Stats"]
        XCTAssertTrue(statsNav.waitForExistence(timeout: 5), "Stats screen should appear")
    }
}
