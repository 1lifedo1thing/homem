import SwiftUI
import AppKit
import SwiftTerm
import UniformTypeIdentifiers
import CoreImage

struct MacFiles: View {
    let api: APIClient
    let botID: String
    @State private var path: String
    @State private var location: String
    @State private var files: [Record] = []
    @State private var selection: String?
    @State private var editing: Record?
    @State private var importing = false
    @State private var deleting: Record?
    @State private var folder = false
    @State private var name = ""
    @State private var error: String?
    @State private var loading = false
    private var base: String { "/bots/\(botID.pathComponent)/container/fs" }
    init(api: APIClient, botID: String, initialPath: String) {
        self.api = api; self.botID = botID
        _path = State(initialValue: initialPath); _location = State(initialValue: initialPath)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { navigate((path as NSString).deletingLastPathComponent.nonEmpty ?? "/") } label: { Image(systemName: "chevron.up") }.disabled(path == "/").help("Parent folder")
                TextField("Location", text: $location).textFieldStyle(.roundedBorder).onSubmit { navigate(location) }
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }.help("Refresh files")
                Menu {
                    Button("Upload Files…") { importing = true }
                    Button("New Folder…") { name = ""; folder = true }
                } label: { Image(systemName: "plus") }.menuStyle(.borderlessButton).frame(width: 20)
            }.controlSize(.small).padding(10)
            if let error { MacError(message: error) { Task { await load() } } }
            Table(files, selection: $selection) {
                TableColumn("Name") { file in Label(file.title, systemImage: file.value["isDir"].bool ? "folder.fill" : "doc.text").lineLimit(1) }.width(min: 180, ideal: 320)
                TableColumn("Size") { file in Text(file.value["isDir"].bool ? "—" : ByteCountFormatter.string(fromByteCount: Int64(file.value["size"].number), countStyle: .file)).foregroundStyle(.secondary) }.width(80)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first, let file = files.first(where: { $0.id == id }) {
                    Button(file.value["isDir"].bool ? "Open Folder" : "Open File") { open(file) }
                    if !file.value["isDir"].bool { Button("Download…") { Task { await download(file) } } }
                    Button("Delete", role: .destructive) { deleting = file }
                }
            } primaryAction: { ids in if let id = ids.first, let file = files.first(where: { $0.id == id }) { open(file) } }
            .overlay { if loading { ProgressView() } else if files.isEmpty && error == nil { ContentUnavailableView("No files", systemImage: "folder", description: Text("Upload a file or create a folder.")) } }
            Divider()
            HStack { Text("\(files.count) items"); Spacer(); Text(path).lineLimit(1) }.font(.caption).foregroundStyle(.secondary).padding(10)
        }
        .task(id: path) { await load() }
        .sheet(item: $editing) { file in MacFileEditor(api: api, base: base, path: child(file.title)) { Task { await load() } } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            Task {
                do { for url in try result.get() { _ = try await api.upload(path: base + "/upload", fileURL: url, destination: path) }; await load() }
                catch { self.error = error.localizedDescription }
            }
        }
        .alert("New Folder", isPresented: $folder) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Create") { Task {
                do {
                    guard !name.isEmpty, !name.contains("/"), ![".", ".."].contains(name) else { throw ClientError.message("Enter a folder name without slashes.") }
                    _ = try await api.call(base + "/mkdir", method: "POST", body: ["path": .string(child(name))]); await load()
                } catch { self.error = error.localizedDescription }
            } }
        }
        .alert("Delete File?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) {
                if let file = deleting { let target = child(file.title); Task { do { _ = try await api.call(base + "/delete", method: "POST", body: ["path": .string(target)]); await load() } catch { self.error = error.localizedDescription } } }; deleting = nil
            }
        } message: { Text("This removes the selected item from the agent’s workspace.") }
    }
    private func child(_ name: String) -> String { path + (path.hasSuffix("/") ? "" : "/") + name }
    private func navigate(_ value: String) { path = value.hasPrefix("/") ? value : "/" + value; location = path; selection = nil }
    private func open(_ file: Record) { if file.value["isDir"].bool { navigate(child(file.title)) } else { editing = file } }
    private func load() async {
        let current = path; loading = true; defer { loading = false }
        do {
            let result = try await api.call(base + "/list", query: ["path": current]).items.map(Record.init)
            guard current == path else { return }
            files = result.sorted { a, b in a.value["isDir"].bool != b.value["isDir"].bool ? a.value["isDir"].bool : a.title.localizedStandardCompare(b.title) == .orderedAscending }; error = nil
        } catch { if current == path { self.error = error.localizedDescription } }
    }
    private func download(_ file: Record) async {
        do {
            let data = try await api.perform(api.request(base + "/download", query: ["path": child(file.title)]))
            let panel = NSSavePanel(); panel.nameFieldStringValue = file.title
            if await panel.begin() == .OK, let url = panel.url { try data.write(to: url, options: .atomic) }
        } catch { self.error = error.localizedDescription }
    }
}

