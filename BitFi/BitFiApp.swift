import SwiftUI

@main
struct BitFiApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var monitor: BatteryMonitor
    @StateObject private var settings: AppSettings
    @StateObject private var notifications: NotificationService
    @StateObject private var reminder: ChargeReminderEngine
    @StateObject private var loginItem: LoginItemManager

    init() {
        let notificationService = NotificationService()
        _monitor = StateObject(wrappedValue: BatteryMonitor())
        _settings = StateObject(wrappedValue: AppSettings())
        _notifications = StateObject(wrappedValue: notificationService)
        _reminder = StateObject(wrappedValue: ChargeReminderEngine(notificationService: notificationService))
        _loginItem = StateObject(wrappedValue: LoginItemManager())
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environmentObject(monitor)
                .environmentObject(settings)
                .environmentObject(notifications)
                .environmentObject(reminder)
                .environmentObject(loginItem)
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
        } label: {
            if settings.showPercentageInMenuBar {
                Label(monitor.snapshot.percentageText, systemImage: monitor.snapshot.statusSymbolName)
            } else {
                Image(systemName: monitor.snapshot.statusSymbolName)
            }
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
