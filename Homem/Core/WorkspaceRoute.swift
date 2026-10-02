import Foundation

struct ChatDestination: Hashable, Codable {
    var botID: String; var sessionID: String; var title: String; var botName: String
    var firstMessage: NewChatDraft? = nil
    enum CodingKeys: String, CodingKey { case botID, sessionID, title, botName }
}


struct NewChatDraft: Hashable {
    var text: String
    var attachments: [JSONValue]
    var targetID: String
}


/// Window values contain navigation only; credentials and unsent messages never
/// cross the scene restoration boundary. The ID restores this specific window.
struct WorkspaceWindowRoute: Codable, Hashable {
    var id = UUID()
    var scope: String
    var botID: String
    var tool: ChatWorkspaceTool
    var conversation: ChatDestination?
    var directory: String
    var viewOnly: Bool

    init(scope: String, botID: String, tool: ChatWorkspaceTool, conversation: ChatDestination? = nil,
         directory: String = "/data", viewOnly: Bool = true) {
        self.scope = scope; self.botID = botID; self.tool = tool
        self.conversation = conversation
        self.conversation?.firstMessage = nil
        self.directory = directory; self.viewOnly = viewOnly
    }
    @MainActor func belongs(to api: APIClient?) -> Bool { api?.draftScope == scope }
}

