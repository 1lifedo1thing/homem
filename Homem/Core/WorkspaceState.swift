import SwiftUI
import Observation

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
        case .pane: CGSize(width: Theme.minimumPaneWidth, height: 180)
        case .split(let horizontal, _, let first, let second):
            horizontal ? CGSize(width: first.minimum.width + second.minimum.width + Theme.paneGap, height: max(first.minimum.height, second.minimum.height))
                : CGSize(width: max(first.minimum.width, second.minimum.width), height: first.minimum.height + second.minimum.height + Theme.paneGap)
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
                let available = (horizontal ? rect.width : rect.height) - Theme.paneGap
                let minFirst = horizontal ? first.minimum.width : first.minimum.height
                let minSecond = horizontal ? second.minimum.width : second.minimum.height
                let length = min(available - minSecond, max(minFirst, available * fraction))
                let a = CGRect(x: rect.minX, y: rect.minY, width: horizontal ? length : rect.width, height: horizontal ? rect.height : length)
                let b = horizontal ? CGRect(x: a.maxX + Theme.paneGap, y: rect.minY, width: available - length, height: rect.height)
                    : CGRect(x: rect.minX, y: a.maxY + Theme.paneGap, width: rect.width, height: available - length)
                dividers.append(horizontal ? CGRect(x: a.maxX, y: rect.minY, width: Theme.paneGap, height: rect.height)
                                : CGRect(x: rect.minX, y: a.maxY, width: rect.width, height: Theme.paneGap))
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
    // Use the actual window width and each platform’s readable pane minimum.
    static func usesColumns(width: CGFloat) -> Bool { width >= Theme.minimumPaneWidth * 2 + Theme.paneGap }
    static func columnFraction(_ value: Double, available: CGFloat) -> Double {
        let minimum = min(0.5, Theme.minimumPaneWidth / max(available, 1))
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
        let count = max(1, count), gap: CGFloat = Theme.paneGap
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
        let cellWidth = max(min(width, Theme.minimumPaneWidth + 20), (width - CGFloat(columns - 1) * gap) / CGFloat(columns))
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

