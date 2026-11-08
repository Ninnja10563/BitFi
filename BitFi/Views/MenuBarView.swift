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
    @State private var menuHistoryTimelineEnd = Date.now
    @State private var menuHistoryScrollPosition = Date.now.addingTimeInterval(-24 * 60 * 60)
    @State private var menuHistoryZoomFactor = 1.0
    @State private var menuHistoryMagnificationStartZoom: Double?
    @State private var menuHistoryMagnificationFocalDate: Date?
    @State private var systemAppMessage: String?

    private let menuHistoryBaseDuration: TimeInterval = 24 * 60 * 60
    private let menuHistoryMinimumVisibleDuration: TimeInterval = 15 * 60

    private var chargeLimitBinding: Binding<Double> {
        Binding(
            get: { settings.chargeLimit },
            set: { settings.setChargeLimit($0) }
        )
    }

    private var menuHistoryChartStart: Date {
        menuHistoryTimelineEnd.addingTimeInterval(-menuHistoryBaseDuration)
    }

    private var menuHistoryVisibleDuration: TimeInterval {
        max(menuHistoryMinimumVisibleDuration, menuHistoryBaseDuration / menuHistoryZoomFactor)
    }

    private var menuHistoryMaximumZoomFactor: Double {
        menuHistoryBaseDuration / menuHistoryMinimumVisibleDuration
    }

    private var menuHistoryCanZoomIn: Bool {
        menuHistoryZoomFactor < menuHistoryMaximumZoomFactor - 0.001
    }

    private var menuHistoryCanZoomOut: Bool {
        menuHistoryZoomFactor > 1.001
    }

    private var menuHistoryMaximumScrollStart: Date {
        max(menuHistoryChartStart, menuHistoryTimelineEnd.addingTimeInterval(-menuHistoryVisibleDuration))
    }

    private var menuHistoryVisibleStart: Date {
        min(max(menuHistoryScrollPosition, menuHistoryChartStart), menuHistoryMaximumScrollStart)
    }

    private var menuHistoryVisibleEnd: Date {
        min(menuHistoryTimelineEnd, menuHistoryVisibleStart.addingTimeInterval(menuHistoryVisibleDuration))
    }

    private var menuHistoryCanMoveForward: Bool {
        menuHistoryVisibleEnd < menuHistoryTimelineEnd.addingTimeInterval(-1)
    }

    private var menuHistoryDurationText: String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = menuHistoryVisibleDuration >= 60 * 60 ? [.hour, .minute] : [.minute]
        formatter.maximumUnitCount = 2
        return formatter.string(from: menuHistoryVisibleDuration) ?? "History"
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
            refreshMenuHistoryTimeline()
        }
        .onDisappear {
            activityMonitor.setLiveSampling(false, for: .menuBar)
        }
        .onChange(of: selectedPanel) { _, panel in
            if panel != .history {
                selectedHistoryRecord = nil
            } else {
                refreshMenuHistoryTimeline()
            }
            updateMenuBarLiveSampling()
            if panel == .apps, selectedAppMode.measure != nil {
                activityMonitor.refresh()
            }
        }
        .onChange(of: history.latestRecordedAt) { _, _ in
            guard selectedPanel == .history else { return }
            refreshMenuHistoryTimeline()
        }
        .onChange(of: menuHistoryScrollPosition) { _, _ in
            selectedHistoryRecord = nil
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
                        height: 12
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
        let endDate = menuHistoryTimelineEnd
        let startDate = menuHistoryChartStart
        let records = history.records(from: startDate, through: endDate)
        let segments = history.segments(from: startDate, through: endDate)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Battery History", systemImage: "chart.xyaxis.line")
                    .font(.headline)
                Spacer()
                HStack(spacing: 2) {
                    Button {
                        changeMenuHistoryZoom(by: 0.5)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .help("Zoom out history")
                    .accessibilityLabel("Zoom out menu bar history")
                    .disabled(!menuHistoryCanZoomOut)

                    Button {
                        changeMenuHistoryZoom(by: 2)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .help("Zoom in history")
                    .accessibilityLabel("Zoom in menu bar history")
                    .disabled(!menuHistoryCanZoomIn)
                }
                .buttonStyle(.borderless)
                Text(menuHistoryDurationText)
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
        .chartXScale(domain: menuHistoryChartStart...menuHistoryTimelineEnd)
        .chartScrollableAxes(.horizontal)
        .chartXVisibleDomain(length: menuHistoryVisibleDuration)
        .chartScrollPosition(x: $menuHistoryScrollPosition)
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
                            let record = history.nearestRecord(
                                to: date,
                                from: menuHistoryVisibleStart,
                                through: menuHistoryVisibleEnd
                            )
                            if selectedHistoryRecord?.id != record?.id {
                                selectedHistoryRecord = record
                            }
                        case .ended:
                            selectedHistoryRecord = nil
                        }
                    }
            }
        }
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    if menuHistoryMagnificationStartZoom == nil {
                        menuHistoryMagnificationStartZoom = menuHistoryZoomFactor
                        menuHistoryMagnificationFocalDate = menuHistoryVisibleStart
                            .addingTimeInterval(menuHistoryVisibleDuration / 2)
                    }
                    changeMenuHistoryZoom(
                        to: (menuHistoryMagnificationStartZoom ?? menuHistoryZoomFactor)
                            * Double(value.magnification),
                        focalDate: menuHistoryMagnificationFocalDate
                    )
                }
                .onEnded { _ in
                    menuHistoryMagnificationStartZoom = nil
                    menuHistoryMagnificationFocalDate = nil
                }
        )
        .frame(height: 156)
        .accessibilityLabel("Battery charge history")
        .accessibilityHint("Use zoom controls or pinch to change visible time span. Hover a saved sample to show its time and charge.")
    }

    private func menuBarHistoryCaption(records: [BatteryHistoryRecord]) -> some View {
        let visibleSampleCount = history.window(
            from: menuHistoryVisibleStart,
            through: menuHistoryVisibleEnd
        ).count

        return HStack {
            if let selectedHistoryRecord {
                Text(selectedHistoryRecord.recordedAt.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
                Text("\(selectedHistoryRecord.percentage)%")
                    .fontWeight(.semibold)
            } else {
                Text("Latest \(records.last?.percentage ?? 0)%")
            }
            Spacer()
            Text("\(visibleSampleCount) samples")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .monospacedDigit()
    }

    private func refreshMenuHistoryTimeline() {
        let wasAtLatest = !menuHistoryCanMoveForward
        menuHistoryTimelineEnd = .now
        if wasAtLatest {
            scrollMenuHistoryToLatest()
        }
    }

    private func scrollMenuHistoryToLatest() {
        let start = menuHistoryTimelineEnd.addingTimeInterval(-menuHistoryVisibleDuration)
        menuHistoryScrollPosition = min(max(start, menuHistoryChartStart), menuHistoryMaximumScrollStart)
    }

    private func changeMenuHistoryZoom(by multiplier: Double) {
        changeMenuHistoryZoom(to: menuHistoryZoomFactor * multiplier)
    }

    private func changeMenuHistoryZoom(to requestedZoom: Double, focalDate: Date? = nil) {
        let oldDuration = menuHistoryVisibleDuration
        let newZoom = min(max(requestedZoom, 1), menuHistoryMaximumZoomFactor)
        guard abs(newZoom - menuHistoryZoomFactor) > 0.001 else { return }

        let focalDate = focalDate ?? menuHistoryVisibleStart.addingTimeInterval(oldDuration / 2)
        let newDuration = max(menuHistoryMinimumVisibleDuration, menuHistoryBaseDuration / newZoom)
        let maximumStart = max(menuHistoryChartStart, menuHistoryTimelineEnd.addingTimeInterval(-newDuration))
        let newStart = focalDate.addingTimeInterval(-newDuration / 2)

        selectedHistoryRecord = nil
        menuHistoryZoomFactor = newZoom
        menuHistoryScrollPosition = min(max(newStart, menuHistoryChartStart), maximumStart)
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