struct MacFileEditor: View {
    let api: APIClient
    let base: String
    let path: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var original = ""
    @State private var revision = ""
    @State private var loaded = false
    @State private var busy = false
    @State private var discard = false
    @State private var preview = false
    @State private var error: String?
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text((path as NSString).lastPathComponent).font(.headline)
                Spacer()
                Toggle("Preview", isOn: $preview).toggleStyle(.button)
                Button("Save") { Task { await save() } }.disabled(!loaded || original == text || busy).keyboardShortcut("s")
                Button("Done") { if text != original { discard = true } else { dismiss() } }
            }.padding(16)
            Divider()
            if let error { MacError(message: error) }
            if preview { ScrollView { MacMarkdown(text: text).padding(24).frame(maxWidth: .infinity, alignment: .leading) } }
            else { TextEditor(text: $text).font(.system(size: 13, design: .monospaced)).padding(12).disabled(!loaded) }
            Divider()
            Text(text == original ? "Saved" : "Unsaved changes").font(.caption).foregroundStyle(.secondary).padding(10).frame(maxWidth: .infinity, alignment: .leading)
        }.frame(minWidth: 600, minHeight: 460).interactiveDismissDisabled(text != original)
        .task {
            do { let result = try await api.call(base + "/read", query: ["path": path]); text = result["content"].string; original = text; revision = result["revision"].string; loaded = true }
            catch { self.error = error.localizedDescription }
        }
        .alert("Discard Unsaved Changes?", isPresented: $discard) { Button("Keep Editing", role: .cancel) {}; Button("Discard", role: .destructive) { dismiss() } }
    }
    private func save() async {
        busy = true; defer { busy = false }
        do {
            let saved = text
            let result = try await api.call(base + "/write", method: "POST", body: ["path": .string(path), "content": .string(saved), "expectedRevision": .string(revision)])
            original = saved; revision = result["revision"].string; error = nil; onSave()
        } catch { self.error = error.localizedDescription }
    }
}

