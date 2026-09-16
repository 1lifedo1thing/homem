import SwiftUI

struct MemoryGraphView: View {
    @Environment(AppStore.self) private var store
    var path: String
    @State private var graph: JSONValue = .null
    @State private var selected: JSONValue?
    @State private var error: String?
    @State private var search = ""
    var nodes: [JSONValue] { graph["nodes"].array }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Connected ideas").font(.title2.bold())
                Text("\(nodes.count) topics · \(graph["edges"].array.count) relationships").font(.subheadline).foregroundStyle(.secondary)
                if let error { ErrorBanner(message: error) }
                if !nodes.isEmpty {
                    GeometryReader { geometry in
                        ZStack {
                            Canvas { context, size in
                                for edge in graph["edges"].array {
                                    guard let a = nodes.firstIndex(where: { $0["id"] == edge["source"] }), let b = nodes.firstIndex(where: { $0["id"] == edge["target"] }) else { continue }
                                    var line = Path(); line.move(to: position(a, size: size)); line.addLine(to: position(b, size: size))
                                    context.stroke(line, with: .color(Theme.accent.opacity(0.25)), lineWidth: min(4, max(1, edge["weight"].number)))
                                }
                            }.accessibilityHidden(true)
                            ForEach(Array(nodes.prefix(60).enumerated()), id: \.offset) { i, node in
                                Button { selected = node } label: {
                                    VStack(spacing: 5) { Circle().fill(Theme.color(node["id"].string).gradient).frame(width: 24 + min(20, node["count"].number), height: 24 + min(20, node["count"].number)); Text(node.text("label", "subject", "topic", "id")).font(.caption2).lineLimit(2).frame(width: 90) }
                                }.buttonStyle(.plain).position(position(i, size: geometry.size)).accessibilityLabel(node.text("label", "subject", "topic", "id"))
                            }
                        }
                    }.frame(height: 380).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                } else if error == nil { EmptyState(title: "Connections grow over time", symbol: "brain", detail: "Your agent’s memory relationships will appear here.") }
                ForEach(nodes.filter { search.isEmpty || $0.pretty.localizedCaseInsensitiveContains(search) }, id: \.self) { node in
                    Button { selected = node } label: { HStack { Image(systemName: "circle.hexagongrid").foregroundStyle(Theme.accent); VStack(alignment: .leading) { Text(node.text("label", "subject", "topic", "id")).font(.headline); Text(node["memory"].string).font(.caption).foregroundStyle(.secondary).lineLimit(2) }; Spacer(); Text(node["count"].scalar).font(.caption).foregroundStyle(.secondary) }.padding() }.buttonStyle(.plain)
                }
            }.padding(22)
        }.background(Color(.systemGroupedBackground)).navigationTitle("Memory graph").navigationBarTitleDisplayMode(.inline).searchable(text: $search)
            .task { do { graph = try await store.api?.call(path) ?? .null } catch { self.error = error.localizedDescription } }
            .sheet(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) { NavigationStack { List { if let selected { JSONDetails(value: selected) } }.navigationTitle("Memory topic").toolbar { Button("Done") { selected = nil } } } }
    }
    func position(_ index: Int, size: CGSize) -> CGPoint {
        let count = min(nodes.count, 60)
        if count == 1 { return CGPoint(x: size.width / 2, y: size.height / 2) }
        let angle = Double(index) * 2.399963229728653
        let radius = sqrt(Double(index + 1) / Double(max(1, count)))
        return CGPoint(x: size.width / 2 + cos(angle) * radius * max(0, size.width / 2 - 52), y: size.height / 2 + sin(angle) * radius * max(0, size.height / 2 - 48))
    }
}
