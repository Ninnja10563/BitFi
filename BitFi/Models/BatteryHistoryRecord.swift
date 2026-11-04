import Foundation

struct BatteryHistoryRecord: Codable, Equatable, Identifiable {
    let id: UUID
    let recordedAt: Date
    let percentage: Int
    let isCharging: Bool
    let isConnectedToPower: Bool

    init(snapshot: BatterySnapshot) {
        id = UUID()
        recordedAt = snapshot.updatedAt
        percentage = snapshot.percentage ?? 0
        isCharging = snapshot.isCharging
        isConnectedToPower = snapshot.isConnectedToPower
    }
}

enum BatteryHistoryRange: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case sixMonths
    case year
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "1D"
        case .week: "1W"
        case .month: "1M"
        case .sixMonths: "6M"
        case .year: "1Y"
        case .all: "All"
        }
    }

    var accessibilityTitle: String {
        switch self {
        case .day: "1 Day"
        case .week: "1 Week"
        case .month: "1 Month"
        case .sixMonths: "6 Months"
        case .year: "1 Year"
        case .all: "All Saved History"
        }
    }

    /// `nil` means the complete locally retained history.
    var visibleDuration: TimeInterval? {
        switch self {
        case .day: 24 * 60 * 60
        case .week: 7 * 24 * 60 * 60
        case .month: 30 * 24 * 60 * 60
        case .sixMonths: 183 * 24 * 60 * 60
        case .year: 365 * 24 * 60 * 60
        case .all: nil
        }
    }
}

struct BatteryHistorySegment: Identifiable {
    let id: Int
    let records: [BatteryHistoryRecord]
}

/// Lightweight metadata for a visible history range. Avoids copying retained samples while a chart is hovered.
struct BatteryHistoryWindow {
    let count: Int
    let first: BatteryHistoryRecord?
    let last: BatteryHistoryRecord?

    static let empty = BatteryHistoryWindow(count: 0, first: nil, last: nil)

    var isEmpty: Bool { count == 0 }
}

enum AppActivityMeasure: String, CaseIterable, Identifiable {
    case cpu
    case memory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        }
    }

    var chartTitle: String {
        switch self {
        case .cpu: "CPU activity"
        case .memory: "Memory footprint"
        }
    }
}

enum AppActivityChartMode: String, CaseIterable, Identifiable {
    case cpu
    case memory
    case energyLevel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Memory"
        case .energyLevel: "Battery Level"
        }
    }

    var subtitle: String {
        switch self {
        case .cpu: "Current CPU activity for running app bundles."
        case .memory: "Current resident memory for running app bundles."
        case .energyLevel: "Current device battery charge level."
        }
    }

    var measure: AppActivityMeasure? {
        switch self {
        case .cpu: .cpu
        case .memory: .memory
        case .energyLevel: nil
        }
    }
}

struct AppActivitySlice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let cpuPercent: Double
    let residentMemoryBytes: Int64

    func value(for measure: AppActivityMeasure) -> Double {
        switch measure {
        case .cpu: cpuPercent
        case .memory: Double(residentMemoryBytes)
        }
    }

    func valueText(for measure: AppActivityMeasure) -> String {
        switch measure {
        case .cpu:
            String(format: "%.1f%% CPU", cpuPercent)
        case .memory:
            ByteCountFormatter.string(fromByteCount: residentMemoryBytes, countStyle: .memory)
        }
    }
}
