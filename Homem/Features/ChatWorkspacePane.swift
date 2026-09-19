import SwiftUI

private struct ExpandChatWorkspaceKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var expandChatWorkspace: () -> Void {
        get { self[ExpandChatWorkspaceKey.self] }
        set { self[ExpandChatWorkspaceKey.self] = newValue }
    }
}

enum ChatWorkspaceTool: String, CaseIterable, Identifiable, Codable {
    case chat, files, terminal, desktop
    var id: Self { self }
    var title: String { switch self { case .chat: "Chat"; case .files: "Files"; case .terminal: "Terminal"; case .desktop: "Desktop" } }
    var symbol: String { switch self { case .chat: "bubble.left"; case .files: "folder"; case .terminal: "terminal"; case .desktop: "desktopcomputer" } }
}

struct WorkspacePane: Identifiable, Equatable, Codable {
    var id = UUID()
    var tool: ChatWorkspaceTool
    var botID = ""
    var conversation: ChatDestination?
    var directory = "/data"
    var viewOnly = true
}

struct WorkspaceSnapshot: Codable, Equatable {
    var primaryID = UUID()
    var conversation: ChatDestination?
    var panes: [WorkspacePane] = []
    var arrangement = WorkspaceArrangement.automatic {
        didSet { docking = nil }
    }
    var docking: WorkspaceDockNode?
    var primaryIndex = 0
    var columnFraction = 0.45
    var rowFraction = 0.45
    var orderedIDs: [UUID] {
        var ids = panes.map(\.id)
        ids.insert(primaryID, at: min(max(0, primaryIndex), ids.count))
        return ids
    }
    mutating func move(_ source: UUID, to target: UUID) {
        var ids = orderedIDs
        guard let from = ids.firstIndex(of: source), let to = ids.firstIndex(of: target), from != to else { return }
        docking = nil
        ids.remove(at: from); ids.insert(source, at: to)
        primaryIndex = ids.firstIndex(of: primaryID) ?? 0
        let existing = Dictionary(uniqueKeysWithValues: panes.map { ($0.id, $0) })
        panes = ids.compactMap { existing[$0] }
    }
    mutating func remove(_ id: UUID) {
        let order = orderedIDs.filter { $0 != id }
        panes.removeAll { $0.id == id }
        docking = docking?.removing(id)
        primaryIndex = order.firstIndex(of: primaryID) ?? 0
    }
}

@MainActor @Observable final class AgentWorkspaceState {
    var snapshot: WorkspaceSnapshot { didSet { persist() } }
    private let key: String
    private let defaults: UserDefaults
    init(scope: String, botID: String, defaults: UserDefaults = .standard) {
        key = "agent-workspace." + Data((scope + "|" + botID).utf8).base64EncodedString()
        self.defaults = defaults
        snapshot = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(WorkspaceSnapshot.self, from: $0) } ?? WorkspaceSnapshot()
    }
    private func persist() {
        // ChatDestination deliberately excludes unsent attachments/messages from disk.
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: key) }
    }
}

enum WorkspaceArrangement: String, CaseIterable, Identifiable, Codable {
    case automatic, columns, rows, grid
    var id: Self { self }
    var title: String { switch self { case .automatic: "Automatic"; case .columns: "Side by side"; case .rows: "Stacked"; case .grid: "Grid" } }
}

enum WorkspaceDockEdge: CaseIterable {
    case left, right, top, bottom
    var horizontal: Bool { self == .left || self == .right }
    var before: Bool { self == .left || self == .top }
}

