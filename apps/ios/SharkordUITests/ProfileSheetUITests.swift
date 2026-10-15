import XCTest

// the profile sheet's corner buttons, against a local server:
//   TEST_RUNNER_SHARKORD_TEST_LOCAL_SERVER=http://localhost:4991 with the identity and password
//   variables as SignInUITests reads them
final class ProfileSheetUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCloseAndSettingsButtonsWork() throws {
        let environment = ProcessInfo.processInfo.environment

        guard
            let server = environment["SHARKORD_TEST_LOCAL_SERVER"],
            let identity = environment["SHARKORD_TEST_IDENTITY"],
            let password = environment["SHARKORD_TEST_PASSWORD"]
        else {
            throw XCTSkip("Set SHARKORD_TEST_LOCAL_SERVER, SHARKORD_TEST_IDENTITY and SHARKORD_TEST_PASSWORD to run.")
        }

        let app = XCUIApplication()

        app.launchEnvironment["SHARKORD_DEV_SERVER"] = server
        app.launchEnvironment["SHARKORD_DEV_IDENTITY"] = identity
        app.launchEnvironment["SHARKORD_DEV_PASSWORD"] = password
        app.launch()

        let userBar = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Online")).firstMatch

        XCTAssertTrue(userBar.waitForExistence(timeout: 20))
        userBar.tap()

        let editProfile = app.buttons["Edit Profile"]

        XCTAssertTrue(editProfile.waitForExistence(timeout: 5))
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(editProfile.waitForNonExistence(timeout: 5), "close did not dismiss the profile")

        userBar.tap()
        XCTAssertTrue(editProfile.waitForExistence(timeout: 5))
        app.buttons["Settings"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5), "settings did not open")
    }
}
