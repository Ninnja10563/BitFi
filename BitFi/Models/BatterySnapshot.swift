import Foundation

enum PowerSourceKind: Equatable {
    case acPower
    case battery
    case ups
    case unavailable
    case other(String)

    init(powerSourceState: String?) {
        switch powerSourceState {
        case "AC Power":
            self = .acPower
        case "Battery Power":
            self = .battery
        case "UPS Power":
            self = .ups
        case .none:
            self = .unavailable
        case let value?:
            self = .other(value)
        }
    }

    var title: String {
        switch self {
        case .acPower: "AC Power"
        case .battery: "Battery Power"
        case .ups: "UPS Power"
        case .unavailable: "Unavailable"
        case let .other(value): value
        }
    }

    var symbolName: String {
        switch self {
        case .acPower: "powerplug"
        case .battery: "battery.50"
        case .ups: "bolt.horizontal.circle"
        case .unavailable: "battery.0"
        case .other: "bolt.circle"
        }
    }
}

struct BatterySnapshot: Equatable {
    let currentCapacity: Int?
    let maximumCapacity: Int?
    let designCapacity: Int?
    let powerSource: PowerSourceKind
    let isCharging: Bool
    let isCharged: Bool
    let timeToEmptyMinutes: Int?
    let timeToFullChargeMinutes: Int?
    let cycleCount: Int?
    let health: String?
    let healthCondition: String?
    let temperatureCelsius: Double?
    let voltageMillivolts: Int?
    let amperageMilliamps: Int?
    let updatedAt: Date
    let unavailableReason: String?

    static let unavailable = BatterySnapshot(
        currentCapacity: nil,
        maximumCapacity: nil,
        designCapacity: nil,
        powerSource: .unavailable,
        isCharging: false,
        isCharged: false,
        timeToEmptyMinutes: nil,
        timeToFullChargeMinutes: nil,
        cycleCount: nil,
        health: nil,
        healthCondition: nil,
        temperatureCelsius: nil,
        voltageMillivolts: nil,
        amperageMilliamps: nil,
        updatedAt: .now,
        unavailableReason: "No internal battery reported by macOS."
    )

    var isAvailable: Bool {
        currentCapacity != nil
    }

    var percentage: Int? {
        guard let currentCapacity, let maximumCapacity, maximumCapacity > 0 else { return nil }
        return Int((Double(currentCapacity) / Double(maximumCapacity) * 100).rounded())
    }

    var percentageText: String {
        percentage.map { "\($0)%" } ?? "—"
    }

    var isConnectedToPower: Bool {
        powerSource == .acPower
    }

    var statusTitle: String {
        if isCharged { return "Fully charged" }
        if isCharging { return "Charging" }
        if isConnectedToPower { return "Connected to power" }
        if powerSource == .battery { return "On battery" }
        return powerSource.title
    }

    var statusSymbolName: String {
        if isCharging { return "bolt.fill" }
        if isCharged { return "checkmark.circle.fill" }
        return powerSource.symbolName
    }

    /// Closest native SF Symbol level for current live IOKit capacity.
    var batterySymbolName: String {
        guard let percentage else { return "battery.0" }

        switch percentage {
        case ...10:
            return "battery.0"
        case 11...35:
            return "battery.25"
        case 36...60:
            return "battery.50"
        case 61...85:
            return "battery.75"
        default:
            return "battery.100"
        }
    }

    var healthText: String {
        healthCondition ?? health ?? "Unavailable"
    }

    /// Full-charge capacity divided by design capacity when macOS publishes both.
    var healthCapacityPercentage: Int? {
        guard let maximumCapacity, let designCapacity, designCapacity > 0 else { return nil }
        return Int((Double(maximumCapacity) / Double(designCapacity) * 100).rounded())
    }

    var healthCapacityText: String {
        healthCapacityPercentage.map { "\($0)%" } ?? "Unavailable"
    }

    var healthSummaryText: String {
        guard let healthCapacityPercentage else { return healthText }
        let condition = healthCondition ?? health
        return condition.map { "\($0) · \(healthCapacityPercentage)%" } ?? "\(healthCapacityPercentage)%"
    }

    var temperatureText: String {
        guard let temperatureCelsius else { return "Unavailable" }
        return String(format: "%.1f°C", temperatureCelsius)
    }

    var voltageText: String {
        guard let voltageMillivolts else { return "Unavailable" }
        return String(format: "%.2f V", Double(voltageMillivolts) / 1_000)
    }

    var amperageText: String {
        guard let amperageMilliamps else { return "Unavailable" }
        return String(format: "%+d mA", amperageMilliamps)
    }

    var timeToEmptyText: String {
        Self.durationText(minutes: timeToEmptyMinutes)
    }

    var timeToFullText: String {
        Self.durationText(minutes: timeToFullChargeMinutes)
    }

    private static func durationText(minutes: Int?) -> String {
        guard let minutes, minutes >= 0 else { return "Unavailable" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) hr \(minutes % 60) min"
    }
}
