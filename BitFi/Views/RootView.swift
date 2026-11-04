import SwiftUI

private enum AppSection: Hashable {
    case overview
    case chargeControls
    case batteryDetails

    var title: String {
        switch self {
        case .overview: "Overview"
        case .chargeControls: "Charge Controls"
        case .batteryDetails: "Battery Details"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: "rectangle.grid.1x2"
        case .chargeControls: "battery.75percent"
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

    @State private var selection: AppSection? = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach([AppSection.overview, .chargeControls, .batteryDetails], id: \.self) { section in
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
        case .batteryDetails:
            BatteryDetailsView()
        }
    }
}
