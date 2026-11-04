import Combine
import Foundation
import UserNotifications

@MainActor
final class NotificationService: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    var authorizationTitle: String {
        switch authorizationStatus {
        case .authorized: "Allowed"
        case .provisional: "Deliver quietly"
        case .ephemeral: "Temporary"
        case .denied: "Not allowed"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }

    func refreshAuthorization() {
        Task {
            let settings = await center.notificationSettings()
            authorizationStatus = settings.authorizationStatus
        }
    }

    func requestAuthorization() {
        Task {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                // Status refresh below surfaces user-facing denial without masking OS error.
            }
            let settings = await center.notificationSettings()
            authorizationStatus = settings.authorizationStatus
        }
    }

    @discardableResult
    func sendChargeLimitReached(limit: Int, currentPercentage: Int) -> Bool {
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else { return false }

        let content = UNMutableNotificationContent()
        content.title = "Charge limit reached"
        content.body = "Battery is at \(currentPercentage)%. Unplug power to stay near your \(limit)% target."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "charge-limit-reached",
            content: content,
            trigger: nil
        )
        center.add(request)
        return true
    }
}
