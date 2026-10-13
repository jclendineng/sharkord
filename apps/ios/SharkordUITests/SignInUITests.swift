import XCTest

// signs in to a real server the way a person, or Apple's reviewer, would. the server and the
// account come from the environment so nothing is committed:
//   TEST_RUNNER_SHARKORD_TEST_SERVER=chat.example.com TEST_RUNNER_SHARKORD_TEST_IDENTITY=...
//   TEST_RUNNER_SHARKORD_TEST_PASSWORD=... xcodebuild test -scheme Sharkord ...
// nothing here posts, edits or deletes, so it is safe to point at a live server
final class SignInUITests: XCTestCase {
    private struct Account {
        let server: String
        let identity: String
        let password: String
    }

    private var account: Account?

    override func setUpWithError() throws {
        continueAfterFailure = false

        let environment = ProcessInfo.processInfo.environment

        guard
            let server = environment["SHARKORD_TEST_SERVER"],
            let identity = environment["SHARKORD_TEST_IDENTITY"],
            let password = environment["SHARKORD_TEST_PASSWORD"]
        else {
            throw XCTSkip("Set SHARKORD_TEST_SERVER, SHARKORD_TEST_IDENTITY and SHARKORD_TEST_PASSWORD to run against a server.")
        }

        account = Account(server: server, identity: identity, password: password)
    }

    @MainActor
    private func launchSignedOut() -> XCUIApplication {
        let app = XCUIApplication()

        app.launchEnvironment["SHARKORD_DEV_SIGNED_OUT"] = "1"
        app.launch()

        return app
    }

    @MainActor
    private func launchSignedIn(_ account: Account) -> XCUIApplication {
        let app = XCUIApplication()

        app.launchEnvironment["SHARKORD_DEV_SERVER"] = "https://\(account.server)"
        app.launchEnvironment["SHARKORD_DEV_IDENTITY"] = account.identity
        app.launchEnvironment["SHARKORD_DEV_PASSWORD"] = account.password
        app.launch()

        return app
    }

    @MainActor
    private func snapshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())

        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // the path in the review notes: welcome, log in, the server, the account
    @MainActor
    func testSignInThroughTheLoginScreens() throws {
        let account = try XCTUnwrap(account)
        let app = launchSignedOut()

        XCTAssertTrue(app.staticTexts["WELCOME TO SHARKORD"].waitForExistence(timeout: 10))
        snapshot(app, "welcome")

        app.buttons["Log In"].firstMatch.tap()

        let serverField = app.textFields["serverAddress"]

        XCTAssertTrue(serverField.waitForExistence(timeout: 5))
        serverField.tap()
        serverField.typeText(account.server)
        snapshot(app, "server")
        app.buttons["Next"].tap()

        let usernameField = app.textFields["username"]

        XCTAssertTrue(usernameField.waitForExistence(timeout: 15))
        usernameField.tap()
        usernameField.typeText(account.identity)

        let passwordField = app.secureTextFields["password"]

        passwordField.tap()
        passwordField.typeText(account.password)
        snapshot(app, "login")

        app.buttons["Log In"].firstMatch.tap()

        XCTAssertTrue(app.buttons["Search"].waitForExistence(timeout: 20), "the channel list never showed")
        snapshot(app, "channels")
    }

    @MainActor
    func testAWrongPasswordIsRefused() throws {
        let account = try XCTUnwrap(account)
        let app = launchSignedOut()

        app.buttons["Log In"].firstMatch.tap()

        let serverField = app.textFields["serverAddress"]

        XCTAssertTrue(serverField.waitForExistence(timeout: 10))
        serverField.tap()
        serverField.typeText(account.server)
        app.buttons["Next"].tap()

        let usernameField = app.textFields["username"]

        XCTAssertTrue(usernameField.waitForExistence(timeout: 15))
        usernameField.tap()
        usernameField.typeText(account.identity)
        app.secureTextFields["password"].tap()
        app.secureTextFields["password"].typeText("not-the-password")
        app.buttons["Log In"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Invalid credentials"].waitForExistence(timeout: 15))
        snapshot(app, "refused")
    }

    // the screens a reviewer goes through once in: a channel, its pins, search and its tabs
    @MainActor
    func testTheMainScreensOpen() throws {
        let account = try XCTUnwrap(account)
        let app = launchSignedIn(account)

        let search = app.buttons["Search"]

        XCTAssertTrue(search.waitForExistence(timeout: 20), "the channel list never showed")
        snapshot(app, "channel-list")

        search.tap()

        for tab in ["Recent", "Members", "Channels", "Media", "Links", "Files"] {
            let button = app.buttons[tab]

            XCTAssertTrue(button.waitForExistence(timeout: 5), "no \(tab) tab")
            button.tap()
            snapshot(app, "search-\(tab.lowercased())")
        }

        app.navigationBars.buttons.firstMatch.tap()

        let channel = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'channel-'")).firstMatch

        XCTAssertTrue(channel.waitForExistence(timeout: 5), "no text channel to open")
        channel.tap()

        XCTAssertTrue(app.buttons["Pinned Messages"].waitForExistence(timeout: 10))
        snapshot(app, "chat")

        app.buttons["Pinned Messages"].tap()
        XCTAssertTrue(app.navigationBars["Pinned Messages"].waitForExistence(timeout: 10))
        snapshot(app, "pins")
        app.buttons["Done"].tap()

        app.buttons["Search"].firstMatch.tap()

        for tab in ["Recent", "Members", "Media", "Pins", "Links", "Files"] {
            let button = app.buttons[tab]

            XCTAssertTrue(button.waitForExistence(timeout: 5), "no \(tab) tab in channel search")
        }

        snapshot(app, "channel-search")
    }
}
