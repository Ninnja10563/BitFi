import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var monitor: BatteryMonitor
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var reminder: ChargeReminderEngine

    private var chargeLimitBinding: Binding<Double> {
        Binding(
            get: { settings.chargeLimit },
            set: { settings.setChargeLimit($0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Battery")
                    .font(.headline)
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
                    BatteryMetricRow(
                        title: "Battery Health",
                        value: monitor.snapshot.healthText
                    )
                    BatteryMetricRow(
                        title: "Temperature",
                        value: monitor.snapshot.temperatureText
                    )
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

            Divider().padding(.vertical, 14)

            HStack {
                Button("Open BitFi") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                SettingsLink {
                    Text("Settings…")
                }
            }
        }
        .padding(16)
        .frame(width: 330)
        .onAppear { monitor.refresh() }
    }
}
