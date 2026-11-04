import SwiftUI

private enum AppSection: Hashable {
    case overview
    case chargeControls
    case batteryHistory
    case appActivity
    case batteryDetails

    var title: String {
        switch self {
        case .overview: "Overview"
        case .chargeControls: "Charge Controls"
        case .batteryHistory: "Battery History"
        case .appActivity: "App Activity"
        case .batteryDetails: "Battery Details"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: "rectangle.grid.1x2"
        case .chargeControls: "battery.75percent"
        case .batteryHistory: "chart.xyaxis.line"
        case .appActivity: "chart.pie"
        case .batteryDetails: "list.bullet.rectangle"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var monitor: BatteryMonitor
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var notifications: NotificationService
    @EnvironmentObject private var reminder: ChargeReminderEngine
    @EnvironmentObject private var loginItem: LoginItemManager
    @EnvironmentObject private var history: BatteryHistoryStore
    @EnvironmentObject private var activityMonitor: AppActivityMonitor

    @State private var selection: AppSection? = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach([AppSection.overview, .chargeControls, .batteryHistory, .appActivity, .batteryDetails], id: \.self) { section in
                    Label(section.title, systemImage: section.symbolName)
                        .tag(section)
                }
            }
            .navigationTitle("BitFi")
            .listStyle(.sidebar)
        } detail: {
            selectedView
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            monitor.start()
            reminder.start(monitor: monitor, settings: settings)
            history.start(monitor: monitor)
            activityMonitor.start()
            notifications.refreshAuthorization()
            loginItem.refresh()
        }
    }

    @ViewBuilder
    private var selectedView: some View {
        switch selection ?? .overview {
        case .overview:
            OverviewView {
                selection = .chargeControls
            }
        case .chargeControls:
            ChargeControlsView()
        case .batteryHistory:
            BatteryHistoryView()
        case .appActivity:
            AppActivityView()
        case .batteryDetails:
            BatteryDetailsView()
        }
    }
}
