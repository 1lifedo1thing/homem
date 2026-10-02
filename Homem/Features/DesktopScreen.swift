import SwiftUI
#if !os(visionOS)
import WebRTC
#endif
import Observation

struct DesktopScreen: View {
    @Environment(AppStore.self) private var store
    var botID: String
    var initialViewOnly = false
    private func desktopModel(_ api: APIClient) -> DesktopModel {
        let model = DesktopModel(api: api, botID: botID)
        model.setViewOnly(initialViewOnly)
        return model
    }
    var body: some View {
        if let api = store.api { DesktopContent(model: desktopModel(api)).navigationTitle("Desktop".localized).navigationBarTitleDisplayMode(.inline) }
        else { EmptyState(title: "Desktop unavailable", symbol: "desktopcomputer", detail: "Connect to a server to use this agent’s desktop.").navigationTitle("Desktop".localized) }
    }
}

struct DesktopContent: View {
    #if os(visionOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(AppStore.self) private var store
    #endif
    @State var model: DesktopModel
    var embedded = false
    var isFullscreen = false
    var onClosePane: (() -> Void)? = nil
    @State private var keyboardVisible = false
    @State private var fullscreen = false
    @State private var modifiers = Set<UInt32>()
    @State private var dragging = false
    @State private var pointer = CGPoint.zero
    @State private var zoomResetID = 0
    @ScaledMetric(relativeTo: .body) private var controlRailWidth: CGFloat = Theme.controlSize + 12
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    private var showsPiPChoice: Bool { model.pictureInPicture.isActive && !model.pictureInPicture.duplicatesInline }