/// A saved split tree lets any pane sit beside or above another without losing
/// the identity (and connection) of the views it contains.
indirect enum WorkspaceDockNode: Codable, Equatable {
    case pane(UUID)
    case split(horizontal: Bool, fraction: Double, first: WorkspaceDockNode, second: WorkspaceDockNode)

    var ids: [UUID] {
        switch self {
        case .pane(let id): [id]
        case .split(_, _, let first, let second): first.ids + second.ids
        }
    }
    var minimum: CGSize {
        switch self {
        case .pane: CGSize(width: 300, height: 180)
        case .split(let horizontal, _, let first, let second):
            horizontal ? CGSize(width: first.minimum.width + second.minimum.width + 24, height: max(first.minimum.height, second.minimum.height))
                : CGSize(width: max(first.minimum.width, second.minimum.width), height: first.minimum.height + second.minimum.height + 24)
        }
    }
    func removing(_ id: UUID) -> Self? {
        switch self {
        case .pane(let value): return value == id ? nil : self
        case .split(let horizontal, let fraction, let first, let second):
            let a = first.removing(id), b = second.removing(id)
            if let a, let b { return .split(horizontal: horizontal, fraction: fraction, first: a, second: b) }
            return a ?? b
        }
    }
    func inserting(_ source: UUID, at target: UUID, edge: WorkspaceDockEdge) -> Self {
        switch self {
        case .pane(let id):
            guard id == target else { return self }
            return .split(horizontal: edge.horizontal, fraction: 0.5,
                          first: edge.before ? .pane(source) : self, second: edge.before ? self : .pane(source))
        case .split(let horizontal, let fraction, let first, let second):
            return .split(horizontal: horizontal, fraction: fraction,
                          first: first.inserting(source, at: target, edge: edge), second: second.inserting(source, at: target, edge: edge))
        }
    }
    func fraction(at path: [Bool]) -> Double {
        guard case .split(_, let fraction, let first, let second) = self else { return 0.5 }
        guard let next = path.first else { return fraction }
        return (next ? second : first).fraction(at: Array(path.dropFirst()))
    }
    mutating func setFraction(_ value: Double, at path: [Bool]) {
        guard case .split(let horizontal, let fraction, var first, var second) = self else { return }
        if let next = path.first {
            if next { second.setFraction(value, at: Array(path.dropFirst())) }
            else { first.setFraction(value, at: Array(path.dropFirst())) }
        }
        self = .split(horizontal: horizontal, fraction: path.isEmpty ? value : fraction, first: first, second: second)
    }
    static func matching(ids: [UUID], frames: [CGRect]) -> Self? {
        guard ids.count == frames.count, let id = ids.first else { return nil }
        if ids.count == 1 { return .pane(id) }
        for horizontal in [true, false] {
            for frame in frames {
                let boundary = horizontal ? frame.maxX : frame.maxY
                let first = frames.indices.filter { (horizontal ? frames[$0].maxX : frames[$0].maxY) <= boundary + 1 }
                let second = frames.indices.filter { (horizontal ? frames[$0].minX : frames[$0].minY) > boundary + 1 }
                guard !first.isEmpty, !second.isEmpty, first.count + second.count == ids.count,
                      let a = matching(ids: first.map { ids[$0] }, frames: first.map { frames[$0] }),
                      let b = matching(ids: second.map { ids[$0] }, frames: second.map { frames[$0] }) else { continue }
                return .split(horizontal: horizontal, fraction: 0.5, first: a, second: b)
            }
        }
        return nil
    }
    func geometry(size: CGSize, order: [UUID]) -> WorkspaceGeometry? {
        guard Set(ids) == Set(order), ids.count == order.count,
              size.width >= minimum.width, size.height >= minimum.height else { return nil }
        var frames: [UUID: CGRect] = [:]
        var dividers: [CGRect] = [], paths: [[Bool]] = [], extents: [CGFloat] = []
        func visit(_ node: Self, _ rect: CGRect, _ path: [Bool]) {
            switch node {
            case .pane(let id): frames[id] = rect
            case .split(let horizontal, let fraction, let first, let second):
                let available = (horizontal ? rect.width : rect.height) - 24
                let minFirst = horizontal ? first.minimum.width : first.minimum.height
                let minSecond = horizontal ? second.minimum.width : second.minimum.height
                let length = min(available - minSecond, max(minFirst, available * fraction))
                let a = CGRect(x: rect.minX, y: rect.minY, width: horizontal ? length : rect.width, height: horizontal ? rect.height : length)
                let b = horizontal ? CGRect(x: a.maxX + 24, y: rect.minY, width: available - length, height: rect.height)
                    : CGRect(x: rect.minX, y: a.maxY + 24, width: rect.width, height: available - length)
                dividers.append(horizontal ? CGRect(x: a.maxX, y: rect.minY, width: 24, height: rect.height)
                                : CGRect(x: rect.minX, y: a.maxY, width: rect.width, height: 24))
                paths.append(path); extents.append(available)
                visit(first, a, path + [false]); visit(second, b, path + [true])
            }
        }
        visit(self, CGRect(origin: .zero, size: size), [])
        return WorkspaceGeometry(frames: order.compactMap { frames[$0] }, size: size, dividers: dividers, dividerPaths: paths, dividerExtents: extents)
    }
}

