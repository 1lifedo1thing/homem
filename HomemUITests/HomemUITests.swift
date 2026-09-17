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
        selectTab("Agents", in: app)
        XCTAssertTrue(app.buttons["createAgent"].waitForExistence(timeout: 5))
        capture(app, "Agent overview")
        selectTab("Library", in: app)
        capture(app, "Library")
        app.buttons["Schedules"].tap()
        XCTAssertTrue(app.staticTexts["Morning perspective"].waitForExistence(timeout: 5))
        capture(app, "Schedules")
    }
    @MainActor func testNewChatComposerAndKeyboardDismissal() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["New conversation"].waitForExistence(timeout: 10))
        app.buttons["New conversation"].tap()
        let message = app.textFields["newChatMessage"]
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["startConversation"].isEnabled)
        XCTAssertFalse(app.textFields["Acp Runtime Id"].exists)
        XCTAssertTrue(app.buttons["Attach"].exists)
        app.buttons["newChatRunLocation"].tap()
        XCTAssertTrue(app.buttons["Studio Mac"].waitForExistence(timeout: 3))
        capture(app, "Workspace icon dropdown")
        app.buttons["Studio Mac"].tap()
        let agentMenu = app.navigationBars["New chat"].buttons["agentPickerMenu"]
        XCTAssertEqual(agentMenu.value as? String, "Atlas")
        agentMenu.tap()
        capture(app, "Agent avatar dropdown")
        app.buttons["Mika"].tap()
        XCTAssertEqual(agentMenu.value as? String, "Mika")
        XCTAssertTrue(app.buttons["newChatRunLocation"].label.contains("Agent default"))
        capture(app, "Simple new chat")
        message.tap(); message.typeText("Plan a calm afternoon")
        app.buttons["startConversation"].tap()
        let composer = app.textFields["messageComposer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Plan a calm afternoon"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "This is a local demo reply.")).firstMatch.waitForExistence(timeout: 5))
        composer.tap(); composer.typeText("A follow-up")
        XCTAssertTrue(app.buttons["hideChatKeyboard"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Done"].exists)
        capture(app, "Keyboard composer")
        app.buttons["hideChatKeyboard"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
    }
    @MainActor func testDeleteAlertNamesConversationAndCancelPreservesIt() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let conversation = app.staticTexts["A weekend in Kyoto"]
        XCTAssertTrue(conversation.waitForExistence(timeout: 10))
        conversation.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()
        let alert = app.alerts["Delete conversation?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["“A weekend in Kyoto” will be permanently deleted."].exists)
        capture(app, "Centered delete confirmation")
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(conversation.exists)
    }
    @MainActor func testThemePreferencesPersist() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        selectTab("Settings", in: app)
        app.swipeUp()
        let appearance = app.buttons["appearancePicker"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 5))
        appearance.tap(); app.buttons["Dark"].tap()
        app.buttons["accentPicker"].tap(); app.buttons["Rose"].tap()
        app.terminate(); app.launch()
        selectTab("Settings", in: app); app.swipeUp()
        XCTAssertTrue(app.buttons["appearancePicker"].label.contains("Dark"))
        XCTAssertTrue(app.buttons["accentPicker"].label.contains("Rose"))
        selectTab("Chats", in: app); app.buttons["New conversation"].tap()
        XCTAssertTrue(app.textFields["newChatMessage"].waitForExistence(timeout: 5))
        app.textFields["newChatMessage"].tap(); app.textFields["newChatMessage"].typeText("A little color")
        capture(app, "Dark Rose new chat")
        app.buttons["Cancel"].tap()
        selectTab("Settings", in: app)
        app.buttons["appearancePicker"].tap(); app.buttons["System"].tap()
        app.buttons["accentPicker"].tap(); app.buttons["System"].tap()
    }
    @MainActor private func selectTab(_ name: String, in app: XCUIApplication) {
        let compactTab = app.tabBars.buttons[name]
        if compactTab.exists { compactTab.tap() }
        else { app.buttons[name].firstMatch.tap() } // iPad uses a floating tab control.
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
        selectTab("Agents", in: app)
        XCTAssertTrue(app.buttons["createAgent"].waitForExistence(timeout: 5))
        let agents = XCTAttachment(screenshot: app.screenshot()); agents.name = "Agents"; agents.lifetime = .keepAlways; add(agents)
        app.staticTexts["Atlas"].firstMatch.tap()
        app.buttons["Files, terminal & desktop"].tap()
        capture(app, "Workspace tools")
        app.buttons["Files"].tap()
        XCTAssertTrue(app.staticTexts["AGENTS.md"].waitForExistence(timeout: 5))
        app.staticTexts["AGENTS.md"].tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue((app.textViews.firstMatch.value as? String ?? "").contains("workspace of your own"))
    }
    @MainActor func testCreateMemoryAndScheduleNavigation() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        selectTab("Library", in: app)
        app.buttons["Memories"].tap()
        XCTAssertTrue(app.staticTexts["Prefers thoughtful answers with concrete examples."].waitForExistence(timeout: 5))
        app.buttons["Add Memories"].tap()
        let message = app.textFields["Message"]
        XCTAssertTrue(message.waitForExistence(timeout: 5)); message.tap(); message.typeText("Remember this native app test")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Remember this native app test"].waitForExistence(timeout: 5))
        let library = XCTAttachment(screenshot: app.screenshot()); library.name = "Created memory"; library.lifetime = .keepAlways; add(library)
        selectTab("Settings", in: app)
        XCTAssertTrue(app.staticTexts["Providers"].waitForExistence(timeout: 5))
        app.buttons["Providers"].tap()
        XCTAssertTrue(app.staticTexts["Example provider"].waitForExistence(timeout: 5))
    }
}
