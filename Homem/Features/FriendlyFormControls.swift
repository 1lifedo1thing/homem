import SwiftUI

/// Use a slider only when the server defines a finite, meaningful range.
/// Free numeric entry remains available for precision and unbounded values.
struct FriendlyNumberField: View {
    let title: String
    let name: String
    let schema: JSONValue
    let required: Bool
    @Binding var value: JSONValue
    private var range: ClosedRange<Double>? {
        if name == "compaction_target_percent" { return 1...99 }
        guard case .number(let min) = schema["minimum"], case .number(let max) = schema["maximum"], min.isFinite, max.isFinite, min < max,
              schema["exclusiveMinimum"] != true, schema["exclusiveMaximum"] != true else { return nil }
        return min...max
    }
    private var step: Double { schema["multipleOf"].number > 0 ? schema["multipleOf"].number : schema["type"] == "integer" ? 1 : 0.01 }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent(title) {
                TextField("Default".localized, text: Binding(get: { value.isNull ? "" : value.scalar }, set: { value = $0.isEmpty ? .null : Double($0).map(JSONValue.number) ?? .string($0) }))
                    .keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing).monospacedDigit()
            }
            if let range, case .number(let number) = value, range.contains(number) {
                Slider(value: Binding(get: { min(range.upperBound, max(range.lowerBound, value.number)) }, set: { value = .number($0) }), in: range, step: step)
                    .accessibilityLabel(title)
            }
            if name == "compaction_target_percent" {
                Toggle("Automatic".localized, isOn: Binding(get: { value.isNull || !(1...99).contains(value.number) }, set: { value = $0 ? 0 : 50 }))
                // Memoh uses 0 to reset this setting; null means no change.
            }
        }.padding(.vertical, 2)
    }
}

struct TimeZoneFormField: View {
    let title: String
    @Binding var value: JSONValue
    var body: some View {
        NavigationLink {
            TimeZoneChoices(value: $value)
        } label: {
            LabeledContent(title, value: value.string.isEmpty ? "Default".localized : Self.name(value.string))
        }
    }
    static func name(_ id: String) -> String {
        TimeZone(identifier: id)?.localizedName(for: .generic, locale: .current) ?? id.replacingOccurrences(of: "_", with: " ")
    }
}

private struct TimeZoneChoices: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var value: JSONValue
    @State private var search = ""
    private var zones: [String] {
        TimeZone.knownTimeZoneIdentifiers.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) || TimeZoneFormField.name($0).localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        List {
            Section {
                choice("", title: "Default".localized)
                choice(TimeZone.current.identifier, title: "Device time zone".localized)
            }
            Section {
                ForEach(zones, id: \.self) { id in choice(id, title: id.replacingOccurrences(of: "_", with: " ")) }
            }
        }.navigationTitle("Time zone".localized).searchable(text: $search)
    }
    private func choice(_ id: String, title: String) -> some View {
        Button { value = .string(id); dismiss() } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).foregroundStyle(.primary)
                    if !id.isEmpty { Text(TimeZoneFormField.name(id)).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if value.string == id { Image(systemName: "checkmark").accessibilityLabel("Selected".localized) }
            }
        }
    }
}