enum ChatSplitLayout {
    static func fraction(_ value: Double) -> Double { min(0.65, max(0.25, value)) }
    // Two readable 300-point panes plus the divider, independent of device idiom.
    static func usesColumns(width: CGFloat) -> Bool { width >= 624 }
    static func columnFraction(_ value: Double, available: CGFloat) -> Double {
        let minimum = min(0.5, 300 / max(available, 1))
        return min(1 - minimum, max(minimum, value))
    }
    static func paneHeight(available: CGFloat, fraction: Double) -> CGFloat {
        // Keep the composer and some conversation visible even above the keyboard.
        max(0, min(available * Self.fraction(fraction), available - 170))
    }
}

/// Frames share a single coordinate space, keeping pane identity stable during
/// resize, reordering and changes between arrangements.
struct WorkspaceGeometry {
    var frames: [CGRect]
    var size: CGSize
    var dividers: [CGRect] = []
    var dividerPaths: [[Bool]] = []
    var dividerExtents: [CGFloat] = []

    static func make(size proposed: CGSize, count: Int, arrangement: WorkspaceArrangement,
                     columnFraction: Double = 0.45, rowFraction: Double = 0.45, division: CGRect? = nil, docking: WorkspaceDockNode? = nil, order: [UUID] = []) -> Self {
        let width = max(1, proposed.width), height = max(1, proposed.height)
        let count = max(1, count), gap: CGFloat = 24
        // An active fold takes precedence over a saved arrangement. Keep the
        // preference intact so unfolding restores it without recreating panes.
        if let division, let folded = folded(size: CGSize(width: width, height: height), count: count, division: division) {
            return folded
        }
        if let custom = docking?.geometry(size: CGSize(width: width, height: height), order: order) { return custom }
        if count == 1 { return Self(frames: [CGRect(x: 0, y: 0, width: width, height: height)], size: CGSize(width: width, height: height)) }
        if arrangement == .automatic, ChatSplitLayout.usesColumns(width: width), count <= 3 {
            let usableWidth = width - gap
            let left = usableWidth * ChatSplitLayout.columnFraction(columnFraction, available: usableWidth)
            let right = usableWidth - left
            let totalHeight = max(height, count == 3 ? 480 : 260)
            var frames = [CGRect(x: 0, y: 0, width: left, height: totalHeight)]
            var dividers = [CGRect(x: left, y: 0, width: gap, height: totalHeight)]
            if count == 2 {
                frames.append(CGRect(x: left + gap, y: 0, width: right, height: totalHeight))
            } else {
                let top = (totalHeight - gap) * ChatSplitLayout.fraction(rowFraction)
                frames.append(CGRect(x: left + gap, y: 0, width: right, height: top))
                frames.append(CGRect(x: left + gap, y: top + gap, width: right, height: totalHeight - gap - top))
                dividers.append(CGRect(x: left + gap, y: top, width: right, height: gap))
            }
            return Self(frames: frames, size: CGSize(width: width, height: totalHeight), dividers: dividers)
        }
        if arrangement == .automatic, !ChatSplitLayout.usesColumns(width: width), count == 2 {
            let totalHeight = max(300, height)
            let top = ChatSplitLayout.paneHeight(available: totalHeight - gap, fraction: rowFraction)
            return Self(frames: [CGRect(x: 0, y: top + gap, width: width, height: totalHeight - top - gap),
                                 CGRect(x: 0, y: 0, width: width, height: top)],
                        size: CGSize(width: width, height: totalHeight),
                        dividers: [CGRect(x: 0, y: top, width: width, height: gap)])
        }
        let columns: Int
        switch arrangement {
        case .columns: columns = count
        case .rows: columns = 1
        case .automatic, .grid: columns = ChatSplitLayout.usesColumns(width: width) ? 2 : 1
        }
        let rows = (count + columns - 1) / columns
        let cellWidth = max(min(width, 320), (width - CGFloat(columns - 1) * gap) / CGFloat(columns))
        let cellHeight = max(300, (height - CGFloat(rows - 1) * gap) / CGFloat(rows))
        let frames = (0..<count).map { index in
            CGRect(x: CGFloat(index % columns) * (cellWidth + gap), y: CGFloat(index / columns) * (cellHeight + gap), width: cellWidth, height: cellHeight)
        }
        return Self(frames: frames, size: CGSize(width: CGFloat(columns) * (cellWidth + gap) - gap,
                                                height: CGFloat(rows) * (cellHeight + gap) - gap))
    }
    private static func folded(size: CGSize, count: Int, division: CGRect) -> Self? {
        let bounds = CGRect(origin: .zero, size: size)
        let fold = division.intersection(bounds)
        guard !fold.isNull, !fold.isEmpty else { return nil }
        let vertical = division.height >= division.width
        let margin: CGFloat = 12
        let first: CGRect
        let second: CGRect
        if vertical {
            guard fold.height >= size.height * 0.5 else { return nil }
            first = CGRect(x: 0, y: 0, width: max(0, fold.minX - margin), height: size.height)
            second = CGRect(x: min(size.width, fold.maxX + margin), y: 0, width: max(0, size.width - fold.maxX - margin), height: size.height)
        } else {
            guard fold.width >= size.width * 0.5 else { return nil }
            first = CGRect(x: 0, y: 0, width: size.width, height: max(0, fold.minY - margin))
            second = CGRect(x: 0, y: min(size.height, fold.maxY + margin), width: size.width, height: max(0, size.height - fold.maxY - margin))
        }
        // A fold outside the useful viewport (for example above the keyboard)
        // must not force a tiny, unusable pane.
        guard min(first.width, second.width) >= 170, min(first.height, second.height) >= 140 else { return nil }
        if count == 1 {
            // Keep the composer reachable on the lower half in a laptop pose.
            return Self(frames: [vertical ? first : second], size: size)
        }
        let leadingCount = (count + 1) / 2
        func tiles(in region: CGRect, count: Int) -> [CGRect] {
            let gap: CGFloat = 12
            let extent = vertical ? region.height : region.width
            let length = max(1, (extent - CGFloat(count - 1) * gap) / CGFloat(count))
            return (0..<count).map { index in
                if vertical { return CGRect(x: region.minX, y: region.minY + CGFloat(index) * (length + gap), width: region.width, height: length) }
                return CGRect(x: region.minX + CGFloat(index) * (length + gap), y: region.minY, width: length, height: region.height)
            }
        }
        // Put the primary chat below a horizontal fold, with remote content above.
        let primaryRegion = vertical ? first : second
        let secondaryRegion = vertical ? second : first
        // For three panes retain the familiar chat + two tools arrangement.
        let primaryCount = count <= 3 ? 1 : leadingCount
        let secondaryCount = count - primaryCount
        return Self(frames: tiles(in: primaryRegion, count: primaryCount) + tiles(in: secondaryRegion, count: secondaryCount), size: size)
    }

}

