import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var monitor: BatteryMonitor
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var reminder: ChargeReminderEngine

    let openChargeControls: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                BatteryHeader(snapshot: monitor.snapshot)

                if monitor.snapshot.isAvailable {
                    BatteryLevelBar(percentage: monitor.snapshot.percentage)
                        .animation(.easeInOut(duration: 0.2), value: monitor.snapshot.percentage)

                    GroupBox {
                        VStack(spacing: 13) {
                            BatteryMetricRow(
                                title: "Power source",
                                value: monitor.snapshot.powerSource.title,
                                symbolName: "powerplug"
                            )
                            BatteryMetricRow(
                                title: "Charge state",
                                value: monitor.snapshot.statusTitle,
                                symbolName: monitor.snapshot.statusSymbolName
                            )
                            BatteryMetricRow(
                                title: "Time remaining",
                                value: monitor.snapshot.isConnectedToPower
                                    ? monitor.snapshot.timeToFullText
                                    : monitor.snapshot.timeToEmptyText,
                                symbolName: "clock"
                            )
                            BatteryMetricRow(
                                title: "Battery health",
                                value: monitor.snapshot.healthSummaryText,
                                symbolName: "heart.text.square"
                            )
                        }
                        .padding(.vertical, 4)
                    } label: {
                        Label("Current status", systemImage: "bolt.horizontal.circle")
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            ChargeReminderStatusView(
                                state: reminder.state,
                                limit: Int(settings.chargeLimit)
                            )

                            Divider()

                            Text("BitFi monitors your selected threshold and can remind you to unplug power. macOS does not provide a public API to stop charging at a custom percentage.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            HStack {
                                Button("Charge Controls", action: openChargeControls)
                                Spacer()
                                Text("Target \(Int(settings.chargeLimit))%")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    } label: {
                        Label("Charge protection", systemImage: "battery.75percent")
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .accessibilityHidden(true)
                        Text("Updated \(monitor.snapshot.updatedAt, style: .relative)")
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                } else {
                    BatteryUnavailableView(reason: monitor.snapshot.unavailableReason ?? "Battery data is unavailable.")
                        .frame(maxWidth: .infinity, minHeight: 260)
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .navigationTitle("Overview")
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
