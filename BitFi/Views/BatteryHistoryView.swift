import Charts
import SwiftUI

struct BatteryHistoryView: View {
    @EnvironmentObject private var history: BatteryHistoryStore
    @State private var selectedRange: BatteryHistoryRange = .day
    @State private var scrollPosition = Date.now.addingTimeInterval(-24 * 60 * 60)
    @State private var selectedRecord: BatteryHistoryRecord?
    @State private var timelineEnd = Date.now

    private var chartStart: Date {
        let earliestSample = history.earliestRecordedAt ?? chartEnd.addingTimeInterval(-fallbackDuration)
        guard let windowDuration = selectedRange.visibleDuration else {
            return earliestSample
        }
        return min(earliestSample, chartEnd.addingTimeInterval(-windowDuration))
    }

    private var chartEnd: Date {
        max(history.latestRecordedAt ?? timelineEnd, timelineEnd)
    }

    private var chartDomain: ClosedRange<Date> {
        chartStart...chartEnd
    }

    private var fallbackDuration: TimeInterval {
        selectedRange.visibleDuration ?? 24 * 60 * 60
    }

    private var visibleDuration: TimeInterval {
        selectedRange.visibleDuration ?? max(chartEnd.timeIntervalSince(chartStart), 60 * 60)
    }

    private var maximumScrollStart: Date {
        max(chartStart, chartEnd.addingTimeInterval(-visibleDuration))
    }

    private var visibleStart: Date {
        min(max(scrollPosition, chartStart), maximumScrollStart)
    }

    private var visibleEnd: Date {
        min(chartEnd, visibleStart.addingTimeInterval(visibleDuration))
    }

    private var chartSegments: [BatteryHistorySegment] {
        history.chartSegments(from: chartStart, through: chartEnd)
    }

    private var visibleRecords: [BatteryHistoryRecord] {
        history.records(from: visibleStart, through: visibleEnd)
    }

    private var hasHistory: Bool {
        history.earliestRecordedAt != nil
    }

    private var canMoveBack: Bool {
        selectedRange != .all && visibleStart > chartStart.addingTimeInterval(1)
    }

    private var canMoveForward: Bool {
        selectedRange != .all && visibleEnd < chartEnd.addingTimeInterval(-1)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Battery History")
                            .font(.title2.weight(.semibold))
                        Text("Saved local charge samples. Pan, navigate, or hover to inspect.")
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
                    .frame(maxWidth: 390)
                    .accessibilityLabel("History range")
                }

                if !hasHistory {
                    ContentUnavailableView {
                        Label("Gathering Battery History", systemImage: "chart.xyaxis.line")
                    } description: {
                        Text("BitFi records available battery readings while it is running.")
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    historyNavigation
                    historyChart
                    historyInspector
                    HistorySummary(records: visibleRecords)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Samples save locally for up to two years while BitFi runs. A line break means BitFi was not running, or your Mac was asleep or shut down; BitFi never invents readings for that gap.")
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
        .onAppear {
            timelineEnd = .now
            scrollToLatest()
        }
        .onChange(of: selectedRange) { _, _ in
            selectedRecord = nil
            scrollToLatest()
        }
        .onChange(of: history.latestRecordedAt) { _, _ in
            let wasAtLatest = !canMoveForward
            timelineEnd = .now
            if wasAtLatest {
                scrollToLatest()
            }
        }
    }

    private var historyNavigation: some View {
        HStack(spacing: 10) {
            Text(windowTitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()

            Button {
                moveWindow(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .help("View earlier \(selectedRange.accessibilityTitle.lowercased())")
            .disabled(!canMoveBack)

            Button("Latest") {
                scrollToLatest()
            }
            .controlSize(.small)
            .disabled(!canMoveForward)

            Button {
                moveWindow(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .help("View later \(selectedRange.accessibilityTitle.lowercased())")
            .disabled(!canMoveForward)
        }
    }

    private var historyChart: some View {
        Chart {
            historyLineMarks
            selectedHistoryMarks
        }
        .chartXScale(domain: chartDomain)
        .chartYScale(domain: 0...100)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: visibleDuration)
        .chartScrollPosition(x: $scrollPosition)
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
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(location):
                            guard let plotAnchor = proxy.plotFrame else {
                                selectedRecord = nil
                                return
                            }
                            let plotFrame = geometry[plotAnchor]
                            guard plotFrame.contains(location),
                                  let date = proxy.value(
                                      atX: location.x - plotFrame.origin.x,
                                      as: Date.self
                                  )
                            else {
                                selectedRecord = nil
                                return
                            }
                            let nearestRecord = history.nearestRecord(to: date)
                            if selectedRecord?.id != nearestRecord?.id {
                                selectedRecord = nearestRecord
                            }
                        case .ended:
                            if selectedRecord != nil {
                                selectedRecord = nil
                            }
                        }
                    }
            }
        }
        .frame(height: 290)
        .overlay {
            if visibleRecords.isEmpty {
                ContentUnavailableView {
                    Label("No Samples in This Window", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("Pan or select another range to inspect available history.")
                }
            }
        }
        .accessibilityLabel("Scrollable battery charge history")
    }

    @ChartContentBuilder
    private var historyLineMarks: some ChartContent {
        ForEach(chartSegments) { segment in
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
    }

    @ChartContentBuilder
    private var selectedHistoryMarks: some ChartContent {
        if let selectedRecord {
            RuleMark(x: .value("Selected time", selectedRecord.recordedAt))
                .foregroundStyle(.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            PointMark(
                x: .value("Selected time", selectedRecord.recordedAt),
                y: .value("Selected charge", selectedRecord.percentage)
            )
            .foregroundStyle(.tint)
            .symbolSize(56)
        }
    }

    private var historyInspector: some View {
        HStack(spacing: 12) {
            if let selectedRecord {
                Text(selectedRecord.recordedAt.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
                Text("\(selectedRecord.percentage)%")
                    .font(.headline)
                    .monospacedDigit()
                Label(sampleState(selectedRecord), systemImage: selectedRecord.isCharging ? "bolt.fill" : "battery.100")
                    .foregroundStyle(.secondary)
            } else {
                Label("Hover graph to inspect a sample", systemImage: "cursorarrow.rays")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(visibleRecords.count) samples")
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.caption)
        .frame(minHeight: 18)
    }

    private var windowTitle: String {
        "\(visibleStart.formatted(date: .abbreviated, time: .shortened)) – \(visibleEnd.formatted(date: .abbreviated, time: .shortened))"
    }

    private func sampleState(_ record: BatteryHistoryRecord) -> String {
        if record.isCharging { return "Charging" }
        return record.isConnectedToPower ? "Connected to power" : "On battery"
    }

    private func scrollToLatest() {
        let start = chartEnd.addingTimeInterval(-visibleDuration)
        scrollPosition = min(max(start, chartStart), maximumScrollStart)
    }

    private func moveWindow(by direction: Int) {
        let overlap: TimeInterval = 0.85
        let destination = scrollPosition.addingTimeInterval(Double(direction) * visibleDuration * overlap)
        scrollPosition = min(max(destination, chartStart), maximumScrollStart)
        selectedRecord = nil
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
