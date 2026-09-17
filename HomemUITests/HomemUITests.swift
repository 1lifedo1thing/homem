import XCTest

final class HomemUITests: XCTestCase {
    @MainActor func testOfficialEmailIsPrimaryAndCustomServerRemainsAvailable() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-onboarding"]; app.launch()
        let official = app.buttons["officialSignIn"]
        XCTAssertTrue(official.waitForExistence(timeout: 10))
        if !official.isHittable { app.swipeUp() }
        official.tap()
        let email = app.textFields["officialEmail"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        let send = app.buttons["sendOfficialCode"]
        XCTAssertFalse(send.isEnabled)
        email.tap(); email.typeText("not-an-email")
        XCTAssertFalse(send.isEnabled)
        // Clear without sending any mail or touching a production account.
        email.tap(); email.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 12))
        email.typeText("person@example.com")
        XCTAssertTrue(send.isEnabled)
        capture(app, "Official email sign-in")
        app.buttons["Cancel"].tap()
        let custom = app.buttons["Use another server"]
        if !custom.isHittable { app.swipeUp() }
        custom.tap()
        app.swipeUp()
        XCTAssertTrue(app.textFields["serverAddress"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Use an access token"].exists)
        capture(app, "Third-party server sign-in")
    }
    @MainActor func testOnboardingAndScreenshots() throws {
        let app = XCUIApplication(); app.launchArguments = ["--ui-onboarding"]; app.launch()
        XCTAssertTrue(app.staticTexts["Your agents.\nRight at home."].waitForExistence(timeout: 10))
        capture(app, "Onboarding")
        let demo = app.buttons["exploreDemo"]
        if !demo.isHittable { app.swipeUp() }
        demo.tap()
        XCTAssertTrue(app.staticTexts["A place for your next idea"].waitForExistence(timeout: 5))
        capture(app, "Conversations")
        app.tabBars.buttons["Agents"].tap()
        XCTAssertTrue(app.staticTexts["Good company.\nGreat possibilities."].waitForExistence(timeout: 5))
        capture(app, "Agent overview")
        app.tabBars.buttons["Library"].tap()
        capture(app, "Library")
        app.buttons["Schedules"].tap()
        XCTAssertTrue(app.staticTexts["Morning perspective"].waitForExistence(timeout: 5))
        capture(app, "Schedules")
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testDemoConversationAndWorkspace() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.staticTexts["A place for your next idea"].waitForExistence(timeout: 10))
        app.staticTexts["A place for your next idea"].tap()
        let input = app.textFields["messageComposer"]
        XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("Hello from iOS")
        app.buttons["sendMessage"].tap()
        XCTAssertTrue(app.staticTexts["Hello from iOS"].waitForExistence(timeout: 5))
        let chat = XCTAttachment(screenshot: app.screenshot()); chat.name = "Native chat"; chat.lifetime = .keepAlways; add(chat)
        app.tabBars.buttons["Agents"].tap()
        XCTAssertTrue(app.staticTexts["Good company.\nGreat possibilities."].waitForExistence(timeout: 5))
        let agents = XCTAttachment(screenshot: app.screenshot()); agents.name = "Agents"; agents.lifetime = .keepAlways; add(agents)
        app.staticTexts["Atlas"].firstMatch.tap()
        app.buttons["Files, terminal & desktop"].tap()
        app.buttons["Files"].tap()
        XCTAssertTrue(app.staticTexts["AGENTS.md"].waitForExistence(timeout: 5))
        app.staticTexts["AGENTS.md"].tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue((app.textViews.firstMatch.value as? String ?? "").contains("workspace of your own"))
    }
    @MainActor func testCreateMemoryAndScheduleNavigation() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        app.tabBars.buttons["Library"].tap()
        app.buttons["Memories"].tap()
        XCTAssertTrue(app.staticTexts["Prefers thoughtful answers with concrete examples."].waitForExistence(timeout: 5))
        app.buttons["Add Memories"].tap()
        let message = app.textFields["Message"]
        XCTAssertTrue(message.waitForExistence(timeout: 5)); message.tap(); message.typeText("Remember this native app test")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Remember this native app test"].waitForExistence(timeout: 5))
        let library = XCTAttachment(screenshot: app.screenshot()); library.name = "Created memory"; library.lifetime = .keepAlways; add(library)
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Providers"].waitForExistence(timeout: 5))
        app.buttons["Providers"].tap()
        XCTAssertTrue(app.staticTexts["Example provider"].waitForExistence(timeout: 5))
    }
}
