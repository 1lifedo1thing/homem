import SwiftUI
import UniformTypeIdentifiers

struct WorkspaceView: View {
    @Environment(AppStore.self) private var store
    var botID: String
    var name: String
    var base: String { "/bots/\(botID.pathComponent)" }
    @State private var status: JSONValue = .null
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { AgentAvatar(name: name, size: 54); Spacer(); StatusPill(text: status.text("status", "state").nonEmpty ?? "Workspace", color: .teal) }
                    Text("A computer of their own.").font(.title2.weight(.semibold))
                    Text("Files, a terminal, and a desktop. Your agent’s world, within reach.").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
            }
            Section {
                NavigationLink("Files", systemImage: "folder") { FileBrowserView(botID: botID, path: "/data") }
                NavigationLink("Terminal", systemImage: "terminal") { TerminalScreen(botID: botID) }
                NavigationLink("Desktop", systemImage: "desktopcomputer") { DesktopScreen(botID: botID) }
            }
            Section("Manage") {
                ResourceLink(title: "Working directories", icon: "folder.badge.gearshape", spec: .bot(botID, "workdirs", title: "Working directories", detail: "/bots/{bot_id}/workdirs/{workdir_id}"))
                ResourceLink(title: "Snapshots", icon: "camera", spec: .bot(botID, "container/snapshots", title: "Snapshots"))
                NavigationLink("Dependencies", systemImage: "shippingbox") { DependenciesView(botID: botID) }
                NavigationLink("Resource metrics", systemImage: "chart.xyaxis.line") { ReadOnlyDocumentView(title: "Resource metrics", path: base + "/container/metrics") }
                OperationButton(title: "Create workspace", path: base + "/container", template: "/bots/{bot_id}/container", method: "POST")
                Button("Start workspace") { Task { await action("start") } }.disabled(busy)
                Button("Stop workspace") { Task { await action("stop") } }.disabled(busy)
                OperationButton(title: "Restore snapshot", path: base + "/container/snapshots/rollback", template: "/bots/{bot_id}/container/snapshots/rollback", method: "POST")
            }
            if let error { ErrorBanner(message: error) }
        }.navigationTitle(name + "’s workspace").navigationBarTitleDisplayMode(.inline).task { await load() }
    }
    func load() async { do { status = try await store.api?.call(base + "/container") ?? .null; error = nil } catch { self.error = error.localizedDescription } }
    func action(_ action: String) async {
        busy = true; defer { busy = false }
        do { _ = try await store.api?.call(base + "/container/" + action, method: "POST"); await load() } catch { self.error = error.localizedDescription }
    }
}

