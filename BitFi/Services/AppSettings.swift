import Foundation
import Combine

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let chargeReminderEnabled = "chargeReminderEnabled"
        static let chargeLimit = "chargeLimit"
        static let notificationsEnabled = "notificationsEnabled"
        static let showPercentageInMenuBar = "showPercentageInMenuBar"
    }

    private let defaults: UserDefaults

    @Published var isChargeReminderEnabled: Bool {
        didSet { defaults.set(isChargeReminderEnabled, forKey: Key.chargeReminderEnabled) }
    }

    @Published var chargeLimit: Double {
        didSet {
            let normalized = Self.normalizedLimit(chargeLimit)
            if chargeLimit != normalized {
                chargeLimit = normalized
                return
            }
            defaults.set(chargeLimit, forKey: Key.chargeLimit)
        }
    }

    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) }
    }

    @Published var showPercentageInMenuBar: Bool {
        didSet { defaults.set(showPercentageInMenuBar, forKey: Key.showPercentageInMenuBar) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isChargeReminderEnabled = defaults.object(forKey: Key.chargeReminderEnabled) as? Bool ?? true
        chargeLimit = Self.normalizedLimit(defaults.object(forKey: Key.chargeLimit) as? Double ?? 80)
        notificationsEnabled = defaults.object(forKey: Key.notificationsEnabled) as? Bool ?? true
        showPercentageInMenuBar = defaults.object(forKey: Key.showPercentageInMenuBar) as? Bool ?? true
    }

    func setChargeLimit(_ value: Double) {
        chargeLimit = Self.normalizedLimit(value)
    }

    func resetChargeSettings() {
        isChargeReminderEnabled = true
        chargeLimit = 80
    }

    private static func normalizedLimit(_ value: Double) -> Double {
        min(max(value.rounded(), 50), 100)
    }
}
