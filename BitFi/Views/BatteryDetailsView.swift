import SwiftUI

struct BatteryDetailsView: View {
    @EnvironmentObject private var monitor: BatteryMonitor

    var body: some View {
        Group {
            if monitor.snapshot.isAvailable {
                Form {
                    Section("Power") {
                        BatteryMetricRow(title: "Power Source", value: monitor.snapshot.powerSource.title)
                        BatteryMetricRow(title: "Charge State", value: monitor.snapshot.statusTitle)
                        BatteryMetricRow(title: "Time to Full", value: monitor.snapshot.timeToFullText)
                        BatteryMetricRow(title: "Time Remaining", value: monitor.snapshot.timeToEmptyText)
                    }

                    Section("Capacity") {
                        BatteryMetricRow(title: "Current Capacity", value: monitor.snapshot.percentageText)
                        BatteryMetricRow(
                            title: "Reported Maximum",
                            value: monitor.snapshot.maximumCapacity.map { "\($0)%" } ?? "Unavailable"
                        )
                        BatteryMetricRow(
                            title: "Cycle Count",
                            value: monitor.snapshot.cycleCount.map(String.init) ?? "Unavailable"
                        )
                    }

                    Section("Health") {
                        BatteryMetricRow(title: "Battery Health", value: monitor.snapshot.health ?? "Unavailable")
                        BatteryMetricRow(title: "Condition", value: monitor.snapshot.healthCondition ?? "Unavailable")
                        BatteryMetricRow(
                            title: "Maximum Capacity",
                            value: monitor.snapshot.healthCapacityText
                        )
                        BatteryMetricRow(title: "Temperature", value: monitor.snapshot.temperatureText)
                    }

                    Section("Electrical") {
                        BatteryMetricRow(title: "Voltage", value: monitor.snapshot.voltageText)
                        BatteryMetricRow(title: "Current", value: monitor.snapshot.amperageText)
                    }

                    Section {
                        BatteryMetricRow(
                            title: "Last Updated",
                            value: monitor.snapshot.updatedAt.formatted(date: .abbreviated, time: .standard)
                        )
                    }
                }
                .formStyle(.grouped)
                .padding(20)
            } else {
                BatteryUnavailableView(reason: monitor.snapshot.unavailableReason ?? "Battery data is unavailable.")
            }
        }
        .navigationTitle("Battery Details")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    monitor.refresh()
                } label: {
                    Label("Refresh Battery Status", systemImage: "arrow.clockwise")
                }
                .help("Refresh Battery Status")
            }
        }
    }
}