    var body: some View {
        VStack(spacing: 0) {
            if isFullscreen {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                        .accessibilityLabel("Exit fullscreen".localized)
                    Spacer()
                    Text("Desktop".localized).font(.headline)
                    Spacer()
                    DesktopModeButton(model: model)
                }.padding(.horizontal, 16).frame(minHeight: 44)
            } else if !embedded {
                HStack {
                    StatusIndicator(text: model.status, color: model.status == "Connected" ? .green : .orange)
                    Spacer()
                    DesktopModeButton(model: model)
                }.padding(.horizontal, 12)
            }
            if let error = model.error {
                ErrorBanner(message: error) { Task { model.disconnect(); await model.connect() } }.padding()
            }
            GeometryReader { geometry in
                let side = DesktopControlLayout.usesSideRail(viewport: geometry.size, remote: model.videoSize,
                                                           railWidth: controlRailWidth)
                desktopSurface
                    .padding(.trailing, side ? controlRailWidth : 0)
                    .padding(.bottom, side ? 0 : Theme.controlSize)
                    .overlay(alignment: side ? .trailing : .bottom) {
                        controls(vertical: side)
                            .frame(width: side ? controlRailWidth : nil, height: side ? nil : Theme.controlSize)
                            .frame(maxHeight: side ? .infinity : nil)
                    }
                    .allowsHitTesting(!showsPiPChoice)
                    .overlay { if showsPiPChoice { pictureInPictureChoice } }
            }
            if !model.viewOnly, model.status == "Connected", !fullscreen, !showsPiPChoice {
                RemoteKeyboard(isActive: $keyboardVisible, onText: { text in
                    model.type(text, modifiers: modifiers.sorted()); modifiers.removeAll()
                }, onKey: { code, hardwareModifiers in
                    model.key(code, modifiers: Array(Set(hardwareModifiers).union(modifiers)).sorted())
                    modifiers.removeAll()
                }).frame(width: 1, height: 1).clipped()
            }
        }
        .background(Color(uiColor: .systemBackground))
        .fullScreenCover(isPresented: $fullscreen) {
            DesktopContent(model: model, isFullscreen: true, onClosePane: onClosePane)
        }
        .toolbar(embedded ? .automatic : .hidden, for: .tabBar)
        .task { if !isFullscreen { await model.connect() } }
        .onAppear { model.pictureInPicture.viewerAppeared() }
        .alert("Picture in Picture".localized, isPresented: Binding(get: { model.pictureInPicture.error != nil }, set: { if !$0 { model.pictureInPicture.error = nil } })) {
            Button("OK".localized, role: .cancel) { model.pictureInPicture.error = nil }
        } message: { Text(model.pictureInPicture.error ?? "") }
        .onDisappear {
            model.pictureInPicture.viewerDisappeared(allowDisconnect: !fullscreen)
            keyboardVisible = false; modifiers.removeAll(); releasePointer()
            if !isFullscreen, !fullscreen, !model.pictureInPicture.keepsConnectionAlive { model.disconnect() }
        }
        .onChange(of: model.viewOnly) { _, viewOnly in
            if viewOnly { keyboardVisible = false; modifiers.removeAll(); dragging = false }
        }
        .onChange(of: showsPiPChoice) { _, showing in
            if showing { keyboardVisible = false; modifiers.removeAll(); releasePointer() }
        }
        .onChange(of: model.status) { _, status in
            if status != "Connected" { keyboardVisible = false; modifiers.removeAll(); dragging = false }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { keyboardVisible = false; modifiers.removeAll(); releasePointer() }
            guard !isFullscreen else { return }
            if phase == .background, !model.pictureInPicture.keepsConnectionAlive { model.disconnect() }
            if phase == .active { Task { await model.connect() } }
        }
    }

    private var pictureInPictureChoice: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 12) {
                    Label("Desktop is in Picture in Picture".localized, systemImage: "pip")
                        .font(.headline).multilineTextAlignment(.center)
                    Button((onClosePane == nil ? "Close view, keep PiP" : "Close pane, keep PiP").localized) {
                        if let onClosePane {
                            if isFullscreen { dismiss() }
                            onClosePane()
                        } else { dismiss() }
                    }.buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("closePaneKeepPiP")
                    Button("Show in both".localized) { model.pictureInPicture.showInBoth() }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("duplicateDesktopPiP")
                }.frame(maxWidth: .infinity).padding(20)
                    .frame(minHeight: geometry.size.height)
            }
        }.background(Theme.canvas)
    }

    private var desktopSurface: some View {
        ZStack {
            Color.black
            if fullscreen { Color.clear }
            else if model.runtimeImage != nil || model.track != nil {
                DesktopViewport(model: model, resetID: zoomResetID) { point, mask in
                    pointer = point; dragging = mask != 0
                    model.pointer(point, mask: mask)
                }
                .overlay { if !model.hasVideo { ProgressView().tint(.white).allowsHitTesting(false) } }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "desktopcomputer").font(.largeTitle)
                    Text(model.status.localized)
                    if model.error == nil { ProgressView().tint(.white) }
                }.foregroundStyle(.white.opacity(0.7))
            }
        }.clipped()
    }

    private func controls(vertical: Bool) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
        return layout {
            Button { keyboardVisible.toggle() } label: {
                Image(systemName: keyboardVisible ? "keyboard.chevron.compact.down" : "keyboard")
                    .frame(width: Theme.controlSize, height: Theme.controlSize)
            }
            .accessibilityLabel((keyboardVisible ? "Hide keyboard" : "Show keyboard").localized)
            .disabled(model.viewOnly || model.status != "Connected")
            if !model.viewOnly {
                ScrollView(vertical ? .vertical : .horizontal, showsIndicators: false) {
                    layout {
                        keyButton("Esc", 0xff1b)
                        keyButton("Tab", 0xff09)
                        modifierButton("Ctrl", 0xffe3)
                        modifierButton("Alt", 0xffe9)
                        modifierButton("Shift", 0xffe1)
                        modifierButton("Super", 0xffeb)
                        keyButton("←", 0xff51, label: "Left arrow")
                        keyButton("↑", 0xff52, label: "Up arrow")
                        keyButton("↓", 0xff54, label: "Down arrow")
                        keyButton("→", 0xff53, label: "Right arrow")
                        Menu {
                            Button("Backspace".localized) { sendKey(0xff08) }
                            Button("Delete".localized) { sendKey(0xffff) }
                            Button("Return".localized) { sendKey(0xff0d) }
                            Button("Home".localized) { sendKey(0xff50) }
                            Button("End".localized) { sendKey(0xff57) }
                            Button("Page up".localized) { sendKey(0xff55) }
                            Button("Page down".localized) { sendKey(0xff56) }
                            Button("Insert".localized) { sendKey(0xff63) }
                            Button("Ctrl + Alt + Delete") { model.key(0xffff, modifiers: [0xffe3, 0xffe9]); modifiers.removeAll() }
                            ForEach(1...12, id: \.self) { number in
                                Button("F\(number)") { sendKey(0xffbd + UInt32(number)) }
                            }
                        } label: { Image(systemName: "ellipsis").frame(width: Theme.controlSize, height: Theme.controlSize) }
                        .accessibilityLabel("More keys".localized)
                    }
                }.disabled(model.status != "Connected")
            } else { Spacer(minLength: 0) }
            Menu {
                Button("Right click".localized) { model.pointer(pointer, mask: 4); model.pointer(pointer, mask: 0) }
                    .disabled(model.viewOnly || model.status != "Connected")
                Button("Scroll up".localized) { model.pointer(pointer, mask: 8); model.pointer(pointer, mask: 0) }
                    .disabled(model.viewOnly || model.status != "Connected")
                Button("Scroll down".localized) { model.pointer(pointer, mask: 16); model.pointer(pointer, mask: 0) }
                    .disabled(model.viewOnly || model.status != "Connected")
                Button("Fit to screen".localized, systemImage: "arrow.down.right.and.arrow.up.left") { zoomResetID += 1 }
                Button("Reconnect desktop".localized) { Task { model.disconnect(); await model.connect() } }
            } label: { Image(systemName: "computermouse").frame(width: Theme.controlSize, height: Theme.controlSize) }
            .accessibilityLabel("Desktop controls".localized)
            if model.pictureInPicture.isSupported {
                Button {
                    keyboardVisible = false; modifiers.removeAll(); releasePointer()
                    if model.pictureInPicture.keepsConnectionAlive { model.pictureInPicture.stop() }
                    else { model.pictureInPicture.start() }
                } label: {
                    Image(systemName: model.pictureInPicture.keepsConnectionAlive ? "pip.exit" : "pip.enter").frame(width: Theme.controlSize, height: Theme.controlSize)
                }
                .accessibilityLabel((model.pictureInPicture.keepsConnectionAlive ? "Close Picture in Picture" : "Picture in Picture").localized)
                .accessibilityIdentifier("desktopPictureInPicture")
                .disabled(!model.hasVideo && !model.pictureInPicture.keepsConnectionAlive)
            }
            #if os(visionOS)
            Button {
                guard let route = store.workspaceWindowRoute(botID: model.botID, tool: .desktop, viewOnly: model.viewOnly) else { return }
                openWindow(id: "workspace-tool", value: route)
            } label: { Image(systemName: "macwindow.badge.plus").frame(width: Theme.controlSize, height: Theme.controlSize) }
                .accessibilityLabel("Open in new window".localized)
            #else
            if !isFullscreen {
                Button { keyboardVisible = false; modifiers.removeAll(); releasePointer(); fullscreen = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: Theme.controlSize, height: Theme.controlSize)
                }.accessibilityLabel("Fullscreen".localized)
            }
            #endif
        }.buttonStyle(.borderless).padding(vertical ? .vertical : .horizontal, 6).background(.bar)
    }
    private func keyButton(_ title: String, _ code: UInt32, label: String? = nil) -> some View {
        Button { sendKey(code) } label: { Text(title).font(.system(.caption, design: .monospaced)).frame(minWidth: Theme.controlSize, minHeight: Theme.controlSize) }
            .accessibilityLabel((label ?? title).localized)
    }
    private func modifierButton(_ title: String, _ code: UInt32) -> some View {
        Button {
            if modifiers.contains(code) { modifiers.remove(code) } else { modifiers.insert(code) }
        } label: {
            Text(title).font(.system(.caption, design: .monospaced)).frame(minWidth: Theme.controlSize, minHeight: Theme.controlSize)
                .background(modifiers.contains(code) ? Color.accentColor.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.accessibilityValue((modifiers.contains(code) ? "On" : "Off").localized)
    }
    private func sendKey(_ code: UInt32) { model.key(code, modifiers: modifiers.sorted()); modifiers.removeAll() }
    private func releasePointer() { if dragging { model.pointer(pointer, mask: 0); dragging = false } }
}

/// UIKit owns composition and candidate selection; only committed text goes to the host.
struct RemoteKeyboard: UIViewRepresentable {
    @Binding var isActive: Bool
    let onText: (String) -> Void
    let onKey: (UInt32, [UInt32]) -> Void
    func makeUIView(context: Context) -> RemoteKeyboardView { RemoteKeyboardView() }
    func updateUIView(_ view: RemoteKeyboardView, context: Context) {
        view.onText = onText; view.onKey = onKey
        view.onDismiss = { if isActive { isActive = false } }
        if isActive, !view.isFirstResponder {
            // SwiftUI may attach this view to its window after updateUIView returns.
            view.wantsKeyboard = true
            DispatchQueue.main.async { [weak view] in
                guard let view, view.wantsKeyboard, view.window != nil else { return }
                view.becomeFirstResponder()
            }
        } else if !isActive { view.wantsKeyboard = false; view.resignFirstResponder() }
    }
    static func dismantleUIView(_ view: RemoteKeyboardView, coordinator: ()) {
        view.wantsKeyboard = false; view.onDismiss = nil; view.resignFirstResponder()
    }
}

final class RemoteKeyboardView: UITextView, UITextViewDelegate {
    var onText: ((String) -> Void)?
    var onKey: ((UInt32, [UInt32]) -> Void)?
    var onDismiss: (() -> Void)?
    var wantsKeyboard = false
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        delegate = self
        autocorrectionType = .no; autocapitalizationType = .none; spellCheckingType = .no
        smartQuotesType = .no; smartDashesType = .no; smartInsertDeleteType = .no
        textContentType = nil; backgroundColor = .clear; textColor = .clear; tintColor = .clear
        isScrollEnabled = false
        #if !os(visionOS)
        inputAssistantItem.leadingBarButtonGroups = []; inputAssistantItem.trailingBarButtonGroups = []
        #endif
        accessibilityLabel = "Type on remote desktop".localized
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func textViewDidChange(_ textView: UITextView) { flushCommittedText() }
    override func unmarkText() { super.unmarkText(); flushCommittedText() }
    func flushCommittedText() {
        guard markedTextRange == nil, !text.isEmpty else { return }
        let committed = text!
        text = ""
        onText?(committed)
    }
    override func deleteBackward() {
        if markedTextRange != nil || !text.isEmpty { super.deleteBackward() }
        else { onKey?(0xff08, []) }
    }
    func textViewDidEndEditing(_ textView: UITextView) { text = ""; onDismiss?() }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        for press in presses {
            guard let key = press.key, markedTextRange == nil else { unhandled.insert(press); continue }
            let special: UInt32?
            switch key.keyCode {
            case .keyboardEscape: special = 0xff1b
            case .keyboardTab: special = 0xff09
            case .keyboardReturnOrEnter, .keypadEnter: special = 0xff0d
            case .keyboardDeleteOrBackspace: special = 0xff08
            case .keyboardDeleteForward: special = 0xffff
            case .keyboardLeftArrow: special = 0xff51
            case .keyboardUpArrow: special = 0xff52
            case .keyboardRightArrow: special = 0xff53
            case .keyboardDownArrow: special = 0xff54
            case .keyboardHome: special = 0xff50
            case .keyboardEnd: special = 0xff57
            case .keyboardPageUp: special = 0xff55
            case .keyboardPageDown: special = 0xff56
            case .keyboardInsert: special = 0xff63
            case .keyboardF1, .keyboardF2, .keyboardF3, .keyboardF4, .keyboardF5, .keyboardF6, .keyboardF7, .keyboardF8, .keyboardF9, .keyboardF10, .keyboardF11, .keyboardF12: special = 0xffbe + UInt32(key.keyCode.rawValue - UIKeyboardHIDUsage.keyboardF1.rawValue)
            default: special = nil
            }
            var modifiers: [UInt32] = []
            if key.modifierFlags.contains(.control) { modifiers.append(0xffe3) }
            if key.modifierFlags.contains(.alternate) { modifiers.append(0xffe9) }
            if key.modifierFlags.contains(.command) { modifiers.append(0xffeb) }
            if key.modifierFlags.contains(.shift) { modifiers.append(0xffe1) }
            if let special { onKey?(special, modifiers) }
            else if !key.modifierFlags.intersection([.control, .command]).isEmpty,
                    let scalar = key.charactersIgnoringModifiers.unicodeScalars.first {
                onKey?(RemoteKeyInput.keysym(scalar), modifiers)
            } else { unhandled.insert(press) }
        }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }
}