struct PaneDropProposal: Equatable {
    var target: UUID
    var preview: CGRect
    var docking: WorkspaceDockNode?

    static func make(source: UUID, location: CGPoint, workspace: WorkspaceSnapshot,
                     layout: WorkspaceGeometry, viewport: CGSize, division: CGRect?) -> Self? {
        let order = workspace.orderedIDs
        guard order.contains(source), let index = layout.frames.indices.first(where: {
            order[$0] != source && layout.frames[$0].contains(location)
        }) else { return nil }
        let target = order[index], frame = layout.frames[index]
        let x = (location.x - frame.minX) / frame.width
        let y = (location.y - frame.minY) / frame.height
        let centered = (0.3...0.7).contains(x) && (0.3...0.7).contains(y)
        let fold = division?.intersection(CGRect(origin: .zero, size: viewport))
        let activeFold = fold.map { !$0.isNull && !$0.isEmpty } ?? false
        if !centered, !activeFold {
            let edge = [(WorkspaceDockEdge.left, x), (.right, 1 - x), (.top, y), (.bottom, 1 - y)].min { $0.1 < $1.1 }!.0
            let saved = workspace.docking.flatMap { $0.geometry(size: viewport, order: order) == nil ? nil : $0 }
            if let root = saved ?? WorkspaceDockNode.matching(ids: order, frames: layout.frames),
               let remaining = root.removing(source) {
                let docked = remaining.inserting(source, at: target, edge: edge)
                if let result = docked.geometry(size: viewport, order: order), let sourceIndex = order.firstIndex(of: source) {
                    return Self(target: target, preview: result.frames[sourceIndex], docking: docked)
                }
            }
        }
        // Compact or folded areas can still reorder without creating tiny panes.
        return Self(target: target, preview: frame)
    }
}

private struct PaneDragHandle: View {
    var changed: (DragGesture.Value) -> Void
    var ended: () -> Void
    var cancelled: () -> Void
    @GestureState private var active = false
    var body: some View {
        Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
            .frame(width: 40, height: 44).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 6, coordinateSpace: .named("chatSplit"))
                .updating($active) { _, state, _ in state = true }
                .onChanged(changed).onEnded { _ in ended() })
            .onChange(of: active) { _, value in if !value { cancelled() } }
            .accessibilityLabel("Drag pane".localized)
    }
}

