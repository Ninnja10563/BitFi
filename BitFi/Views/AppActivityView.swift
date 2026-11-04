import Charts
import SwiftUI

struct AppActivityView: View {
    @EnvironmentObject private var monitor: BatteryMonitor
    @EnvironmentObject private var activityMonitor: AppActivityMonitor
    @State private var selectedMode: AppActivityChartMode = .cpu

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("App Activity")
                            .font(.title2.weight(.semibold))
                        Text(selectedMode.subtitle)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        monitor.refresh()
                        activityMonitor.refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }

                Picker("Chart mode", selection: $selectedMode) {
                    ForEach(AppActivityChartMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                Label(liveUpdateText, systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                chartContent

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(chartNote)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        if let updatedAt = activityMonitor.lastUpdated,
                           selectedMode != .energyLevel {
                            Text("Updated \(updatedAt, style: .relative)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    Label("About this chart", systemImage: "info.circle")
                }
            }
            .padding(28)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .navigationTitle("App Activity")
        .onAppear {
            updateLiveSampling()
        }
        .onDisappear {
            activityMonitor.setLiveSampling(false, for: .mainWindow)
        }
        .onChange(of: selectedMode) { _, mode in
            updateLiveSampling()
            monitor.refresh()
            if mode != .energyLevel {
                activityMonitor.refresh()
            }
        }
    }

    @ViewBuilder
    private var chartContent: some View {
        if selectedMode == .energyLevel {
            if monitor.snapshot.isAvailable {
                HStack(alignment: .center, spacing: 36) {
                    BatteryEnergyLevelPieChart(snapshot: monitor.snapshot, diameter: 250)
                    VStack(alignment: .leading, spacing: 12) {
                        BatteryMetricRow(title: "Charge", value: monitor.snapshot.percentageText)
                        BatteryMetricRow(title: "Status", value: monitor.snapshot.statusTitle)
                        BatteryMetricRow(title: "Power Source", value: monitor.snapshot.powerSource.title)
                    }
                    .frame(maxWidth: 300, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                ContentUnavailableView {
                    Label("Battery Level Unavailable", systemImage: "battery.0")
                } description: {
                    Text(monitor.snapshot.unavailableReason ?? "macOS did not report an internal battery.")
                }
                .frame(maxWidth: .infinity, minHeight: 280)
            }
        } else if let measure = selectedMode.measure {
            measurementContent(for: measure)
        }
    }

    @ViewBuilder
    private func measurementContent(for measure: AppActivityMeasure) -> some View {
        let slices = activityMonitor.slices(for: measure)

        if let errorMessage = activityMonitor.errorMessage {
            ContentUnavailableView {
                Label("App Activity Unavailable", systemImage: "chart.pie")
            } description: {
                Text(errorMessage)
            }
            .frame(maxWidth: .infinity, minHeight: 280)
        } else if slices.isEmpty {
            ContentUnavailableView {
                Label("No \(measure.title) Activity", systemImage: "chart.pie")
            } description: {
                Text("No visible app bundles reported measurable \(measure.title.lowercased()) activity in this sample.")
            }
            .frame(maxWidth: .infinity, minHeight: 280)
        } else {
            HStack(alignment: .center, spacing: 36) {
                AppMetricPieChart(slices: slices, measure: measure, diameter: 250)

                VStack(spacing: 12) {
                    ForEach(slices) { slice in
                        HStack {
                            Text(slice.name)
                                .lineLimit(1)
                            Spacer()
                            Text(slice.valueText(for: measure))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                }
                .frame(maxWidth: 360, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 280)
        }
    }

    private var chartNote: String {
        switch selectedMode {
        case .cpu:
            "CPU values come from macOS process reporting, grouped by visible app bundle. They are workload signals, not battery-energy measurements."
        case .memory:
            "Memory values are current resident memory from macOS process reporting, grouped by visible app bundle."
        case .energyLevel:
            "Energy Level shows actual battery state of charge reported by macOS. macOS does not expose a public per-app battery-energy API."
        }
    }

    private var liveUpdateText: String {
        selectedMode.measure == nil
            ? "Updates from live battery-state changes"
            : "Live updates every 2 seconds while open"
    }

    private func updateLiveSampling() {
        activityMonitor.setLiveSampling(selectedMode.measure != nil, for: .mainWindow)
    }
}

struct AppMetricPieChart: View {
    let slices: [AppActivitySlice]
    let measure: AppActivityMeasure
    let diameter: CGFloat

    private var total: Double {
        slices.reduce(0) { $0 + $1.value(for: measure) }
    }

    private var totalText: String {
        switch measure {
        case .cpu:
            return String(format: "%.1f%%", total)
        case .memory:
            return ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .memory)
        }
    }

    var body: some View {
        ZStack {
            Chart(slices) { slice in
                SectorMark(
                    angle: .value(measure.chartTitle, slice.value(for: measure)),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5
                )
                .cornerRadius(3)
                .foregroundStyle(by: .value("App", slice.name))
            }
            .chartLegend(.hidden)

            VStack(spacing: 2) {
                Text(totalText)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text(measure.title == "CPU" ? "CPU total" : "resident memory")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel("Running app \(measure.chartTitle.lowercased()) chart")
    }
}

struct BatteryEnergyLevelPieChart: View {
    let snapshot: BatterySnapshot
    let diameter: CGFloat

    private var slices: [BatteryEnergySlice] {
        guard let percentage = snapshot.percentage else { return [] }
        return [
            BatteryEnergySlice(id: "charged", name: "Charged", value: Double(percentage)),
            BatteryEnergySlice(id: "remaining", name: "Remaining", value: Double(100 - percentage))
        ]
        .filter { $0.value > 0 }
    }

    var body: some View {
        ZStack {
            Chart(slices) { slice in
                SectorMark(
                    angle: .value("Battery level", slice.value),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5
                )
                .cornerRadius(3)
                .foregroundStyle(by: .value("Battery level", slice.name))
            }
            .chartLegend(.hidden)

            VStack(spacing: 2) {
                Text(snapshot.percentageText)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text(snapshot.statusTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityLabel("Battery charge \(snapshot.percentageText)")
    }
}

private struct BatteryEnergySlice: Identifiable {
    let id: String
    let name: String
    let value: Double
}
