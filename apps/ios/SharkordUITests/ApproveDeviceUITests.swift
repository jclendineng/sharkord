import XCTest

// a device without a camera's sign in code, opened on a signed in one and approved there. run
// against a local server with TEST_RUNNER_SHARKORD_TEST_LOCAL_SERVER, the identity and password
// variables, and TEST_RUNNER_SHARKORD_TEST_REQUEST_TOKEN from a POST to /login/request
final class ApproveDeviceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testApprovingAnotherDevicesCode() throws {
        let environment = ProcessInfo.processInfo.environment

        guard
            let server = environment["SHARKORD_TEST_LOCAL_SERVER"],
            let identity = environment["SHARKORD_TEST_IDENTITY"],
            let password = environment["SHARKORD_TEST_PASSWORD"],
            let token = environment["SHARKORD_TEST_REQUEST_TOKEN"]
        else {
            throw XCTSkip("Set the local server, identity, password and request token to run.")
        }

        let app = XCUIApplication()

        app.launchEnvironment["SHARKORD_DEV_SERVER"] = server
        app.launchEnvironment["SHARKORD_DEV_IDENTITY"] = identity
        app.launchEnvironment["SHARKORD_DEV_PASSWORD"] = password
        app.launch()

        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Online")).firstMatch.waitForExistence(timeout: 20))

        var components = URLComponents()
        components.scheme = "sharkord"
        components.host = "approve"
        components.queryItems = [URLQueryItem(name: "server", value: server), URLQueryItem(name: "request", value: token)]

        app.open(try XCTUnwrap(components.url))

        // ios asks before a link opens an app
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let open = springboard.buttons["Open"]

        if open.waitForExistence(timeout: 5) {
            open.tap()
        }

        sleep(1)

        let early = XCTAttachment(screenshot: XCUIScreen.main.screenshot())

        early.name = "a-second-after-open"
        early.lifetime = .keepAlways
        add(early)

        let approve = app.buttons["Approve"]
        let found = approve.waitForExistence(timeout: 6)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())

        attachment.name = "after-open"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertTrue(found, "the approval sheet did not show")

        approve.tap()
        XCTAssertTrue(app.staticTexts["Signed in"].waitForExistence(timeout: 10), "approving did not finish")
    }

    // the device without a camera's side: past the server, a code to scan instead of a password
    @MainActor
    func testShowingACodeToScan() throws {
        guard let server = ProcessInfo.processInfo.environment["SHARKORD_TEST_LOCAL_SERVER"] else {
            throw XCTSkip("Set the local server to run.")
        }

        let app = XCUIApplication()

        app.launchEnvironment["SHARKORD_DEV_SIGNED_OUT"] = "1"
        app.launch()

        app.buttons["Log In"].firstMatch.tap()

        let field = app.textFields["serverAddress"]

        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(server)
        app.buttons["Next"].tap()

        let another = app.buttons["Sign In With Another Device"]

        XCTAssertTrue(another.waitForExistence(timeout: 10))
        another.tap()

        let waiting = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Waiting for approval")).firstMatch

        XCTAssertTrue(waiting.waitForExistence(timeout: 10), "no code was shown")

        let attachment = XCTAttachment(screenshot: app.screenshot())

        attachment.name = "code"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
