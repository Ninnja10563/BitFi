import SwiftUI

@main
struct BitFiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var monitor: BatteryMonitor
    @StateObject private var settings: AppSettings
    @StateObject private var notifications: NotificationService
    @StateObject private var reminder: ChargeReminderEngine
    @StateObject private var loginItem: LoginItemManager
    @StateObject private var history: BatteryHistoryStore
    @StateObject private var activityMonitor: AppActivityMonitor

    init() {
        let notificationService = NotificationService()
        _monitor = StateObject(wrappedValue: BatteryMonitor())
        _settings = StateObject(wrappedValue: AppSettings())
        _notifications = StateObject(wrappedValue: notificationService)
        _reminder = StateObject(wrappedValue: ChargeReminderEngine(notificationService: notificationService))
        _loginItem = StateObject(wrappedValue: LoginItemManager())
        _history = StateObject(wrappedValue: BatteryHistoryStore())
        _activityMonitor = StateObject(wrappedValue: AppActivityMonitor())
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environmentObject(monitor)
                .environmentObject(settings)
                .environmentObject(notifications)
                .environmentObject(reminder)
                .environmentObject(loginItem)
                .environmentObject(history)
                .environmentObject(activityMonitor)
        }
        .defaultSize(width: 900, height: 630)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsRootView()
                .environmentObject(settings)
                .environmentObject(notifications)
                .environmentObject(loginItem)
        }

        MenuBarExtra {
            MenuBarView()
                .environmentObject(monitor)
                .environmentObject(settings)
                .environmentObject(reminder)
                .environmentObject(history)
                .environmentObject(activityMonitor)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: monitor.snapshot.batterySymbolName)
                    .font(.system(size: 15, weight: .medium))
                    .imageScale(.medium)
                if monitor.snapshot.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .bold))
                }
                if settings.showPercentageInMenuBar {
                    Text(monitor.snapshot.percentageText)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                }
            }
            .accessibilityLabel("Battery \(monitor.snapshot.percentageText), \(monitor.snapshot.statusTitle)")
        }
        .menuBarExtraStyle(.window)

        .commands {
            CommandGroup(after: .appInfo) {
                Button("Refresh Battery Status") {
                    monitor.refresh()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}
