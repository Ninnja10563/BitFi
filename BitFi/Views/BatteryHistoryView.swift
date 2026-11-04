import Charts
import SwiftUI

struct BatteryHistoryView: View {
    @EnvironmentObject private var history: BatteryHistoryStore
    @State private var selectedRange: BatteryHistoryRange = .day

    private var segments: [BatteryHistorySegment] {
        history.segments(in: selectedRange)
    }

    private var records: [BatteryHistoryRecord] {
        history.records(in: selectedRange)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Battery History")
                            .font(.title2.weight(.semibold))
                        Text("Local charge samples, retained across app launches and computer restarts.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("History range", selection: $selectedRange) {
                        ForEach(BatteryHistoryRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 280)
                }

                if records.isEmpty {
                    ContentUnavailableView {
                        Label("Gathering Battery History", systemImage: "chart.xyaxis.line")
                    } description: {
                        Text("BitFi records available battery readings while it is running.")
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    Chart {
                        ForEach(segments) { segment in
                            ForEach(segment.records) { record in
                                LineMark(
                                    x: .value("Time", record.recordedAt),
                                    y: .value("Charge", record.percentage),
                                    series: .value("Continuous samples", segment.id)
                                )
                                .foregroundStyle(.tint)
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                .interpolationMethod(.linear)
                            }
                        }
                        if records.count == 1, let record = records.first {
                            PointMark(
                                x: .value("Time", record.recordedAt),
                                y: .value("Charge", record.percentage)
                            )
                            .foregroundStyle(.tint)
                            .symbolSize(56)
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxis {
                        AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let percentage = value.as(Int.self) {
                                    Text("\(percentage)%")
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 5))
                    }
                    .frame(height: 270)
                    .accessibilityLabel("Battery charge history")

                    HistorySummary(records: records)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Samples save locally as BitFi runs. A line break means BitFi was not running, or your Mac was asleep or shut down; BitFi never invents readings for that gap.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if let persistenceError = history.persistenceError {
                            Label(persistenceError, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    Label("Recording", systemImage: "internaldrive")
                }
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .navigationTitle("Battery History")
    }
}

private struct HistorySummary: View {
    let records: [BatteryHistoryRecord]

    private var first: BatteryHistoryRecord? { records.first }
    private var latest: BatteryHistoryRecord? { records.last }

    var body: some View {
        HStack(spacing: 32) {
            HistoryMetric(title: "Start", value: first.map { "\($0.percentage)%" } ?? "—")
            HistoryMetric(title: "Latest", value: latest.map { "\($0.percentage)%" } ?? "—")
            HistoryMetric(title: "Change", value: changeText)
            Spacer()
            Text("\(records.count) samples")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var changeText: String {
        guard let first, let latest else { return "—" }
        let change = latest.percentage - first.percentage
        return change == 0 ? "0%" : "\(change > 0 ? "+" : "")\(change)%"
    }
}

private struct HistoryMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
        }
    }
}