struct FileBrowserView: View {
    @Environment(\.appAccent) private var accent
    @Environment(AppStore.self) private var store
    var botID: String
    var path: String
    @State private var files: [Record] = []
    @State private var error: String?
    @State private var loading = false
    @State private var importFile = false
    @State private var newFolder = false
    @State private var newFile = false
    @State private var name = ""
    @State private var rename: Record?
    @State private var delete: Record?
    var base: String { "/bots/\(botID.pathComponent)/container/fs" }
    var body: some View {
        List {
            Section { Text(path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled) }
            if let error { ErrorBanner(message: error) { Task { await load() } } }
            ForEach(files) { file in
                NavigationLink {
                    if file.value["isDir"].bool { FileBrowserView(botID: botID, path: file.value["path"].string) }
                    else { FileEditorView(botID: botID, path: file.value["path"].string) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: file.value["isDir"].bool ? "folder.fill" : "doc.text").foregroundStyle(file.value["isDir"].bool ? accent : .secondary)
                        VStack(alignment: .leading, spacing: 4) { Text(file.value["name"].string); if !file.value["isDir"].bool { Text(ByteCountFormatter.string(fromByteCount: Int64(file.value["size"].number), countStyle: .file)).font(.caption).foregroundStyle(.secondary) } }
                    }.padding(.vertical, 4)
                }.contextMenu { Button("Rename", systemImage: "pencil") { rename = file; name = file.value["name"].string }; Button("Delete", systemImage: "trash", role: .destructive) { delete = file } }
            }
        }.navigationTitle(path == "/data" ? "Files" : (path as NSString).lastPathComponent).navigationBarTitleDisplayMode(.inline)
            .overlay { if loading { ProgressView() } else if files.isEmpty && error == nil { EmptyState(title: "A blank canvas", symbol: "folder", detail: "Upload a file or create something new.") } }
            .toolbar {
                Menu {
                    Button("Upload file", systemImage: "square.and.arrow.up") { importFile = true }
                    Button("New folder", systemImage: "folder.badge.plus") { name = ""; newFolder = true }
                    Button("New text file", systemImage: "doc.badge.plus") { name = ""; newFile = true }
                    NavigationLink("Archive & extract", systemImage: "archivebox") { OperationBrowser(prefix: "/bots/{bot_id}/container/fs", substitutions: ["bot_id": botID, "path": path]) }
                } label: { Image(systemName: "plus") }.accessibilityLabel("File actions")
            }
            .task { await load() }.refreshable { await load() }
            .fileImporter(isPresented: $importFile, allowedContentTypes: [.data]) { result in Task { do { let url = try result.get(); _ = try await store.api?.upload(path: base + "/upload", fileURL: url, destination: child(url.lastPathComponent)); await load() } catch { self.error = error.localizedDescription } } }
            .alert("New folder", isPresented: $newFolder) { TextField("Folder name", text: $name); Button("Create") { Task { await operation("mkdir", body: ["path": .string(child(name))]) } }; Button("Cancel", role: .cancel) {} }
            .alert("New text file", isPresented: $newFile) { TextField("File name", text: $name); Button("Create") { Task { await operation("write", body: ["path": .string(child(name)), "content": ""]) } }; Button("Cancel", role: .cancel) {} }
            .alert("Rename", isPresented: Binding(get: { rename != nil }, set: { if !$0 { rename = nil } })) { TextField("Name", text: $name); Button("Save") { if let file = rename { Task { await operation("rename", body: ["oldPath": file.value["path"], "newPath": .string(child(name))]) } } }; Button("Cancel", role: .cancel) { rename = nil } }
            .confirmationDialog("Delete \(delete?.value["name"].string ?? "file")?", isPresented: Binding(get: { delete != nil }, set: { if !$0 { delete = nil } }), titleVisibility: .visible) { Button("Delete", role: .destructive) { if let file = delete { Task { await operation("delete", body: ["path": file.value["path"], "recursive": file.value["isDir"]]) } } } } message: { Text("Folders are deleted with all their contents.") }
    }
    func child(_ name: String) -> String { path + (path.hasSuffix("/") ? "" : "/") + name }
    func load() async {
        loading = true; defer { loading = false }
        do { files = try await store.api?.call(base + "/list", query: ["path": path]).items.map(Record.init).sorted { a, b in if a.value["isDir"].bool != b.value["isDir"].bool { return a.value["isDir"].bool }; return a.title.localizedStandardCompare(b.title) == .orderedAscending } ?? []; error = nil } catch { self.error = error.localizedDescription }
    }
    func operation(_ suffix: String, body: JSONValue) async {
        do {
            if ["write", "mkdir", "rename"].contains(suffix), name.isEmpty || name.contains("/") || [".", ".."].contains(name) { throw ClientError.message("Enter a file or folder name without slashes.") }
            _ = try await store.api?.call(base + "/" + suffix, method: "POST", body: body); rename = nil; delete = nil; await load()
        } catch { self.error = error.localizedDescription }
    }
}

