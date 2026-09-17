import SwiftUI
import Charts

/// Memoh accepts date-only UTC boundaries; `to` is exclusive.
struct TokenUsagePeriod {
    let from: Date
    let to: Date
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    init(days: Int, now: Date = .now) {
        let today = Self.calendar.startOfDay(for: now)
        from = Self.calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: today)!
        to = Self.calendar.date(byAdding: .day, value: 1, to: today)!
    }
    static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    var query: [String: String] { ["from": Self.dateString(from), "to": Self.dateString(to)] }
}

struct TokenUsageSummary {
    struct Day: Identifiable {
        let id: String
        var input: Double = 0
        var output: Double = 0
        var total: Double { input + output }
        var date: Date { (id + "T00:00:00Z").wireDate ?? .distantPast }
    }
    let days: [Day]
    let models: [JSONValue]
    var input: Double { days.reduce(0) { $0 + $1.input } }
    var output: Double { days.reduce(0) { $0 + $1.output } }
    var total: Double { input + output }
    init(_ value: JSONValue) {
        var daily: [String: Day] = [:]
        // These buckets are mutually exclusive. By-model totals are another view
        // of the same tokens and must never be added again.
        for bucket in ["chat", "discuss", "acp_agent", "schedule"] {
            for item in value[bucket].array {
                let id = String(item["day"].string.prefix(10))
                guard !id.isEmpty else { continue }
                var day = daily[id] ?? Day(id: id)
                day.input += item["input_tokens"].number
                day.output += item["output_tokens"].number
                daily[id] = day
            }
        }
        days = daily.values.sorted { $0.id < $1.id }
        models = value["by_model"].array.sorted {
            $0["input_tokens"].number + $0["output_tokens"].number > $1["input_tokens"].number + $1["output_tokens"].number
        }
    }
}

struct TokenUsageView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.appAccent) private var accent
    let botID: String
    @State private var days = 30
    @State private var summary: TokenUsageSummary?
    @State private var period = TokenUsagePeriod(days: 30)
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Date range".localized, selection: $days) {
                    Text("7 days".localized).tag(7)
                    Text("30 days".localized).tag(30)
                    Text("90 days".localized).tag(90)
                }.pickerStyle(.segmented)
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 60)
                } else if let error {
                    ErrorBanner(message: error) { Task { await load() } }
                } else if let summary {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Total tokens".localized).font(.subheadline).foregroundStyle(.secondary)
                            Text(summary.total, format: .number.precision(.fractionLength(0)))
                                .font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit()
                            Text("Daily totals use UTC.".localized).font(.caption).foregroundStyle(.secondary)
                        }
                        Divider()
                        HStack {
                            metric("Input tokens", value: summary.input)
                            Spacer()
                            metric("Output tokens", value: summary.output)
                        }
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).modifier(DetailSurface())
                    if summary.total > 0 {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Daily usage".localized).font(.headline)
                            Chart(summary.days) { day in
                                BarMark(x: .value("Date".localized, day.date, unit: .day), y: .value("Tokens".localized, day.total))
                                    .foregroundStyle(accent.gradient).cornerRadius(3)
                                    .accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted))
                                    .accessibilityValue(day.total.formatted(.number.precision(.fractionLength(0))))
                            }.chartXScale(domain: period.from...period.to)
                                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                                .chartYAxis {
                                    AxisMarks { value in
                                        AxisGridLine()
                                        AxisValueLabel {
                                            if let tokens = value.as(Double.self) { Text(tokens, format: .number.notation(.compactName)) }
                                        }
                                    }
                                }
                                .frame(height: 160)
                                .environment(\.timeZone, TokenUsagePeriod.calendar.timeZone)
                        }.padding(20).modifier(DetailSurface())
                        if !summary.models.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                Text("By model".localized).font(.headline)
                                ForEach(Array(summary.models.enumerated()), id: \.offset) { index, model in
                                    if index > 0 { Divider() }
                                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(model.text("model_name", "model_slug").nonEmpty ?? "Unknown model".localized).font(.subheadline.weight(.medium))
                                            if let provider = model["provider_name"].string.nonEmpty { Text(provider).font(.caption).foregroundStyle(.secondary) }
                                        }
                                        Spacer(minLength: 0)
                                        Text(model["input_tokens"].number + model["output_tokens"].number, format: .number.precision(.fractionLength(0)))
                                            .font(.subheadline.monospacedDigit())
                                    }
                                }
                            }.padding(20).modifier(DetailSurface())
                        }
                    } else {
                        Text("No token usage in this period.".localized).font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 24)
                    }
                }
            }.padding(20).frame(maxWidth: 760).frame(maxWidth: .infinity)
        }.background(Theme.canvas).navigationTitle("Token usage".localized).navigationBarTitleDisplayMode(.inline)
            .task(id: days) { await load() }.refreshable { await load() }
    }
    private func metric(_ title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.localized).font(.caption).foregroundStyle(.secondary)
            Text(value, format: .number.precision(.fractionLength(0))).font(.headline.monospacedDigit())
        }
    }
    private func load() async {
        guard let api = store.api else { return }
        loading = true; error = nil; summary = nil
        let requestedDays = days
        let requestedPeriod = TokenUsagePeriod(days: requestedDays)
        do {
            let value = try await api.call("/bots/\(botID.pathComponent)/token-usage", query: requestedPeriod.query)
            guard !Task.isCancelled, days == requestedDays else { return }
            period = requestedPeriod; summary = TokenUsageSummary(value); loading = false
        } catch {
            guard !Task.isCancelled, days == requestedDays else { return }
            self.error = error.localizedDescription; loading = false
        }
    }
}
