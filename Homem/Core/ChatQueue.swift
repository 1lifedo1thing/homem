import Foundation
import Observation

enum ChatQueueKind: String, Codable, Sendable {
    case followUp = "follow-up-queue"
    case steer = "steer-queue"
}

struct ChatQueuedMessage: Identifiable {
    let value: JSONValue
    let kind: ChatQueueKind
    var id: String { kind.rawValue + ":" + itemID }
    var itemID: String { value["item_id"].string }
    var text: String { value["text"].string }
    var editable: Bool { value["status"] == "accepted" }
}

/// The server owns accepted items. Refresh on runtime changes and reconnects,
/// with a slow fallback while the conversation is on screen.
@MainActor @Observable final class ChatQueue {
    let api: APIClient
    let path: String
    var items: [ChatQueuedMessage] = []
    var steerSupported = false
    var error: String?
    private(set) var submitting = false
    private(set) var busy: Set<String> = []
    private var refreshVersion = 0
    private var refreshTask: Task<Void, Never>?
    private var eventRefreshTask: Task<Void, Never>?
    private struct Submission: Codable {
        let kind: ChatQueueKind
        let text: String
        let invocation: String
    }
    private var submission: Submission?
    private let submissionKey: String

    init(api: APIClient, path: String) {
        self.api = api; self.path = path
        submissionKey = "chat-queue|\(api.draftScope)|\(path)"
        if !api.isDemo, let saved = Keychain.read(submissionKey), let data = saved.data(using: .utf8) {
            submission = try? JSONDecoder().decode(Submission.self, from: data)
        }
    }
    func start() {
        stop()
        guard !api.isDemo else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard self != nil else { return }
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
            }
        }
    }
    func stop() {
        refreshTask?.cancel(); refreshTask = nil
        eventRefreshTask?.cancel(); eventRefreshTask = nil
        refreshVersion += 1
    }
    func scheduleRefresh() {
        eventRefreshTask?.cancel()
        eventRefreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            await self?.refresh()
        }
    }
    var unconfirmedText: String? { submission?.text }
    func retryKind(for text: String) -> ChatQueueKind? {
        submission?.text == text.trimmingCharacters(in: .whitespacesAndNewlines) ? submission?.kind : nil
    }
    func refresh() async {
        guard !api.isDemo, !submitting, busy.isEmpty else { return }
        refreshVersion += 1
        let version = refreshVersion
        do {
            let value = try await api.call(path + "/queue")
            guard version == refreshVersion, !Task.isCancelled else { return }
            items = Self.decode(value["steer"].array, kind: .steer) + Self.decode(value["follow_up"].array, kind: .followUp)
            steerSupported = value["steer_supported"].bool
        } catch {
            // A background refresh must not replace actionable mutation errors
            // or erase a queue during a temporary connection interruption.
        }
    }
    private static func decode(_ values: [JSONValue], kind: ChatQueueKind) -> [ChatQueuedMessage] {
        values.filter { !$0["item_id"].string.isEmpty && ["accepted", "claimed"].contains($0["status"].string) }
            .sorted { $0["position"].number < $1["position"].number }
            .map { ChatQueuedMessage(value: $0, kind: kind) }
    }
    func enqueue(text: String, kind: ChatQueueKind, attachments: [JSONValue] = []) async -> Bool {
        guard !submitting else { return false }
        guard attachments.isEmpty else {
            error = "Queued messages support text only. Your attachments are still in the composer.".localized
            return false
        }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if submission?.kind != kind || submission?.text != text {
            let next = Submission(kind: kind, text: text, invocation: UUID().uuidString.lowercased())
            do {
                let data = try JSONEncoder().encode(next)
                try Keychain.save(String(decoding: data, as: UTF8.self), account: submissionKey)
                submission = next
            } catch { self.error = error.localizedDescription; return false }
        }
        let invocation = submission!.invocation
        submitting = true; refreshVersion += 1; error = nil
        do {
            let value = try await api.call(path + "/" + kind.rawValue, method: "POST", body: ["text": .string(text), "invocation_id": .string(invocation)])
            submission = nil
            try? Keychain.save(nil, account: submissionKey)
            let newItems = Self.decode([value], kind: kind)
            for item in newItems {
                items.removeAll { $0.id == item.id }; items.append(item)
            }
            submitting = false
            await refresh()
            return true
        } catch {
            // Keep the invocation ID on uncertain failure. Retrying the same
            // draft cannot enqueue it twice if the first response was lost.
            self.error = error.localizedDescription; submitting = false
            return false
        }
    }
    func update(_ item: ChatQueuedMessage, text: String) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != item.text else { return }
        await mutate(item, suffix: "/" + item.itemID.pathComponent, method: "PATCH", body: ["text": .string(text)])
    }
    func remove(_ item: ChatQueuedMessage) async {
        await mutate(item, suffix: "/" + item.itemID.pathComponent, method: "DELETE")
    }
    func steer(_ item: ChatQueuedMessage) async {
        guard item.kind == .followUp, steerSupported else { return }
        await mutate(item, suffix: "/" + item.itemID.pathComponent + "/steer", method: "POST")
    }
    func canMove(_ item: ChatQueuedMessage, by offset: Int) -> Bool {
        let siblings = items.filter { $0.kind == item.kind && $0.editable }
        guard let index = siblings.firstIndex(where: { $0.id == item.id }) else { return false }
        return siblings.indices.contains(index + offset)
    }
    func move(_ item: ChatQueuedMessage, by offset: Int) async {
        var siblings = items.filter { $0.kind == item.kind && $0.editable }
        guard let index = siblings.firstIndex(where: { $0.id == item.id }), siblings.indices.contains(index + offset) else { return }
        siblings.remove(at: index); siblings.insert(item, at: index + offset)
        let next = index + offset + 1
        let before = siblings.indices.contains(next) ? siblings[next].itemID : ""
        await mutate(item, suffix: "/reorder", method: "PUT", body: ["item": ["item_id": .string(item.itemID)], "before": ["item_id": .string(before)]])
    }
    private func mutate(_ item: ChatQueuedMessage, suffix: String, method: String, body: JSONValue? = nil) async {
        guard item.editable, busy.isEmpty, !submitting else { return }
        busy.insert(item.id); refreshVersion += 1; error = nil
        do {
            let value = try await api.call(path + "/" + item.kind.rawValue + suffix, method: method, body: body)
            if method == "DELETE" { items.removeAll { $0.id == item.id } }
            else if suffix == "/reorder" {
                items.removeAll { $0.kind == item.kind }
                items += Self.decode(value["items"].array, kind: item.kind)
            } else if !value["item_id"].string.isEmpty {
                items.removeAll { $0.id == item.id }
                items += Self.decode([value], kind: method == "POST" ? .steer : item.kind)
            }
            items.sort {
                if $0.kind != $1.kind { return $0.kind == .steer }
                return $0.value["position"].number < $1.value["position"].number
            }
        } catch { self.error = error.localizedDescription }
        busy.remove(item.id)
        // An item may have been consumed while its menu was open. Reconcile
        // after either success or conflict instead of applying stale edits.
        await refresh()
    }
}
