import SwiftUI

struct SettingsRootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var notifications: NotificationService
    @EnvironmentObject private var loginItem: LoginItemManager

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            ChargingSettingsView()
                .tabItem { Label("Battery", systemImage: "battery.75percent") }
            MenuBarSettingsView()
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
            NotificationSettingsView()
                .tabItem { Label("Notifications", systemImage: "bell") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 590, height: 410)
        .onAppear {
            DockIconVisibility.showForWindow()
        }
        .onAppear {
            loginItem.refresh()
            notifications.refreshAuthorization()
        }
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var loginItem: LoginItemManager

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { loginItem.isEnabled },
            set: { loginItem.setEnabled($0) }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Launch BitFi at login", isOn: launchAtLoginBinding)
                Text("Starts BitFi using macOS Login Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let statusMessage = loginItem.statusMessage {
                Section {
                    Label(statusMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                    Button("Open Login Items Settings") {
                        loginItem.openLoginItemsSettings()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

private struct ChargingSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    private var chargeLimitBinding: Binding<Double> {
        Binding(
            get: { settings.chargeLimit },
            set: { settings.setChargeLimit($0) }
        )
    }

    var body: some View {
        Form {
            Section("Charge Reminder") {
                Toggle("Enable charge-limit reminders", isOn: $settings.isChargeReminderEnabled)
                HStack {
                    Text("Target")
                    Slider(value: chargeLimitBinding, in: 50...100, step: 1)
                    Text("\(Int(settings.chargeLimit))%")
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
                Stepper("Custom target: \(Int(settings.chargeLimit))%", value: chargeLimitBinding, in: 50...100, step: 1)
            }

            Section {
                Text("BitFi sends a threshold reminder; public macOS APIs cannot enforce a custom hardware charging cap.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

private struct MenuBarSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Menu Bar Item") {
                Toggle("Show battery percentage", isOn: $settings.showPercentageInMenuBar)
                Text("BitFi stays available in the menu bar while it is running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

private struct NotificationSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var notifications: NotificationService

    var body: some View {
        Form {
            Section("Charge Limit") {
                Toggle("Send threshold reminders", isOn: $settings.notificationsEnabled)
                    .onChange(of: settings.notificationsEnabled, initial: false) { _, enabled in
                        if enabled, notifications.authorizationStatus == .notDetermined {
                            notifications.requestAuthorization()
                        }
                    }

                LabeledContent("System permission") {
                    Text(notifications.authorizationTitle)
                }

                if notifications.authorizationStatus == .notDetermined {
                    Button("Allow Notifications") {
                        notifications.requestAuthorization()
                    }
                } else if notifications.authorizationStatus == .denied {
                    Text("Enable notifications for BitFi in System Settings to receive reminders.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

private struct AboutSettingsView: View {
    private var version: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "Version \(shortVersion) (\($0))" } ?? "Version \(shortVersion)"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "battery.75percent")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("BitFi")
                .font(.title2.weight(.semibold))
            Text("Battery monitoring and charge-limit reminders")
                .foregroundStyle(.secondary)
            Text(version)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider().frame(width: 280).padding(.vertical, 4)

            Text("Live power data comes from public macOS IOKit APIs. BitFi does not use private charger controls.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(width: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}