struct FileEditorView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var botID: String
    var path: String
    @State private var text = ""
    @State private var original = ""
    @State private var revision = ""
    @State private var error: String?
    @State private var loaded = false
    @State private var busy = false
    @State private var download: URL?
    @State private var preview = false
    @State private var discard = false
    var base: String { "/bots/\(botID.pathComponent)/container/fs" }
    var body: some View {
        VStack(spacing: 0) {
            if let error { ErrorBanner(message: error).padding() }
            if preview { ScrollView { MarkdownContent(text: text).padding() } }
            else { TextEditor(text: $text).font(.system(.body, design: .monospaced)).autocorrectionDisabled().textInputAutocapitalization(.never).padding(10).disabled(!loaded) }
            HStack { Text(text != original ? "Unsaved changes" : loaded ? "Saved" : "Loading…"); Spacer(); Text("\(text.utf8.count) bytes") }.font(.caption).foregroundStyle(.secondary).padding(12).background(.bar)
        }.navigationTitle((path as NSString).lastPathComponent).navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(text != original)
            .toolbar { if text != original { ToolbarItem(placement: .topBarLeading) { Button { discard = true } label: { Label("Files", systemImage: "chevron.left") } } } }
            .confirmationDialog("Discard unsaved changes?", isPresented: $discard, titleVisibility: .visible) { Button("Discard changes", role: .destructive) { dismiss() } }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if path.hasSuffix(".md") { Button { preview.toggle() } label: { Image(systemName: preview ? "pencil" : "eye") }.accessibilityLabel("Toggle preview") }
                    if let download { ShareLink(item: download) } else { Button { Task { await export() } } label: { Image(systemName: "square.and.arrow.down") }.accessibilityLabel("Download file") }
                    Button("Save") { Task { await save() } }.disabled(!loaded || text == original || busy)
                }
            }.task { await load() }
    }
    func load() async {
        do { let value = try await store.api?.call(base + "/read", query: ["path": path]) ?? .null; text = value["content"].string; original = text; revision = value["revision"].string; loaded = true } catch { self.error = error.localizedDescription }
    }
    func save() async {
        busy = true; defer { busy = false }
        do {
            let savedText = text
            let result = try await store.api?.call(base + "/write", method: "POST", body: ["path": .string(path), "content": .string(savedText), "expectedRevision": .string(revision)]) ?? .null
            original = savedText
            if !result["revision"].string.isEmpty { revision = result["revision"].string }
            else {
                let updated = try await store.api?.call(base + "/read", query: ["path": path])
                guard updated?["content"].string == savedText else { throw ClientError.message("The file changed on the server after saving. Reopen it before making further edits.") }
                revision = updated?["revision"].string ?? revision
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    func export() async {
        guard let api = store.api else { return }
        do {
            let data = api.isDemo ? Data(text.utf8) : try await api.perform(api.request(base + "/download", query: ["path": path]))
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent((path as NSString).lastPathComponent); try data.write(to: url); download = url
        } catch { self.error = error.localizedDescription }
    }
}

struct DependenciesView: View {
    @Environment(AppStore.self) private var store
    var botID: String
    @State private var records: [Record] = []
    @State private var error: String?
    var body: some View {
        List {
            ForEach(records) { record in
                NavigationLink(record.title) {
                    List {
                        JSONDetails(value: record.value)
                        NavigationLink("Manage dependency") { OperationBrowser(prefix: "/bots/{bot_id}/dependencies/{dep_id}", substitutions: ["bot_id": botID, "dep_id": record.id]) }
                    }.navigationTitle(record.title)
                }
            }
            OperationButton(title: "Check for updates", path: "/bots/\(botID.pathComponent)/dependencies/check-updates", template: "/bots/{bot_id}/dependencies/check-updates", method: "POST")
            if let error { ErrorBanner(message: error) }
        }.navigationTitle("Dependencies").task { do { records = try await store.api?.call("/bots/\(botID.pathComponent)/dependencies").items.map(Record.init) ?? [] } catch { self.error = error.localizedDescription } }
    }
}

struct BackupView: View {
    @Environment(AppStore.self) private var store
    var botID: String
    @State private var passphrase = ""
    @State private var busy = false
    @State private var error: String?
    @State private var exported: URL?
    @State private var importPicker = false
    @State private var imported: JSONValue = .null
    var body: some View {
        Form {
            Section("Export") {
                Text("Export the agent and its data as a portable backup. A passphrase encrypts sensitive backup content.").foregroundStyle(.secondary)
                SecureField("Passphrase (optional)", text: $passphrase)
                Button("Export backup") { Task { await export() } }.disabled(busy)
                if let exported { ShareLink("Save or share backup", item: exported) }
                NavigationLink("Backup contents") { ReadOnlyDocumentView(title: "Backup contents", path: "/bots/\(botID.pathComponent)/backup/summary") }
            }
            Section("Import") { Text("Import a backup as a new agent.").foregroundStyle(.secondary); Button("Choose backup ZIP") { importPicker = true }.disabled(busy) }
            if busy { ProgressView() }
            if let error { ErrorBanner(message: error) }
            if !imported.isNull { Section("Import result") { JSONDetails(value: imported) } }
        }.navigationTitle("Backups")
            .fileImporter(isPresented: $importPicker, allowedContentTypes: [.zip]) { result in Task { do { let url = try result.get(); try await importBackup(url) } catch { self.error = error.localizedDescription } } }
    }
    func export() async {
        guard let api = store.api else { return }; busy = true; defer { busy = false }
        do {
            guard !api.isDemo else { throw ClientError.message("Connect a server to export a real backup.") }
            let data = try await api.perform(api.request("/bots/\(botID.pathComponent)/backup/export", method: "POST", body: ["passphrase": .string(passphrase)]))
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("memoh-\(botID)-\(UUID().uuidString.prefix(8)).zip")
            try data.write(to: url, options: [.atomic, .completeFileProtection]); exported = url; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func importBackup(_ url: URL) async throws {
        guard let api = store.api, !api.isDemo else { throw ClientError.message("Connect a server to import a backup.") }
        busy = true; defer { busy = false }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let boundary = UUID().uuidString
        var payload = Data()
        for (name, value) in ["mode": "create", "passphrase": passphrase] { payload.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8)) }
        payload.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"backup.zip\"\r\nContent-Type: application/zip\r\n\r\n".utf8)); payload.append(data); payload.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = try api.request("/bots/backup/import", method: "POST"); request.httpBody = payload; request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        imported = try JSONDecoder().decode(JSONValue.self, from: await api.perform(request)); await store.reload(); error = nil
    }
}
