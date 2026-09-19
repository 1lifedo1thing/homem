import SwiftUI

struct ChatQueueView: View {
    @Bindable var queue: ChatQueue
    @State private var expanded = true
    @State private var editing: ChatQueuedMessage?
    @State private var editText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !queue.items.isEmpty {
                DisclosureGroup(isExpanded: $expanded) {
                    ScrollView {
                        VStack(spacing: 4) {
                            ForEach(queue.items) { item in
                                HStack(spacing: 8) {
                                    Image(systemName: item.kind == .steer ? "arrow.turn.up.right" : "clock")
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel((item.kind == .steer ? "Steer current response" : "Send as follow-up").localized)
                                    Text(item.text).font(.subheadline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                    if queue.busy.contains(item.id) { ProgressView().controlSize(.small) }
                                    Menu {
                                        Button("Edit message".localized, systemImage: "pencil") { editText = item.text; editing = item }
                                        if item.kind == .followUp, queue.steerSupported {
                                            Button("Steer current response".localized, systemImage: "arrow.turn.up.right") { Task { await queue.steer(item) } }
                                        }
                                        Button("Move earlier".localized, systemImage: "arrow.up") { Task { await queue.move(item, by: -1) } }.disabled(!queue.canMove(item, by: -1))
                                        Button("Move later".localized, systemImage: "arrow.down") { Task { await queue.move(item, by: 1) } }.disabled(!queue.canMove(item, by: 1))
                                        Button("Remove from queue".localized, systemImage: "xmark", role: .destructive) { Task { await queue.remove(item) } }
                                    } label: {
                                        Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
                                    }.disabled(!item.editable || !queue.busy.isEmpty || queue.submitting)
                                        .accessibilityLabel("Queued message actions".localized)
                                }.padding(.leading, 8).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }.frame(maxHeight: min(CGFloat(queue.items.count) * 60, 180)).scrollBounceBehavior(.basedOnSize)
                } label: {
                    HStack(spacing: 6) {
                        Text("Queued messages".localized)
                        Text(queue.items.count, format: .number).monospacedDigit().foregroundStyle(.secondary)
                    }.font(.caption.weight(.medium))
                }
            }
            if let error = queue.error {
                HStack(alignment: .top) {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button { queue.error = nil } label: { Image(systemName: "xmark.circle").frame(width: 32, height: 32) }
                        .accessibilityLabel("Dismiss".localized)
                }
            }
        }
        .alert("Edit queued message".localized, isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Message".localized, text: $editText)
            Button("Save".localized) {
                if let item = editing { let text = editText; Task { await queue.update(item, text: text) } }
            }.disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel".localized, role: .cancel) { editing = nil }
        }
    }
}
