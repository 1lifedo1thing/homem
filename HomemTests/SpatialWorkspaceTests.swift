import XCTest
@testable import Homem

@MainActor final class SpatialWorkspaceTests: XCTestCase {
    private func isolatedStore() -> AppStore {
        let name = "spatial-window-draft-tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return AppStore(vault: AccountVault(defaults: defaults), restore: false)
    }

    private func accountStore(official: Bool = false) throws -> (AppStore, AccountVault, SavedAccount, SavedAccount) {
        let name = "spatial-accounts." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let vault = AccountVault(defaults: defaults)
        let server = official ? OfficialServer.apiURL.absoluteString : "https://fixture.invalid/api"
        let first = SavedAccount(id: UUID().uuidString, server: server, identity: "first", name: "First Account", avatarURL: "", official: official)
        let second = SavedAccount(id: UUID().uuidString, server: server, identity: "second", name: "Second Account", avatarURL: "", official: official)
        addTeardownBlock {
            try? Keychain.save(nil, account: first.credentialKey)
            try? Keychain.save(nil, account: second.credentialKey)
            Keychain.removeDrafts(server: first.credentialKey); Keychain.removeDrafts(server: second.credentialKey)
            defaults.removePersistentDomain(forName: name)
        }
        for account in [first, second] {
            let secret: String
            if official {
                let cookie = HTTPCookie(properties: [.name: "session", .value: account.identity, .domain: "app.memoh.net", .path: "/", .secure: "TRUE"])!
                secret = try JSONEncoder().encode(OfficialSession(cookies: [cookie], teamID: "selected-team")).base64EncodedString()
            } else { secret = account.identity + "-token" }
            try vault.save(account, secret: secret)
        }
        vault.activate(first.id)
        return (AppStore(vault: vault), vault, first, second)
    }

    private func selectOffline(_ account: SavedAccount, in store: AppStore) async throws {
        let task = Task { try await store.switchAccount(account) }
        task.cancel()
        try await task.value
    }

