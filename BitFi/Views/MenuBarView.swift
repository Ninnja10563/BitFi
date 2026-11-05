import AppKit
import Charts
import SwiftUI

private enum MenuBarPanel: String, CaseIterable, Identifiable {
    case status
    case history
    case apps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: "Status"
        case .history: "History"
        case .apps: "Apps"
        }
    }
}

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var monitor: BatteryMonitor
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var reminder: ChargeReminderEngine
    @EnvironmentObject private var history: BatteryHistoryStore
    @EnvironmentObject private var activityMonitor: AppActivityMonitor

    @State private var selectedPanel: MenuBarPanel = .status
    @State private var selectedAppMode: AppActivityChartMode = .cpu
    @State private var selectedHistoryRecord: BatteryHistoryRecord?
    @State private var systemAppMessage: String?

    private var chargeLimitBinding: Binding<Double> {
        Binding(
            get: { settings.chargeLimit },
            set: { settings.setChargeLimit($0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Menu bar content", selection: $selectedPanel) {
                ForEach(MenuBarPanel.allCases) { panel in
                    Text(panel.title).tag(panel)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            Divider().padding(.vertical, 14)

            selectedPanelView

            Divider().padding(.vertical, 14)

            HStack {
                Button("Open BitFi") {
                    DockIconVisibility.showForWindow()
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                    DockIconVisibility.synchronizeOnNextRunLoop()
                }
                Spacer()
                SettingsLink {
                    Text("Settings…")
                }
            }
        }
        .padding(16)
        .frame(width: 354)
        .onAppear {
            monitor.start()
            history.start(monitor: monitor)
            activityMonitor.start()
        }
        .onDisappear {
            activityMonitor.setLiveSampling(false, for: .menuBar)
        }
        .onChange(of: selectedPanel) { _, panel in
            if panel != .history {
                selectedHistoryRecord = nil
            }
            updateMenuBarLiveSampling()
            if panel == .apps, selectedAppMode.measure != nil {
                activityMonitor.refresh()
            }
        }
    }

    @ViewBuilder
    private var selectedPanelView: some View {
        switch selectedPanel {
        case .status:
            statusPanel
        case .history:
            historyPanel
        case .apps:
            appsPanel
        }
    }

    private var statusPanel: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 7) {
                    BatteryLevelSymbol(
                        snapshot: monitor.snapshot,
                        tint: .accentColor,
                        width: 25,
                        height: 15
                    )
                    Text("Battery")
                        .font(.headline)
                }
                Spacer()
                Text(monitor.snapshot.percentageText)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
            }

            if monitor.snapshot.isAvailable {
                BatteryLevelBar(percentage: monitor.snapshot.percentage)
                    .padding(.top, 10)

                Divider().padding(.vertical, 14)

                VStack(spacing: 11) {
                    BatteryMetricRow(title: "Status", value: monitor.snapshot.statusTitle)
                    BatteryMetricRow(title: "Power Source", value: monitor.snapshot.powerSource.title)
                    BatteryMetricRow(title: "Battery Health", value: monitor.snapshot.healthSummaryText)
                    BatteryMetricRow(title: "Temperature", value: monitor.snapshot.temperatureText)
                }

                Divider().padding(.vertical, 14)

                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Charge-limit reminders", isOn: $settings.isChargeReminderEnabled)

                    HStack {
                        Text("Target")
                        Slider(value: chargeLimitBinding, in: 50...100, step: 1)
                        Text("\(Int(settings.chargeLimit))%")
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }

                    ChargeReminderStatusView(
                        state: reminder.state,
                        limit: Int(settings.chargeLimit)
                    )
                }

                Divider().padding(.vertical, 14)

                if reminder.isPausedForCurrentPowerSession {
                    Button("Resume Monitoring") {
                        reminder.resumeMonitoring()
                        monitor.refresh()
                    }
                } else {
                    Button("Charge to 100% This Session") {
                        reminder.pauseForCurrentPowerSession()
                    }
                    .disabled(!settings.isChargeReminderEnabled || !monitor.snapshot.isConnectedToPower)
                }
            } else {
                Text(monitor.snapshot.unavailableReason ?? "Battery data unavailable.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 22)
            }
        }
    }

    private var historyPanel: some View {
        let endDate = Date.now
        let startDate = endDate.addingTimeInterval(-24 * 60 * 60)
        let records = history.records(from: startDate, through: endDate)
        let segments = history.segments(from: startDate, through: endDate)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Battery History", systemImage: "chart.xyaxis.line")
                    .font(.headline)
                Spacer()
                Text("24 hours")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if records.isEmpty {
                ContentUnavailableView {
                    Label("Gathering Samples", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("BitFi saves readings while running.")
                }
                .frame(maxWidth: .infinity, minHeight: 156)
            } else {
                menuBarHistoryChart(records: records, segments: segments)
                menuBarHistoryCaption(records: records)
            }

            Text("Gaps mean BitFi was not running, or Mac was asleep or shut down.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func menuBarHistoryChart(
        records: [BatteryHistoryRecord],
        segments: [BatteryHistorySegment]
    ) -> some View {
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
                }
            }
            if records.count == 1, let record = records.first {
                PointMark(
                    x: .value("Time", record.recordedAt),
                    y: .value("Charge", record.percentage)
                )
                .foregroundStyle(.tint)
                .symbolSize(42)
            }
            if let selectedHistoryRecord {
                RuleMark(x: .value("Selected time", selectedHistoryRecord.recordedAt))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(
                    x: .value("Selected time", selectedHistoryRecord.recordedAt),
                    y: .value("Selected charge", selectedHistoryRecord.percentage)
                )
                .foregroundStyle(.tint)
                .symbolSize(58)
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let percentage = value.as(Int.self) {
                        Text("\(percentage)%")
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3))
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
                                selectedHistoryRecord = nil
                                return
                            }
                            let plotFrame = geometry[plotAnchor]
                            guard plotFrame.contains(location),
                                  let date = proxy.value(
                                      atX: location.x - plotFrame.origin.x,
                                      as: Date.self
                                  )
                            else {
                                selectedHistoryRecord = nil
                                return
                            }
                            let record = nearestHistoryRecord(to: date, in: records)
                            if selectedHistoryRecord?.id != record?.id {
                                selectedHistoryRecord = record
                            }
                        case .ended:
                            selectedHistoryRecord = nil
                        }
                    }
            }
        }
        .frame(height: 156)
        .accessibilityLabel("Battery charge history")
        .accessibilityHint("Hover a saved sample to show its time and charge.")
    }

    private func menuBarHistoryCaption(records: [BatteryHistoryRecord]) -> some View {
        HStack {
            if let selectedHistoryRecord {
                Text(selectedHistoryRecord.recordedAt.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
                Text("\(selectedHistoryRecord.percentage)%")
                    .fontWeight(.semibold)
            } else {
                Text("Latest \(records.last?.percentage ?? 0)%")
            }
            Spacer()
            Text("\(records.count) samples")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .monospacedDigit()
    }

    private func nearestHistoryRecord(
        to date: Date,
        in records: [BatteryHistoryRecord]
    ) -> BatteryHistoryRecord? {
        guard !records.isEmpty else { return nil }

        var lowerBound = records.startIndex
        var upperBound = records.endIndex
        while lowerBound < upperBound {
            let middle = (lowerBound + upperBound) / 2
            if records[middle].recordedAt < date {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }

        let firstLaterIndex = lowerBound
        let later = firstLaterIndex < records.endIndex ? records[firstLaterIndex] : nil
        let earlier = firstLaterIndex > records.startIndex ? records[firstLaterIndex - 1] : nil
        switch (earlier, later) {
        case let (earlier?, later?):
            return date.timeIntervalSince(earlier.recordedAt) <= later.recordedAt.timeIntervalSince(date)
                ? earlier
                : later
        case let (earlier?, nil): return earlier
        case let (nil, later?): return later
        case (nil, nil): return nil
        }
    }

    private var appsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("App Activity", systemImage: "chart.pie")
                    .font(.headline)
                Spacer()
                Button {
                    systemAppMessage = SystemAppLauncher.openActivityMonitor()
                        ? nil
                        : "Activity Monitor is unavailable."
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .help("Open Activity Monitor for actual per-process Energy Impact")
                Button {
                    monitor.refresh()
                    activityMonitor.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh app activity")
            }

            Picker("Activity mode", selection: $selectedAppMode) {
                ForEach(AppActivityChartMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            if selectedAppMode.measure != nil {
                Label("Live · 2 sec", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let systemAppMessage {
                Text(systemAppMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if selectedAppMode.measure != nil {
                Text("Actual per-process Energy Impact is available in Activity Monitor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if selectedAppMode == .energyLevel {
                energyLevelPanel
            } else if let measure = selectedAppMode.measure {
                appMeasurementPanel(for: measure)
            }
        }
        .onChange(of: selectedAppMode) { _, mode in
            updateMenuBarLiveSampling()
            monitor.refresh()
            if mode != .energyLevel {
                activityMonitor.refresh()
            }
        }
    }

    @ViewBuilder
    private var energyLevelPanel: some View {
        if monitor.snapshot.isAvailable {
            HStack(spacing: 16) {
                BatteryEnergyLevelPieChart(snapshot: monitor.snapshot, diameter: 136)
                VStack(alignment: .leading, spacing: 6) {
                    Text(monitor.snapshot.percentageText)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    Text(monitor.snapshot.statusTitle)
                        .font(.callout)
                    Text(monitor.snapshot.powerSource.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Text("Actual device charge. Open Activity Monitor for per-process Energy Impact.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(monitor.snapshot.unavailableReason ?? "Battery data unavailable.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 136, alignment: .leading)
        }
    }

    @ViewBuilder
    private func appMeasurementPanel(for measure: AppActivityMeasure) -> some View {
        let slices = activityMonitor.slices(for: measure)

        if let errorMessage = activityMonitor.errorMessage {
            Text(errorMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 136, alignment: .leading)
        } else if slices.isEmpty {
            Text("No visible app bundles reported measurable \(measure.title.lowercased()) activity in this sample.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 136, alignment: .leading)
        } else {
            HStack(alignment: .center, spacing: 16) {
                AppMetricPieChart(slices: slices, measure: measure, diameter: 136)

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(slices.prefix(4)) { slice in
                        HStack(spacing: 8) {
                            Text(slice.name)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(slice.valueText(for: measure))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func updateMenuBarLiveSampling() {
        let shouldSample = selectedPanel == .apps && selectedAppMode.measure != nil
        activityMonitor.setLiveSampling(shouldSample, for: .menuBar)
    }
}
