import XCTest

// drives the voice sheet in the playground (see DebugLaunch.opensVoicePlayground) through the
// moves a person makes, slowly enough for a screen recording to show every frame
final class VoicePlaygroundUITests: XCTestCase {
    @MainActor
    func testVoiceSheetMotion() throws {
        let app = XCUIApplication()

        app.launchEnvironment["SHARKORD_DEV_VOICE_PLAYGROUND"] = "1"
        app.launch()

        let open = app.buttons["Open Voice Channel"]

        XCTAssertTrue(open.waitForExistence(timeout: 10))
        sleep(1)
        open.tap()
        sleep(2)

        let window = app.windows.firstMatch
        let join = app.buttons["Join Voice"].firstMatch

        XCTAssertTrue(join.waitForExistence(timeout: 5))

        // a slow drag up from the box's grip, then a quick flick back down
        let grip = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: join.frame.minY - 20))
        grip.press(forDuration: 0.1, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)), withVelocity: 400, thenHoldForDuration: 1.0)
        sleep(2)

        let openJoin = app.buttons["Join Voice"].firstMatch
        let openGrip = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: openJoin.frame.minY - 20))
        openGrip.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)), withVelocity: 2500, thenHoldForDuration: 0)
        sleep(2)

        // a flick up, then a drag of the card down to close
        let restJoin = app.buttons["Join Voice"].firstMatch
        let restGrip = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: restJoin.frame.minY - 20))
        restGrip.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)), withVelocity: 2500, thenHoldForDuration: 0)
        sleep(2)

        let againJoin = app.buttons["Join Voice"].firstMatch
        let againGrip = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: againJoin.frame.minY - 20))
        againGrip.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)), withVelocity: 1500, thenHoldForDuration: 0)
        sleep(2)

        let header = app.buttons["Close"].firstMatch

        if header.exists {
            let headerPoint = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: header.frame.midY))
            headerPoint.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)), withVelocity: 1500, thenHoldForDuration: 0)
        }

        sleep(2)
    }
}