struct MacTerminal: View {
    let api: APIClient
    let botID: String
    @State private var connectionID = UUID()
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Workspace shell").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Reconnect") { connectionID = UUID() }.controlSize(.small) }.padding(10)
            MacTerminalView(api: api, botID: botID).id(connectionID)
        }
    }
}
struct MacTerminalView: NSViewRepresentable {
    let api: APIClient
    let botID: String
    func makeCoordinator() -> Coordinator { Coordinator(api: api, botID: botID) }
    func makeNSView(context: Context) -> TerminalView {
        let terminal = TerminalView(frame: .zero)
        terminal.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        terminal.nativeBackgroundColor = NSColor(calibratedWhite: 0.065, alpha: 1)
        terminal.nativeForegroundColor = NSColor(calibratedWhite: 0.9, alpha: 1)
        terminal.terminalDelegate = context.coordinator
        terminal.setAccessibilityLabel("Interactive workspace terminal")
        context.coordinator.terminal = terminal; context.coordinator.connect()
        return terminal
    }
    func updateNSView(_ nsView: TerminalView, context: Context) {}
    static func dismantleNSView(_ nsView: TerminalView, coordinator: Coordinator) { coordinator.close() }
    @MainActor final class Coordinator: NSObject, @preconcurrency TerminalViewDelegate {
        let api: APIClient
        let botID: String
        weak var terminal: TerminalView?
        var socket: URLSessionWebSocketTask?
        var receiver: Task<Void, Never>?
        var heartbeat: Task<Void, Never>?
        init(api: APIClient, botID: String) { self.api = api; self.botID = botID }
        func connect() {
            receiver = Task { [weak self] in
                guard let self else { return }
                do {
                    let socket = try await api.socket("/bots/\(botID.pathComponent)/container/terminal/ws", query: ["cols": "80", "rows": "24"])
                    guard !Task.isCancelled else { socket.cancel(with: .goingAway, reason: nil); return }
                    self.socket = socket
                    heartbeat = Task {
                        while !Task.isCancelled {
                            do { try await Task.sleep(for: .seconds(20)); try Task.checkCancellation() } catch { return }
                            socket.sendPing { error in if error != nil { socket.cancel(with: .goingAway, reason: nil) } }
                        }
                    }
                    defer { heartbeat?.cancel(); heartbeat = nil }
                    if let size = terminal?.getTerminal() { try await socket.send(.string("{\"type\":\"resize\",\"cols\":\(size.cols),\"rows\":\(size.rows)}")) }
                    while !Task.isCancelled {
                        switch try await socket.receive() {
                        case .data(let data): terminal?.feed(byteArray: Array(data)[...])
                        case .string(let text): terminal?.feed(text: text)
                        @unknown default: break
                        }
                    }
                } catch { if !Task.isCancelled { terminal?.feed(text: "\r\nConnection closed: \(error.localizedDescription)\r\nChoose Reconnect to open a new shell.\r\n") } }
            }
        }
        func close() { heartbeat?.cancel(); receiver?.cancel(); socket?.cancel(with: .goingAway, reason: nil); socket = nil }
        func send(source: TerminalView, data: ArraySlice<UInt8>) { Task { do { try await socket?.send(.data(Data(data))) } catch { source.feed(text: "\r\nSend failed: \(error.localizedDescription)\r\n") } } }
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) { Task { try? await socket?.send(.string("{\"type\":\"resize\",\"cols\":\(newCols),\"rows\":\(newRows)}")) } }
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) { if let url = URL(string: link), ["https", "http"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) } }
        func bell(source: TerminalView) { NSSound.beep() }
        func clipboardCopy(source: TerminalView, content: Data) {}
        func clipboardRead(source: TerminalView) -> Data? { nil }
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}

struct MacDesktop: View {
    @State private var model: DesktopModel
    init(api: APIClient, botID: String) { let model = DesktopModel(api: api, botID: botID); model.setViewOnly(true); _model = State(initialValue: model) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Circle().fill(model.status == "Connected" ? .green : .orange).frame(width: 6, height: 6)
                Text(model.status).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("View Only", isOn: Binding(get: { model.viewOnly }, set: { model.setViewOnly($0) })).toggleStyle(.checkbox)
                Button("Reconnect") { Task { model.disconnect(); await model.connect() } }
            }.controlSize(.small).padding(10)
            if let error = model.error { MacError(message: error) }
            MacDesktopSurface(model: model, image: model.runtimeImage, videoTrack: model.track, viewOnly: model.viewOnly).background(.black)
                .overlay { if !model.hasVideo && model.error == nil { ProgressView().tint(.white) } }
        }.task { await model.connect() }.onDisappear { model.disconnect() }
    }
}
struct MacDesktopSurface: NSViewRepresentable {
    let model: DesktopModel
    // Reading these in the SwiftUI body schedules updates for every RFB frame,
    // including frames arriving after the connection state stops changing.
    var image: NSImage?
    var videoTrack: RTCVideoTrack?
    var viewOnly: Bool
    func makeNSView(context: Context) -> MacRemoteView { let view = MacRemoteView(); view.model = model; return view }
    func updateNSView(_ view: MacRemoteView, context: Context) { view.update(model) }
    static func dismantleNSView(_ view: MacRemoteView, coordinator: ()) { view.close() }
}

