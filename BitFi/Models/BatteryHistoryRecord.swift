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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "24 Hours"
        case .week: "7 Days"
        case .month: "30 Days"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .day: 24 * 60 * 60
        case .week: 7 * 24 * 60 * 60
        case .month: 30 * 24 * 60 * 60
        }
    }
}

struct BatteryHistorySegment: Identifiable {
    let id: Int
    let records: [BatteryHistoryRecord]
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
        case .energyLevel: "Energy Level"
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