    func testOpenWindowsRetainConnectionsAndPendingMessagesWhileLauncherSwitchesAccounts() async throws {
        let (store, vault, first, second) = try accountStore()
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubURLProtocol.self]
        let original = APIClient(baseURL: URL(string: first.server)!, token: "first-token", session: URLSession(configuration: config))
        original.credentialAccount = first.credentialKey
        store.api?.invalidate(); store.api = original
        defer { store.removeAccount(first); store.removeAccount(second); StubURLProtocol.handler = nil }
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer first-token")
            return (200, Data((request.url!.path.hasSuffix("/bots") ? "{\"items\":[]}" : "{\"id\":\"first\",\"display_name\":\"First Account\"}").utf8))
        }
        let destination = ChatDestination(botID: "same-agent", sessionID: "same-chat", title: "First chat", botName: "Agent",
            firstMessage: NewChatDraft(text: "Only for the first account", attachments: [], targetID: "native"))
        let route = try XCTUnwrap(store.chatWindowRoute(for: destination))
        let window = try XCTUnwrap(store.windowStore(for: route))
        let connectionID = window.connectionID
        let layout = window.chatWorkspace(for: "same-agent", windowID: route.id.uuidString)
        layout.snapshot.conversation = destination

        try await selectOffline(second, in: store)
        XCTAssertEqual(store.activeAccountID, second.id)
        XCTAssertTrue(window.api === original)
        XCTAssertFalse(original.signedOut)
        XCTAssertEqual(window.connectionID, connectionID)
        XCTAssertEqual(try window.api?.request("/bots").value(forHTTPHeaderField: "Authorization"), "Bearer first-token")
        XCTAssertEqual(try store.api?.request("/bots").value(forHTTPHeaderField: "Authorization"), "Bearer second-token")
        XCTAssertNil(store.takeWindowDraft(for: destination, windowID: route.id.uuidString))
        XCTAssertEqual(window.takeWindowDraft(for: destination, windowID: route.id.uuidString)?.text, "Only for the first account")
        XCTAssertNil(window.takeWindowDraft(for: destination, windowID: route.id.uuidString))

        // A live request and metadata refresh from the old window must continue
        // using its account without changing the launcher's persisted selection.
        await window.reload()
        XCTAssertNil(window.error)
        XCTAssertEqual(vault.activeID, second.id)
        XCTAssertEqual(store.activeAccountID, second.id)
        XCTAssertTrue(layout === window.chatWorkspace(for: "same-agent", windowID: route.id.uuidString))
        try await selectOffline(first, in: store)
        XCTAssertTrue(store.api === original)
        XCTAssertEqual(window.connectionID, connectionID)
    }

    func testRemovingOneAccountDisconnectsOnlyItsWindows() async throws {
        let (store, vault, first, second) = try accountStore()
        let firstRoute = try XCTUnwrap(store.workspaceWindowRoute(botID: "agent", tool: .terminal))
        let firstWindow = try XCTUnwrap(store.windowStore(for: firstRoute))
        let firstAPI = try XCTUnwrap(firstWindow.api)
        try await selectOffline(second, in: store)
        let secondRoute = try XCTUnwrap(store.workspaceWindowRoute(botID: "agent", tool: .files, directory: "/data/second"))
        let secondWindow = try XCTUnwrap(store.windowStore(for: secondRoute))
        let secondAPI = try XCTUnwrap(secondWindow.api)
        store.removeAccount(first)
        XCTAssertTrue(firstAPI.signedOut)
        XCTAssertNil(firstWindow.api)
        XCTAssertNil(try store.windowStore(for: firstRoute))
        XCTAssertFalse(secondAPI.signedOut)
        XCTAssertTrue(store.api === secondWindow.api)
        XCTAssertEqual(vault.activeID, second.id)
        XCTAssertEqual(Keychain.read(second.credentialKey), "second-token")
        store.signOut()
        XCTAssertTrue(secondAPI.signedOut)
        XCTAssertNil(secondWindow.api)
        XCTAssertNil(store.api)
    }

    func testRestoredWindowUsesItsOwnAccountAndWorkspaceWithoutSelectingThem() throws {
        let (store, vault, first, second) = try accountStore(official: true)
        let route = WorkspaceWindowRoute(scope: second.credentialKey + "|other-team", botID: "agent", tool: .desktop)
        let window = try XCTUnwrap(store.windowStore(for: route))
        defer { store.removeAccount(first); store.removeAccount(second) }
        let request = try XCTUnwrap(window.api).request("/bots")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "session=second")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Team-ID"), "other-team")
        XCTAssertEqual(store.activeAccountID, first.id)
        XCTAssertEqual(vault.activeID, first.id)
        XCTAssertEqual(OfficialSession.restore(account: second.credentialKey)?.teamID, "selected-team")
        XCTAssertTrue(try store.windowStore(for: route)?.api === window.api)
        XCTAssertNil(try store.windowStore(for: WorkspaceWindowRoute(scope: "missing-account", botID: "agent", tool: .files)))
    }

    func testWorkspaceSwitchReusesOpenConnectionsAndAccountRemovalClosesEveryWorkspace() async throws {
        let (store, _, first, second) = try accountStore(official: true)
        defer { store.removeAccount(first); store.removeAccount(second) }
        let initial = try XCTUnwrap(store.api)
        let initialRoute = try XCTUnwrap(store.workspaceWindowRoute(botID: "agent", tool: .desktop))
        let initialWindow = try XCTUnwrap(store.windowStore(for: initialRoute))
        let otherRoute = WorkspaceWindowRoute(scope: first.credentialKey + "|other-team", botID: "agent", tool: .terminal)
        let otherWindow = try XCTUnwrap(store.windowStore(for: otherRoute))
        let otherAPI = try XCTUnwrap(otherWindow.api)
        let switchTask = Task { try await store.switchWorkspace(["team_id": "other-team", "name": "Other"]) }
        switchTask.cancel(); try await switchTask.value
        XCTAssertTrue(store.api === otherAPI)
        XCTAssertTrue(initialWindow.api === initial)
        XCTAssertFalse(initial.signedOut)
        XCTAssertEqual(initial.officialSession?.teamID, "selected-team")
        XCTAssertEqual(OfficialSession.restore(account: first.credentialKey)?.teamID, "other-team")
        store.signOut()
        XCTAssertNil(initialWindow.api)
        XCTAssertNil(otherWindow.api)
        XCTAssertTrue(initial.signedOut)
        XCTAssertTrue(otherAPI.signedOut)
        XCTAssertNotNil(Keychain.read(second.credentialKey))
    }

    func testWindowsKeepIndependentConversationsAndLayoutsAcrossRestoration() throws {
        let name = "spatial-workspace-tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let vault = AccountVault(defaults: defaults)
        let store = AppStore(vault: vault, restore: false)
        store.api = APIClient(baseURL: URL(string: "https://fixture.invalid/api")!)
        let first = store.chatWorkspace(for: "agent", windowID: "one")
        let second = store.chatWorkspace(for: "agent", windowID: "two")
        first.snapshot.conversation = ChatDestination(botID: "agent", sessionID: "chat-a", title: "A", botName: "Agent")
        first.snapshot.panes = [WorkspacePane(tool: .files, directory: "/data/project")]
        first.snapshot.arrangement = .rows
        second.snapshot.conversation = ChatDestination(botID: "agent", sessionID: "chat-b", title: "B", botName: "Agent")
        XCTAssertEqual(first.snapshot.conversation?.sessionID, "chat-a")
        XCTAssertTrue(second.snapshot.panes.isEmpty)
        XCTAssertTrue(first === store.chatWorkspace(for: "agent", windowID: "one"))
        let restored = AppStore(vault: vault, restore: false)
        restored.api = APIClient(baseURL: URL(string: "https://fixture.invalid/api")!)
        XCTAssertEqual(restored.chatWorkspace(for: "agent", windowID: "one").snapshot, first.snapshot)
        XCTAssertEqual(restored.chatWorkspace(for: "agent", windowID: "two").snapshot.conversation?.sessionID, "chat-b")
        XCTAssertNil(store.chatWorkspace(for: "agent").snapshot.conversation)
    }

    func testWindowRestorationNeverCarriesAnUnsentMessageOrAttachments() throws {
        let chat = ChatDestination(botID: "agent", sessionID: "chat", title: "Chat", botName: "Agent",
            firstMessage: NewChatDraft(text: "private draft", attachments: [["data": "private attachment"]], targetID: "native"))
        let route = WorkspaceWindowRoute(scope: "account-one", botID: "agent", tool: .chat, conversation: chat)
        XCTAssertNil(route.conversation?.firstMessage)
        let another = WorkspaceWindowRoute(scope: route.scope, botID: route.botID, tool: .chat, conversation: chat)
        XCTAssertNotEqual(route.id, another.id, "Opening another window must get independent layout state")
        let data = try JSONEncoder().encode(route)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("private"))
        XCTAssertEqual(try JSONDecoder().decode(WorkspaceWindowRoute.self, from: data), route)
    }

    func testNewWindowHandsOffItsDraftOnlyOnceToTheMatchingConversation() throws {
        let store = isolatedStore()
        store.api = APIClient(baseURL: URL(string: "https://fixture.invalid/api")!)
        let draft = NewChatDraft(text: "First message", attachments: [["name": "note.txt", "base64": "private attachment"]], targetID: "native")
        let destination = ChatDestination(botID: "agent", sessionID: "new-chat", title: "New chat", botName: "Agent", firstMessage: draft)
        let route = try XCTUnwrap(store.chatWindowRoute(for: destination))
        let restored = try JSONDecoder().decode(WorkspaceWindowRoute.self, from: JSONEncoder().encode(route))
        let chat = try XCTUnwrap(restored.conversation)
        XCTAssertNil(chat.firstMessage)
        XCTAssertNil(store.takeWindowDraft(for: chat, windowID: UUID().uuidString))
        var otherChat = chat; otherChat.sessionID = "other"
        XCTAssertNil(store.takeWindowDraft(for: otherChat, windowID: route.id.uuidString))
        XCTAssertEqual(store.takeWindowDraft(for: chat, windowID: route.id.uuidString), draft)
        XCTAssertNil(store.takeWindowDraft(for: chat, windowID: route.id.uuidString))
        let restoredStore = isolatedStore()
        restoredStore.api = APIClient(baseURL: URL(string: "https://fixture.invalid/api")!)
        XCTAssertNil(restoredStore.takeWindowDraft(for: chat, windowID: route.id.uuidString))
    }

    func testWindowDraftCannotCrossAccountsAndIsDiscardedOnSignOut() throws {
        let store = isolatedStore()
        store.api = APIClient(baseURL: URL(string: "https://fixture.invalid/api")!)
        let destination = ChatDestination(botID: "agent", sessionID: "chat", title: "Chat", botName: "Agent",
            firstMessage: NewChatDraft(text: "Private", attachments: [], targetID: "native"))
        let route = try XCTUnwrap(store.chatWindowRoute(for: destination))
        store.api?.credentialAccount = "different-account"
        XCTAssertNil(store.takeWindowDraft(for: destination, windowID: route.id.uuidString))
        store.signOut()
        store.api = APIClient(baseURL: URL(string: "https://fixture.invalid/api")!)
        XCTAssertNil(store.takeWindowDraft(for: destination, windowID: route.id.uuidString))
    }

    func testWindowRequiresItsOriginalAccountAndRetainsToolContext() throws {
        let api = APIClient(baseURL: URL(string: "https://server.example/api")!, token: "unused")
        api.credentialAccount = "account-one"
        let route = WorkspaceWindowRoute(scope: api.draftScope, botID: "agent", tool: .files,
            directory: "/data/project", viewOnly: true)
        XCTAssertTrue(route.belongs(to: api))
        XCTAssertFalse(route.belongs(to: nil))
        api.credentialAccount = "account-two"
        XCTAssertFalse(route.belongs(to: api))
        let restored = try JSONDecoder().decode(WorkspaceWindowRoute.self, from: JSONEncoder().encode(route))
        XCTAssertEqual(restored.directory, "/data/project")
        XCTAssertTrue(restored.viewOnly)
    }

    func testSplitReflowsAtMinimumReadableWidthAndRetainsAllPanes() {
        let threshold = Theme.minimumPaneWidth * 2 + Theme.paneGap
        XCTAssertFalse(ChatSplitLayout.usesColumns(width: threshold - 1))
        XCTAssertTrue(ChatSplitLayout.usesColumns(width: threshold))
        for width in [640.0, 960.0, 1280.0, 1800.0] {
            for count in 1...6 {
                let layout = WorkspaceGeometry.make(size: CGSize(width: width, height: 700), count: count, arrangement: .automatic)
                XCTAssertEqual(layout.frames.count, count)
                for (index, frame) in layout.frames.enumerated() {
                    XCTAssertGreaterThanOrEqual(frame.width, min(width, Theme.minimumPaneWidth) - 0.01)
                    XCTAssertTrue(CGRect(origin: .zero, size: layout.size).insetBy(dx: -0.01, dy: -0.01).contains(frame))
                    for other in layout.frames.dropFirst(index + 1) { XCTAssertFalse(frame.intersects(other)) }
                }
            }
        }
    }
}
