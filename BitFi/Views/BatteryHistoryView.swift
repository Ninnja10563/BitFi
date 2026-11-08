import Charts
import SwiftUI

struct BatteryHistoryView: View {
    @EnvironmentObject private var history: BatteryHistoryStore
    @State private var selectedRange: BatteryHistoryRange = .day
    @State private var scrollPosition = Date.now.addingTimeInterval(-24 * 60 * 60)
    @State private var selectedRecord: BatteryHistoryRecord?
    @State private var timelineEnd = Date.now
    @State private var zoomFactor = 1.0
    @State private var magnificationStartZoom: Double?
    @State private var magnificationFocalDate: Date?

    private let minimumVisibleDuration: TimeInterval = 15 * 60
    private let maximumZoomFactor = 1_024.0

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

    private var baseVisibleDuration: TimeInterval {
        selectedRange.visibleDuration ?? max(chartEnd.timeIntervalSince(chartStart), 60 * 60)
    }

    private var visibleDuration: TimeInterval {
        max(minimumVisibleDuration, baseVisibleDuration / zoomFactor)
    }

    private var maximumAllowedZoomFactor: Double {
        min(maximumZoomFactor, max(1, baseVisibleDuration / minimumVisibleDuration))
    }

    private var canZoomIn: Bool {
        zoomFactor < maximumAllowedZoomFactor - 0.001
    }

    private var canZoomOut: Bool {
        zoomFactor > 1.001
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

    private var visibleWindow: BatteryHistoryWindow {
        history.window(from: visibleStart, through: visibleEnd)
    }

    private var hasHistory: Bool {
        history.earliestRecordedAt != nil
    }

    private var canMoveBack: Bool {
        visibleStart > chartStart.addingTimeInterval(1)
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
                        Text("Saved local charge samples. Pan, zoom, navigate, or hover to inspect.")
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
                    HistorySummary(window: visibleWindow)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Samples save locally for up to two years while BitFi runs. The line joins recorded samples; BitFi never creates a reading while it is unavailable.")
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
            zoomFactor = 1
            scrollToLatest()
        }
        .onChange(of: scrollPosition) { _, _ in
            selectedRecord = nil
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

            HStack(spacing: 2) {
                Button {
                    changeZoom(by: 0.5)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .help("Zoom out history")
                .accessibilityLabel("Zoom out history")
                .disabled(!canZoomOut)

                Button {
                    changeZoom(by: 2)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("Zoom in history")
                .accessibilityLabel("Zoom in history")
                .disabled(!canZoomIn)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Divider()
                .frame(height: 16)

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
                            let nearestRecord = history.nearestRecord(
                                to: date,
                                from: visibleStart,
                                through: visibleEnd
                            )
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
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    if magnificationStartZoom == nil {
                        magnificationStartZoom = zoomFactor
                        magnificationFocalDate = visibleStart.addingTimeInterval(visibleDuration / 2)
                    }
                    changeZoom(
                        to: (magnificationStartZoom ?? zoomFactor) * Double(value.magnification),
                        focalDate: magnificationFocalDate
                    )
                }
                .onEnded { _ in
                    magnificationStartZoom = nil
                    magnificationFocalDate = nil
                }
        )
        .frame(height: 290)
        .overlay {
            if visibleWindow.isEmpty {
                ContentUnavailableView {
                    Label("No Samples in This Window", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("Pan or select another range to inspect available history.")
                }
            }
        }
        .accessibilityLabel("Scrollable battery charge history")
        .accessibilityHint("Use zoom controls or pinch to change visible time span. Hover a saved sample to show its time and charge.")
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
            .symbolSize(64)
            .annotation(
                position: selectedRecord.percentage >= 72 ? .bottom : .top,
                alignment: .center,
                spacing: 9
            ) {
                HistoryHoverCallout(record: selectedRecord)
                    .allowsHitTesting(false)
            }
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
            Text("\(visibleWindow.count) samples")
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

    private func changeZoom(by multiplier: Double) {
        changeZoom(to: zoomFactor * multiplier)
    }

    private func changeZoom(to requestedZoom: Double, focalDate: Date? = nil) {
        let oldDuration = visibleDuration
        let newZoom = min(max(requestedZoom, 1), maximumAllowedZoomFactor)
        guard abs(newZoom - zoomFactor) > 0.001 else { return }

        let focalDate = focalDate ?? visibleStart.addingTimeInterval(oldDuration / 2)
        let newDuration = max(minimumVisibleDuration, baseVisibleDuration / newZoom)
        let maximumStart = max(chartStart, chartEnd.addingTimeInterval(-newDuration))
        let newStart = focalDate.addingTimeInterval(-newDuration / 2)

        selectedRecord = nil
        zoomFactor = newZoom
        scrollPosition = min(max(newStart, chartStart), maximumStart)
    }

    private func moveWindow(by direction: Int) {
        let overlap: TimeInterval = 0.85
        let destination = scrollPosition.addingTimeInterval(Double(direction) * visibleDuration * overlap)
        scrollPosition = min(max(destination, chartStart), maximumScrollStart)
        selectedRecord = nil
    }
}

private struct HistorySummary: View {
    let window: BatteryHistoryWindow

    private var first: BatteryHistoryRecord? { window.first }
    private var latest: BatteryHistoryRecord? { window.last }

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

private struct HistoryHoverCallout: View {
    let record: BatteryHistoryRecord

    var body: some View {
        HStack(spacing: 7) {
            Text("\(record.percentage)%")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            Text(record.recordedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.percentage) percent at \(record.recordedAt.formatted(date: .abbreviated, time: .shortened))")
    }
}
