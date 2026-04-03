import XCTest

final class ScreenshotTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["MOCK_LICHESS"] = "1"
        app.launch()
    }

    func testCapturePuzzleScreen() throws {
        let startButton = app.buttons["Start Training"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 30))
        startButton.tap()
        sleep(4)

        let screenshot = XCUIScreen.main.screenshot()
        try screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/puzzle_screen.png"))

        let labels = app.buttons.allElementsBoundByIndex.map { $0.label }
        print("PUZZLE SCREEN BUTTONS: \(labels)")
    }

    func testCaptureAfterAnswer() throws {
        let startButton = app.buttons["Start Training"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 30))
        startButton.tap()
        sleep(4)

        let excluded: Set<String> = ["Start Training", "View Stats", "Back", "Puzzle", ""]
        let choiceButton = app.buttons.allElementsBoundByIndex.first {
            !excluded.contains($0.label) && $0.isHittable
        }

        guard let btn = choiceButton else {
            XCTFail("No choice button found. Buttons: \(app.buttons.allElementsBoundByIndex.map { $0.label })")
            return
        }

        print("Tapping choice: \(btn.label)")
        btn.tap()
        sleep(2)

        let screenshot = XCUIScreen.main.screenshot()
        try screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/after_answer.png"))

        let labelsAfter = app.buttons.allElementsBoundByIndex.map { $0.label }
        print("AFTER ANSWER BUTTONS: \(labelsAfter)")

        let hasRating = app.buttons["Easy"].waitForExistence(timeout: 5)
        XCTAssertTrue(hasRating, "Rating buttons should appear. Buttons found: \(labelsAfter)")
    }

    func testCaptureDebugPanelExpanded() throws {
        let startButton = app.buttons["Start Training"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 30))
        startButton.tap()
        sleep(4)

        // Answer any choice to reveal the debug panel
        let excluded: Set<String> = ["Start Training", "View Stats", "Back", "Puzzle", ""]
        guard let choiceButton = app.buttons.allElementsBoundByIndex.first(where: {
            !excluded.contains($0.label) && $0.isHittable
        }) else { XCTFail("No choice button"); return }

        choiceButton.tap()
        sleep(1)

        // Scroll down to reveal the debug panel
        app.swipeUp()
        sleep(1)

        print("ALL BUTTONS AFTER SCROLL: \(app.buttons.allElementsBoundByIndex.map { $0.label })")

        // Tap the debug panel header
        let debugButton = app.buttons["Debug — Puzzle JSON"]
        XCTAssertTrue(debugButton.waitForExistence(timeout: 5), "Debug panel header should be visible after scrolling")
        debugButton.tap()
        sleep(1)

        let screenshot = XCUIScreen.main.screenshot()
        try screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/debug_panel.png"))

        print("DEBUG PANEL BUTTONS: \(app.buttons.allElementsBoundByIndex.map { $0.label })")
    }

    func testCaptureStatsScreen() throws {
        app.buttons["View Stats"].tap()
        sleep(2)

        let screenshot = XCUIScreen.main.screenshot()
        try screenshot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/stats_screen.png"))
    }
}