/// Keep the familiar header intact; content interaction tucks it away. A centered
/// edge handle reveals pane controls without competing corner buttons.
private struct WorkspacePaneSurface<Header: View, Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var titlesVisible: Bool
    let enabled: Bool
    let autoHide: Bool
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            header()
                .frame(height: enabled && titlesVisible ? 44 : 0)
                .clipped().opacity(enabled && titlesVisible ? 1 : 0)
                .accessibilityHidden(!enabled || !titlesVisible)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .simultaneousGesture(TapGesture().onEnded { focusContent() })
                .simultaneousGesture(DragGesture(minimumDistance: 12).onEnded { _ in focusContent() })
        }
        .background(Theme.canvas)
        .overlay(alignment: .top) {
            if enabled && !titlesVisible {
                Button { setVisible(true) } label: {
                    Image(systemName: "chevron.compact.down")
                        .font(.system(size: 18, weight: .semibold)).foregroundStyle(.secondary)
                        .frame(width: 56, height: 24)
                        .background(.regularMaterial, in: Capsule())
                        .frame(width: 64, height: 44, alignment: .top).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.top, 4)
                    .accessibilityLabel("Show pane bars".localized)
                    .accessibilityIdentifier("showWorkspaceTitles")
            }
        }
    }
    private func focusContent() {
        guard enabled, autoHide, titlesVisible else { return }
        setVisible(false)
    }
    private func setVisible(_ visible: Bool) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { titlesVisible = visible }
    }
}

private struct PaneLift: ViewModifier {
    let active: Bool
    let translation: CGSize
    let reduceMotion: Bool
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(active ? 0.18 : 0), radius: active ? 14 : 0, y: active ? 6 : 0)
            .opacity(active ? 0.86 : 1)
            .offset(active && !reduceMotion ? translation : .zero)
            .zIndex(active ? 3 : 0)
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86), value: active)
    }
}

struct WorkspaceCanvas<Primary: View>: View {
    @Environment(\.appAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draggedID: UUID?
    @State private var dragTranslation = CGSize.zero
    @State private var proposal: PaneDropProposal?
    @State private var layoutRevision = 0
    private var motion: Animation? { reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86) }
    @Binding var workspace: WorkspaceSnapshot
    @Binding var titlesVisible: Bool
    let autoHideTitles: Bool
    let api: APIClient
    let botID: String
    let botName: String
    @ViewBuilder let primary: () -> Primary