/// Native mouse, wheel, hardware keyboard and WebRTC rendering in one AppKit surface.
@MainActor final class MacRemoteView: NSView, RTCVideoRenderer {
    weak var model: DesktopModel?
    private var track: RTCVideoTrack?
    private var frameImage: CGImage?
    private var buttons = 0
    private var point = CGPoint.zero
    private var focusObserver: NSObjectProtocol?
    private nonisolated static let imageContext = CIContext(options: [.cacheIntermediates: false])
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { model?.viewOnly == false }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
        focusObserver = nil
        if let window {
            focusObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.releasePointer() }
            }
        }
    }
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
        super.updateTrackingAreas()
    }
    func update(_ model: DesktopModel) {
        self.model = model
        if track !== model.track { track?.remove(self); frameImage = nil; track = model.track; track?.add(self) }
        if model.viewOnly { releasePointer() }
        needsDisplay = true
    }
    func close() {
        releasePointer(); track?.remove(self); track = nil
        if let focusObserver { NotificationCenter.default.removeObserver(focusObserver); self.focusObserver = nil }
    }
    nonisolated func setSize(_ size: CGSize) { Task { @MainActor in self.model?.videoSize = size; self.needsDisplay = true } }
    nonisolated func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame, let buffer = frame.buffer as? RTCCVPixelBuffer else { return }
        var image = CIImage(cvPixelBuffer: buffer.pixelBuffer)
        switch frame.rotation.rawValue { case 90: image = image.oriented(.right); case 180: image = image.oriented(.down); case 270: image = image.oriented(.left); default: break }
        guard let cg = Self.imageContext.createCGImage(image, from: image.extent) else { return }
        Task { @MainActor in self.frameImage = cg; self.model?.hasVideo = true; self.model?.videoSize = CGSize(width: cg.width, height: cg.height); self.needsDisplay = true }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill(); bounds.fill()
        guard let model, let image = model.runtimeImage?.cgImage(forProposedRect: nil, context: nil, hints: nil) ?? frameImage else { return }
        let size = CGSize(width: image.width, height: image.height)
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let rect = CGRect(x: (bounds.width - size.width * scale) / 2, y: (bounds.height - size.height * scale) / 2, width: size.width * scale, height: size.height * scale)
        NSImage(cgImage: image, size: size).draw(in: rect, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
    }
    private func pointer(_ event: NSEvent, mask: Int) {
        guard let model, !model.viewOnly, let remote = model.point(convert(event.locationInWindow, from: nil), in: bounds.size) else { return }
        point = remote; buttons = mask; model.pointer(remote, mask: mask)
    }
    private func releasePointer() { if buttons != 0 { model?.pointer(point, mask: 0); buttons = 0 } }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); pointer(event, mask: 1) }
    override func mouseUp(with event: NSEvent) { pointer(event, mask: 0); releasePointer() }
    override func rightMouseDown(with event: NSEvent) { pointer(event, mask: 4) }
    override func rightMouseUp(with event: NSEvent) { pointer(event, mask: 0); releasePointer() }
    override func mouseDragged(with event: NSEvent) { pointer(event, mask: buttons) }
    override func rightMouseDragged(with event: NSEvent) { pointer(event, mask: buttons) }
    override func mouseMoved(with event: NSEvent) { pointer(event, mask: 0) }
    override func scrollWheel(with event: NSEvent) { pointer(event, mask: event.scrollingDeltaY > 0 ? 8 : 16); pointer(event, mask: 0) }
    override func resignFirstResponder() -> Bool { releasePointer(); return super.resignFirstResponder() }
    override func keyDown(with event: NSEvent) {
        guard let model, !model.viewOnly else { return }
        let codes: [UInt16: UInt32] = [36: 0xff0d, 48: 0xff09, 51: 0xff08, 53: 0xff1b, 117: 0xffff, 123: 0xff51, 124: 0xff53, 125: 0xff54, 126: 0xff52, 115: 0xff50, 119: 0xff57, 116: 0xff55, 121: 0xff56]
        var modifiers: [UInt32] = []
        if event.modifierFlags.contains(.control) { modifiers.append(0xffe3) }
        if event.modifierFlags.contains(.option) { modifiers.append(0xffe9) }
        if event.modifierFlags.contains(.command) { modifiers.append(0xffeb) }
        if event.modifierFlags.contains(.shift) { modifiers.append(0xffe1) }
        if let code = codes[event.keyCode] { model.key(code, modifiers: modifiers) }
        else { model.type(event.charactersIgnoringModifiers ?? "", modifiers: modifiers) }
    }
}
