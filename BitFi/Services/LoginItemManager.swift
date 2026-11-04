import Combine
import Foundation
import ServiceManagement

@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage: String?

    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled

        switch status {
        case .enabled, .notRegistered:
            statusMessage = nil
        case .requiresApproval:
            statusMessage = "Approval required in System Settings › General › Login Items."
        case .notFound:
            statusMessage = "Login item unavailable in this app bundle."
        @unknown default:
            statusMessage = "Login item status unavailable."
        }
    }

    func setEnabled(_ shouldEnable: Bool) {
        do {
            if shouldEnable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
        refresh()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