    var body: some View {
        GeometryReader { proxy in
            // Read reserved regions before crossing the UIKit hosting boundary.
            PaneSurfaceHost { surface(division: activeDivision(in: proxy)) }
        }
    }
    private func activeDivision(in proxy: GeometryProxy) -> CGRect? {
        #if HOMEM_DUO_SDK
        if #available(iOS 27.1, *) {
            return proxy.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed).first?.frame
        }
        #endif
        return nil
    }
    private func surface(division: CGRect?) -> some View {
        GeometryReader { proxy in
            let order = workspace.orderedIDs
            let layout = WorkspaceGeometry.make(size: proxy.size, count: workspace.panes.count + 1, arrangement: workspace.arrangement,
                                                columnFraction: workspace.columnFraction, rowFraction: workspace.rowFraction, division: division, docking: workspace.docking, order: order)
            let axes: Axis.Set = [layout.size.width > proxy.size.width + 1 ? .horizontal : [],
                                  layout.size.height > proxy.size.height + 1 ? .vertical : []]
            ScrollView(axes) {
                ZStack(alignment: .topLeading) {
                    WorkspacePaneSurface(titlesVisible: $titlesVisible, enabled: !workspace.panes.isEmpty, autoHide: autoHideTitles) {
                        HStack {
                            dragHandle(workspace.primaryID, layout: layout, viewport: proxy.size, division: division)
                            Label("Chat".localized, systemImage: "bubble.left").font(.subheadline.weight(.medium))
                            Spacer()
                            Text(botName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }.padding(.trailing, 14).frame(height: 44).background(Theme.surface)
                    } content: {
                        primary()
                    }
                        .paneFrame(layout.frames[order.firstIndex(of: workspace.primaryID) ?? 0])
                        .modifier(PaneLift(active: draggedID == workspace.primaryID, translation: dragTranslation, reduceMotion: reduceMotion))
                        .animation(motion, value: layoutRevision)
                    ForEach($workspace.panes) { $pane in
                        if let index = order.firstIndex(of: pane.id) {
                            ChatWorkspacePane(api: api, defaultBotID: botID, pane: $pane, titlesVisible: $titlesVisible, autoHideTitles: autoHideTitles,
                                move: { direction in
                                    let ids = workspace.orderedIDs
                                    if let current = ids.firstIndex(of: pane.id), ids.indices.contains(current + direction) {
                                        withAnimation(motion) { workspace.move(pane.id, to: ids[current + direction]); layoutRevision += 1 }
                                    }
                                }, close: { withAnimation(motion) { workspace.remove(pane.id); layoutRevision += 1 } },
                                dragChanged: { updateDrag(pane.id, value: $0, layout: layout, viewport: proxy.size, division: division) },
                                dragEnded: finishDrag, dragCancelled: cancelDrag)
                                .id(pane.id.uuidString + pane.botID + pane.tool.rawValue)
                                .paneFrame(layout.frames[index])
                                .modifier(PaneLift(active: draggedID == pane.id, translation: dragTranslation, reduceMotion: reduceMotion))
                                .animation(motion, value: layoutRevision)
                        }
                    }
                    ForEach(Array(layout.dividers.enumerated()), id: \.offset) { index, frame in
                        let vertical = frame.width == 24
                        ChatPaneDivider(fraction: dividerBinding(index, vertical: vertical, layout: layout),
                                        vertical: vertical, available: layout.dividerExtents.indices.contains(index) ? layout.dividerExtents[index] : (vertical ? layout.size.width - 24 : layout.size.height - 24))
                            .paneFrame(frame)
                    }
                    if let proposal {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(accent.opacity(0.13))
                            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(accent, lineWidth: 2) }
                            .paneFrame(proposal.preview.insetBy(dx: 3, dy: 3))
                            .allowsHitTesting(false).accessibilityHidden(true).zIndex(2)
                            .animation(motion, value: proposal.preview)
                    }
                }.frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                    .coordinateSpace(name: "chatSplit")
            }.contentMargins(0, for: .scrollContent).scrollBounceBehavior(.basedOnSize)
        }.background(Theme.surface).clipped()
    }
    private func dividerBinding(_ index: Int, vertical: Bool, layout: WorkspaceGeometry) -> Binding<Double> {
        if layout.dividerPaths.indices.contains(index) {
            let path = layout.dividerPaths[index]
            return Binding(get: { workspace.docking?.fraction(at: path) ?? 0.5 }, set: { workspace.docking?.setFraction($0, at: path) })
        }
        return vertical ? $workspace.columnFraction : $workspace.rowFraction
    }
    private func dragHandle(_ id: UUID, layout: WorkspaceGeometry, viewport: CGSize, division: CGRect?) -> some View {
        PaneDragHandle(changed: { updateDrag(id, value: $0, layout: layout, viewport: viewport, division: division) },
                       ended: finishDrag, cancelled: cancelDrag)
    }
    private func updateDrag(_ id: UUID, value: DragGesture.Value, layout: WorkspaceGeometry, viewport: CGSize, division: CGRect?) {
        draggedID = id
        dragTranslation = value.translation
        proposal = PaneDropProposal.make(source: id, location: value.location, workspace: workspace,
                                         layout: layout, viewport: viewport, division: division)
    }
    private func finishDrag() {
        withAnimation(motion) {
            if let id = draggedID, let proposal {
                if let docking = proposal.docking { workspace.docking = docking }
                else { workspace.move(id, to: proposal.target) }
                layoutRevision += 1
            }
            draggedID = nil; dragTranslation = .zero; proposal = nil
        }
    }
    private func cancelDrag() {
        withAnimation(motion) { draggedID = nil; dragTranslation = .zero; proposal = nil }
    }
}

/// UIKit resets inherited navigation safe-area insets once, at the workspace
/// boundary. All child panes then lay out in their actual available rectangle.
private struct PaneSurfaceHost<Content: View>: UIViewControllerRepresentable {
    @Environment(AppStore.self) private var store
    @Environment(\.appAccent) private var accent
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @ViewBuilder let content: () -> Content
    private var root: some View {
        content().environment(store).environment(\.appAccent, accent).tint(accent)
            .environment(\.scenePhase, scenePhase).environment(\.colorScheme, colorScheme).environment(\.locale, locale)
    }
    func makeUIViewController(context: Context) -> UIHostingController<AnyView> {
        let controller = UIHostingController(rootView: AnyView(root))
        controller.safeAreaRegions = []
        controller.view.backgroundColor = .clear
        return controller
    }
    func updateUIViewController(_ controller: UIHostingController<AnyView>, context: Context) {
        controller.rootView = AnyView(root)
    }
}

