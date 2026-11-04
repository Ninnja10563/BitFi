import SwiftUI

struct ChargeControlsView: View {
    @EnvironmentObject private var monitor: BatteryMonitor
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var reminder: ChargeReminderEngine

    private let commonLimits: [Double] = [70, 80, 85, 90]

    private var chargeLimitBinding: Binding<Double> {
        Binding(
            get: { settings.chargeLimit },
            set: { settings.setChargeLimit($0) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Charge limit")
                        .font(.title2.weight(.semibold))
                    Text("Set a threshold. BitFi monitors live battery state and reminds you when it is time to unplug.")
                        .foregroundStyle(.secondary)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 18) {
                        Toggle("Enable charge-limit reminders", isOn: $settings.isChargeReminderEnabled)

                        Divider()

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Target")
                                Spacer()
                                Text("\(Int(settings.chargeLimit))%")
                                    .font(.title3.weight(.semibold))
                                    .monospacedDigit()
                            }

                            Slider(value: chargeLimitBinding, in: 50...100, step: 1)
                                .accessibilityLabel("Charge reminder target")
                                .accessibilityValue("\(Int(settings.chargeLimit)) percent")

                            HStack {
                                Text("50%")
                                Spacer()
                                Text("100%")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Common limits")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Picker("Common limits", selection: chargeLimitBinding) {
                                ForEach(commonLimits, id: \.self) { limit in
                                    Text("\(Int(limit))%").tag(limit)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }

                        HStack {
                            Stepper("Custom target", value: chargeLimitBinding, in: 50...100, step: 1)
                            Spacer()
                            TextField("Target", value: chargeLimitBinding, format: .number.precision(.fractionLength(0)))
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .frame(width: 58)
                            Text("%")
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        ChargeReminderStatusView(
                            state: reminder.state,
                            limit: Int(settings.chargeLimit)
                        )

                        HStack {
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

                            Spacer()

                            Button("Reset") {
                                settings.resetChargeSettings()
                                reminder.resumeMonitoring()
                                monitor.refresh()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    Label("Charge reminder", systemImage: "battery.75percent")
                }

                GroupBox {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("Hardware charge caps are not exposed through public macOS APIs. This app does not alter charging firmware, install privileged helpers, or claim to stop charging.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                } label: {
                    Text("Hardware control")
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .navigationTitle("Charge Controls")
    }
}