private extension View {
    func paneFrame(_ rect: CGRect) -> some View {
        frame(width: rect.width, height: rect.height).clipped().offset(x: rect.minX, y: rect.minY)
    }
}

struct ChatWorkspacePane: View {
    @Environment(AppStore.self) private var store
    let api: APIClient
    let defaultBotID: String
    @Binding var pane: WorkspacePane
    @Binding var titlesVisible: Bool
    let autoHideTitles: Bool
    let move: (Int) -> Void
    let close: () -> Void
    let dragChanged: (DragGesture.Value) -> Void
    let dragEnded: () -> Void
    let dragCancelled: () -> Void
    @State private var desktop: DesktopModel
    @State private var terminalID = UUID()
    private var botID: String { pane.botID.nonEmpty ?? defaultBotID }
    private var tool: ChatWorkspaceTool { pane.tool }
    init(api: APIClient, defaultBotID: String, pane: Binding<WorkspacePane>, titlesVisible: Binding<Bool>, autoHideTitles: Bool, move: @escaping (Int) -> Void, close: @escaping () -> Void,
         dragChanged: @escaping (DragGesture.Value) -> Void, dragEnded: @escaping () -> Void, dragCancelled: @escaping () -> Void) {
        _titlesVisible = titlesVisible; self.autoHideTitles = autoHideTitles
        self.dragChanged = dragChanged; self.dragEnded = dragEnded; self.dragCancelled = dragCancelled
        self.api = api; self.defaultBotID = defaultBotID; _pane = pane; self.move = move; self.close = close
        let model = DesktopModel(api: api, botID: pane.wrappedValue.botID.nonEmpty ?? defaultBotID)
        model.setViewOnly(pane.wrappedValue.viewOnly)
        _desktop = State(initialValue: model)
    }
    var body: some View {
        WorkspacePaneSurface(titlesVisible: $titlesVisible, enabled: true, autoHide: autoHideTitles) {
            HStack(spacing: 0) {
                PaneDragHandle(changed: dragChanged, ended: dragEnded, cancelled: dragCancelled)
                Menu {
                    Picker("Show".localized, selection: $pane.tool) {
                        ForEach(ChatWorkspaceTool.allCases) { item in Label(item.title.localized, systemImage: item.symbol).tag(item) }
                    }
                    Picker("Agent".localized, selection: Binding(get: { botID }, set: { pane.botID = $0; pane.conversation = nil; pane.directory = "/data" })) {
                        ForEach(store.bots) { bot in Text(bot.title).tag(bot.id) }
                    }
                    Button("Move earlier".localized, systemImage: "arrow.up") { move(-1) }
                    Button("Move later".localized, systemImage: "arrow.down") { move(1) }
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Label(tool.title.localized, systemImage: tool.symbol).font(.subheadline.weight(.medium)).lineLimit(1)
                        Text(store.bots.first { $0.id == botID }?.title ?? "Agent".localized).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.accessibilityLabel("Switch pane".localized)
                Spacer(minLength: 4)
                if tool == .desktop { DesktopModeButton(model: desktop) }
                if tool == .desktop || tool == .terminal {
                    Button {
                        if tool == .desktop { Task { desktop.disconnect(); await desktop.connect() } }
                        else { terminalID = UUID() }
                    } label: { Image(systemName: "arrow.clockwise").frame(width: 40, height: 44) }
                        .accessibilityLabel((tool == .desktop ? "Reconnect desktop" : "Reconnect terminal").localized)
                }
                Button(action: close) { Image(systemName: "xmark").frame(width: 40, height: 44) }.accessibilityLabel("Close pane".localized)
            }.buttonStyle(.plain).padding(.trailing, 4).frame(height: 44).background(Theme.surface)
        } content: {
            switch tool {
            case .desktop:
                if api.isDemo { EmptyState(title: "Desktop unavailable", symbol: tool.symbol, detail: "Connect to a server to use this agent’s desktop.") }
                else { DesktopContent(model: desktop, embedded: true) }
            case .terminal: TerminalScreen(botID: botID, embedded: true).id(terminalID)
            case .files: PaneFiles(botID: botID, path: $pane.directory)
            case .chat: PaneConversationPicker(initialBotID: botID, selection: $pane.conversation)
            }
        }.background(Theme.canvas).clipped()
            .onChange(of: desktop.viewOnly) { _, value in pane.viewOnly = value }
    }
}

private struct PaneFiles: View {
    let botID: String
    @Binding var path: String
    @State private var selectedFile: Record?
    var body: some View {
        FileBrowserView(botID: botID, path: path, embedded: true, openFile: { file in
            if file.value["isDir"].bool { path = file.value["path"].string }
            else { selectedFile = file }
        }, goBack: path == "/data" ? nil : { path = (path as NSString).deletingLastPathComponent })
            .id(path)
            .sheet(item: $selectedFile) { file in
                NavigationStack { FileEditorView(botID: botID, path: file.value["path"].string, onClose: { selectedFile = nil }) }
            }
    }
}

private struct PaneConversationPicker: View {
    @Environment(AppStore.self) private var store
    let initialBotID: String
    @Binding var selection: ChatDestination?
    @State private var botID = ""
    @State private var sessions: [Record] = []
    @State private var error: String?
    @State private var newChat = false
    var body: some View {
        VStack(spacing: 0) {
            if let route = selection, let api = store.api {
                HStack {
                    Button { selection = nil } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Choose a conversation".localized)
                    Text(route.title).font(.subheadline).lineLimit(1)
                    Spacer()
                }.background(Theme.surface)
                ChatContent(model: ChatModel(api: api, botID: route.botID, sessionID: route.sessionID), destination: route, allowsWorkspace: false,
                            onFirstMessageQueued: { if selection?.sessionID == route.sessionID { selection?.firstMessage = nil } }).id(route.sessionID)
            } else {
                List {
                    Picker("Agent".localized, selection: $botID) { ForEach(store.bots) { bot in Text(bot.title).tag(bot.id) } }
                    Button("New conversation".localized, systemImage: "square.and.pencil") { newChat = true }
                    if let error { ErrorBanner(message: error) }
                    ForEach(sessions) { session in
                        Button(session.title) { selection = ChatDestination(botID: botID, sessionID: session.id, title: session.title, botName: store.bots.first { $0.id == botID }?.title ?? "Agent") }.foregroundStyle(.primary)
                    }
                }
            }
        }
        .onAppear { if botID.isEmpty { botID = selection?.botID ?? initialBotID } }
        .task(id: botID) {
            guard !botID.isEmpty else { return }
            sessions = []; error = nil
            do {
                let result = try await store.api?.call("/bots/\(botID.pathComponent)/sessions", query: ["types": "chat,discuss,acp_agent", "limit": "50"]).items.map(Record.init) ?? []
                if !Task.isCancelled { sessions = result }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
        .sheet(isPresented: $newChat) { NewConversationView(botID: botID) { selection = $0 } }
    }
}

struct DesktopModeButton: View {
    let model: DesktopModel
    var body: some View {
        Button { model.setViewOnly(!model.viewOnly) } label: {
            Label((model.viewOnly ? "View only" : "Control").localized,
                  systemImage: model.viewOnly ? "eye" : "hand.point.up.left")
                .font(.caption.weight(.medium)).lineLimit(1).padding(.horizontal, 8).frame(minHeight: 44)
        }.buttonStyle(.plain)
            .accessibilityLabel("View only".localized)
            .accessibilityValue((model.viewOnly ? "On" : "Off").localized)
            .accessibilityIdentifier("desktopViewOnly")
    }
}

/// A generous hit area around a quiet handle; also adjustable with VoiceOver.
struct ChatPaneDivider: View {
    @Binding var fraction: Double
    let vertical: Bool
    let available: CGFloat
    @State private var startFraction: Double?

    private func clamped(_ value: Double) -> Double {
        vertical ? ChatSplitLayout.columnFraction(value, available: available) : ChatSplitLayout.fraction(value)
    }

    var body: some View {
        Capsule().fill(.tertiary)
            .frame(width: vertical ? 4 : 32, height: vertical ? 32 : 4)
            .frame(maxWidth: vertical ? nil : .infinity, maxHeight: vertical ? .infinity : nil)
            .frame(width: vertical ? 24 : nil, height: vertical ? nil : 24)
            .background(Theme.surface).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("chatSplit")).onChanged { value in
                if startFraction == nil { startFraction = clamped(fraction) }
                let translation = vertical ? value.translation.width : value.translation.height
                fraction = clamped((startFraction ?? fraction) + translation / max(available, 1))
            }.onEnded { _ in startFraction = nil })
            .accessibilityElement().accessibilityLabel("Resize split view".localized)
            .accessibilityValue(Text(clamped(fraction), format: .percent.precision(.fractionLength(0))))
            .accessibilityAdjustableAction { direction in
                fraction = clamped(clamped(fraction) + (direction == .increment ? 0.05 : -0.05))
            }
    }
}
